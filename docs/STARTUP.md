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

`Verify installed Android startup` 可选择公开发行版本，下载并测试实际发布的签名 APK。两个工作流都保留截图、logcat、UI 树和判定 JSON。

本地连接专用测试设备或模拟器后，也可运行：

```bash
python -m pip install Pillow
python tools/android-startup-smoke.py Manxia-0.2.4-x86_64.apk
```

手机请替换为相应架构的 APK。本命令安装/替换测试应用并启动，不清除已有应用数据；请使用专用测试设备。脚本拒绝没有实际首屏内容的白屏、仅系统启动图，以及含未处理启动异常的结果。

模拟器结果不能代替各厂商 ARM64 手机的实际验收。覆盖升级、完整阅读、设备按键与体感仍需对应设备测试。
