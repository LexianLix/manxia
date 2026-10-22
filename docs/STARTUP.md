# Android 启动故障记录

## v0.2.3 的复现

2026-10-22 收到用户反馈：ARM64 安装包在手机上一直白屏。

对 GitHub 公开的 v0.2.3 x86_64 Release APK 做独立安装测试，Android 11（API 30）首屏持续纯白，Android 15（API 35）停留在系统启动画面。两组日志均在 `SharedPreferences.getInstance()` 路径出现：

```text
NoSuchMethodError: no non-static method
SharedPreferencesApiRegistrar.getAll(...;Lkotlin/coroutines/Continuation;)Ljava/lang/Object;
```

[失败运行及截图、日志附件](https://github.com/LexianLix/manxia/actions/runs/39722024214)。网页、单元测试、APK 编译和签名检查此前通过，但没有覆盖 Release 在 Android 上实际启动。

## 原因及修复

锁定的 `shared_preferences_android 2.5.1` 使用 Pigeon JNI。其生成类带有 `@Keep`，但 JNI 按名称查找的 Kotlin 运行时类型没有完整的保留规则；R8 对 `Continuation` 等类型改名后，方法签名与 Dart 绑定中的名称不再一致。此问题影响 Release；Profile 的插件调用不经过相同混淆。

上游于 2026-10-21 合并了[同一问题的修复](https://github.com/flutter/packages/pull/13311)。本项目在 `android/app/proguard-rules.pro` 保留六个 JNI 所需类型。没有关闭 R8 或更换存储后端，现有偏好设置和书库路径不变。

v0.2.4 同时将初始化移到可见启动界面之后。本地插件、目录及书架读取失败会显示所处阶段，提供重试和诊断复制。单阶段等待上限为 15 秒；重试不会用空白设置覆盖已保存内容。离线库在取得存储后才注册全局回调，防止超时返回后干扰下一次重试。

## 验证方法

`Prepare Android release` 在构建各架构未签名 APK 后，将 x86_64 的副本用临时测试密钥签名，在 Android 11 / 15 模拟器安装并冷启动。临时签名包仅用于 CI，不作为发行附件；公开 APK 仍使用本机保存的固定项目密钥签名。

`Verify installed Android startup` 可选择公开发行版本，下载并测试实际发布的签名 APK。可选 `build_run` 用于发布前测试对应构建的副本；不填时始终下载公开发行附件。默认矩阵覆盖 Android 11 / 15 的 x86_64，两个工作流都保留截图、logcat、UI 树和判定 JSON。

首屏通过条件包含应用处于前台、出现“我的书架 / 书架 / 设置”控件、实际截图非空，以及没有未处理启动异常。原先依据颜色数量和深色像素占比的检测，会把封面未联网时的浅色纸质书架误判为未加载，现已用实际控件取代该阈值；原版白屏仍被拒绝。v0.2.4 的[独立安装与重开检查](https://github.com/LexianLix/manxia/actions/runs/39723585901)使用新判定。

该次 Android 11 / 15 的 x86_64 首次启动及重开均通过，日志无启动异常。额外尝试 Android 11 的 ARM64 转译时，`ndk_translation` 报 `Undefined instruction 0x5ea1b800` 并触发 SIGILL，未进入首屏；此项失败保留在同次运行中，不计入通过项。现在转译仅通过 `arm64_translation` 手动开启，不能代替物理 ARM64 或用户 iQOO 手机测试。

发布后直接下载 GitHub 上使用项目固定证书签名的 v0.2.4 APK，再次在 Android 11 / 15 的 x86_64 模拟器安装、首启和重开，[两组均通过](https://github.com/LexianLix/manxia/actions/runs/39724187144)，未重新签名或替换应用入口。公开附件的 GitHub SHA-256 与本机签名包一致，发行清单下载后逐字节一致。

本地连接专用测试设备或模拟器后，也可运行：

```bash
python -m pip install Pillow
python tools/android-startup-smoke.py Manxia-0.2.4-x86_64.apk
```

手机请替换为相应架构的 APK。本命令安装/替换测试应用并启动，不清除已有应用数据；请使用专用测试设备。脚本拒绝没有实际首屏内容的白屏、仅系统启动图，以及含未处理启动异常的结果。

模拟器结果不能代替各厂商 ARM64 手机的实际验收。覆盖升级、完整阅读、设备按键与体感仍需对应设备测试。


## v0.3.0 的 x86 模拟器兼容

Flutter 3.47 的 Impeller OpenGLES 在 Linux x86 软件 AVD 上可能导致模拟器退出，见[上游报告](https://github.com/flutter/flutter/issues/192736)。本项目同 APK 对照中，默认后端第三次启动失联，而 Skia 三次通过；随后默认发行流程在 Android 11 / 15 各连续三次通过。

`MainActivity.getFlutterShellArgs` 仅对 x86 / x86_64 且硬件标识为 ranchu / goldfish 的 AVD 关闭 Impeller，物理设备保持平台默认。常规发行检查不通过 Intent 指定后端，确认兼容处理来自安装包。`Diagnose Android emulator renderer` 工作流可对指定历史构建做同包对照；`--renderer skia` 仅用于诊断。

检查同时核对标题的实际像素，保留原始截图与 RGB 预览。此前将 PNG 预览显示异常误认为缺绘的判断已通过原始像素复核更正，见验证记录。升级 Flutter 后应重新评估这项模拟器兼容处理。
