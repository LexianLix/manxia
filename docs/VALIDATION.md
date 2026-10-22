# 验证记录

## 0.3.0 交互与插件 · 2026-10-22

本地静态分析无问题，51 项 Flutter、7 项 Node 和 3 项 Python 校验测试通过。覆盖插件目录及字节哈希、生命周期与配置、源解析停用、逐本偏好优先、损坏状态隔离、下载校验拒绝，以及取消手势、导航重排后的过渡方向、液滴连续反向和书本落位展开。绘制校验会拒绝只有语义节点、没有可见标题的截图。

390 × 844 Web 实际查看满幅封面、五栏导航、翻开与反向合书、插件商城和新增设置；书架横向拖动进入发现、反向返回，以及插件→设置连续切换均实测。安装蓝调主题后即时变化，卸载后恢复原主题。README 动图和预览图来自 Web 实录；最终导航录屏在本机 `artifacts/v03-final-navigation.gif`。辅助功能语义层开启时鼠标拖动由该层接管。

源码 `9c91621795a0a5facd8e0475394ba6fe4d974598` 的三个架构 Release 包在[发行构建](https://github.com/LexianLix/manxia/actions/runs/39757903743)生成，版本 `0.3.0+9`。Android 11 / 15 的 x86_64 默认启动各连续三次通过，前台状态、书架控件、标题像素及日志均正常；没有测试 Intent 覆盖。日志确认 AVD 自行选用 Skia，实际 RGB 截图显示完整书架及五栏导航。CI 的临时测试签名不作为发行附件。

三包在本机核对来源哈希、ABI、最低 SDK 24 后使用既有项目证书签名，版本码为 1009 / 2009 / 4009；证书 SHA-256 为 `9618d4bb9b8ce8045c502c79fea0b8c2eb4d14f0a6ccb380cf22ac2bccdbc091`。

[公开签名包复测](https://github.com/LexianLix/manxia/actions/runs/39760422829)直接下载 GitHub v0.3.0 附件，不重新签名。Android 11 / 15 各首次启动及两次重开均通过，标题可见、书架控件齐全、启动异常与命令错误为空。五个公开附件 HTTP 200，GitHub SHA-256 与本机产物一致，发行清单公开下载后逐字节一致。

插件 API 1 是声明式主题、阅读预设、静态 HTML 源和导航扩展，不执行第三方 JS / Dart 或替换渲染器。模拟器启动与 Web 验证不能代替物理 iQOO / ARM64、完整阅读、设备按键、帧率、功耗和发热验收；ARM64 转译的旧 SIGILL 不计入通过。

## 0.2.4 Android 启动 · 2026-10-22

v0.2.3 的公开 Release APK 在 Android 11 / 15 模拟器复现启动故障：设置插件 JNI 调用抛出 `NoSuchMethodError`，未进入书架。补上 Kotlin 运行时保留规则后，同样的 Release 路径已能显示书架，错误消失。[原版失败记录](https://github.com/LexianLix/manxia/actions/runs/39722024214)。

v0.2.4 本地静态分析无问题，41 项 Flutter 测试和 6 项 Node 测试通过，Web release 编译通过；新增测试覆盖初始化等待时的可见首帧、JNI 异常后的重试入口和原设置保留。三个架构的 Release 编译及自动测试见[构建作业](https://github.com/LexianLix/manxia/actions/runs/39722839194/job/119640004677)。

原颜色阈值检测对封面未联网时的浅色书架误报，因此改为读取“我的书架 / 书架 / 设置”控件，同时核对前台应用、截图及异常日志。已用保存的原版白屏 UI 树和修复版书架 UI 树验证负例、正例。安装与重开结果以[独立启动检查](https://github.com/LexianLix/manxia/actions/runs/39723585901)为准。

Android 11 / 15 的 x86_64 首次启动和重开四次均通过，UI 树含书架控件，启动异常列表为空。ARM64 转译尝试因 `ndk_translation` 的 `Undefined instruction` / SIGILL 失败，未计入通过项；相关日志保留，转译改为手动实验选项。没有将这个结果表述为 ARM64 真机通过。

公开发行后另行下载实际签名附件，[安装与启动验证全部通过](https://github.com/LexianLix/manxia/actions/runs/39724187144)：Android 11 / 15 的 x86_64 首启及重开均有书架控件，异常列表为空。三 APK、哈希清单和发行清单的公开下载 HTTP 200；GitHub 附件摘要与本机签名产物一致，公开发行清单逐字节一致。项目证书沿用既往版本，版本码递增为 1006 / 2006 / 4006。

截图预览判断更正：先前以为 API 30 顶部文字缺失；对原始 PNG 裁区和 RGB 预览重新检查，v0.2.4 的首启 / 重开标题均完整，标题区域墨色比例为 17.45%。该项没有复现出应用绘制故障。启动控件检查仍不等同于所有交互和真机帧率验收。

故障原因和复测命令见 [STARTUP.md](STARTUP.md)。模拟器和 ARM 转译结果不代替用户的 iQOO 真机验收。

## 0.2.3 动效衔接 · 2026-10-21

本地 39 项 Flutter 测试通过。新增 6 项覆盖：快速切页时所有可见页面的位置与透明度连续、连续选书不丢操作目标、开书中途返回、取消收藏撤回飞入、宽屏详情加载资料时封面位置固定、阅读工具栏反复显隐时正文视口和阅读进度不变。

Web release 已编译并在 390 × 844 浏览器中录制开书、返回和快速切页。录屏验证操作衔接，不能据此宣称 Android 真机达到某个帧率。版本构建提交、APK 哈希与签名记录以 [v0.2.3 发行清单](https://github.com/LexianLix/manxia/releases/tag/v0.2.3) 为准。

浏览器续读自制三页 CBZ 至 3 / 3，收起工具栏后仍为 3 / 3；前后截图的正文区域（x=0–390，y=65–735）逐像素一致。截图为本机 artifacts/motion-reader-before.png 与 motion-reader-after.png，不使用远程漫画正文。

## 0.2.2 公开发行 · 2026-10-21

Release 准备工作流已通过代码分析、33 项 Flutter 测试、6 项 Node 测试和三种架构的 Release 编译。安装包使用本机项目固定密钥签名，apksigner 验证 v2/v3 签名通过，zipalign 的 16 KB 对齐检查通过。包名为 io.manxia.manxia，版本 0.2.2，最低 API 24；架构分包版本码为 ARMv7 1004、ARM64 2004、x86_64 4004。

已核对 Release 包包含对应架构的 libapp.so，不包含 Debug 的 kernel_blob.bin。实际发布包的完整 SHA-256、签名证书指纹、源码提交和构建运行记录在 [发行页](https://github.com/LexianLix/manxia/releases/tag/v0.2.2) 的 release-manifest.json 与 SHA256SUMS.txt 中提供。上述检查不代替真机安装、流畅度、覆盖升级和实际 WebDAV 服务验收。

README 的三张预览图采集于 0.2.2 Web release，视口 390 × 844；用于展示当前书架、排行榜与设置，不作为 Android 真机截图。

以下保留各开发阶段的历史检查记录。

## 0.2.2 性能复核

提交 f1de1b0：静态分析无问题，33 项 Flutter 测试通过；新增绘制底图缓存、32 像素取色缓存、返回书架保留场景，以及高级设置按需加载的回归检查。本地 Web release 构建成功，浏览器无控制台错误。

固定场景的浏览器主线程帧工作 P95 从 17.299 ms 降至 12.204 ms；首次设置页仍有一次 59.560 ms 长帧。已访问页面后重复操作的 P95 为 10.780 ms，最大 26.107 ms，通过本机检查。完整条件与保留的失败结果见 [性能说明](PERFORMANCE.md)。这些不是 Android/GPU FPS 结论。

本轮 [Actions 运行](https://github.com/LexianLix/manxia/actions/runs/39435016723) 全部通过：静态分析、33 项 Flutter 测试、6 项网关测试、Web 与 Profile/AOT Android 构建。安装包已下载至本机 artifacts/android-0.2.2/app-profile.apk，大小 95589904 字节，已逐文件摘要确认与构建 ZIP 中的 APK 一致；包含 arm64-v8a、armeabi-v7a、x86_64 的 libapp.so，不含 Debug 的 kernel_blob.bin。SHA-256 为 aa9ac0dd5b68660334e9cf9325c92c455e8c10a94d59ba6658676a3a6ab51e8c。真机帧率、触感与具体设备表现仍需实机确认。

实际比较 APK Signing Block 中的证书，新测试包与本机保存的 0.2.1 调试包签名不同。换装前需先导出完整书库并妥善保存；本轮没有执行卸载或删除用户书库。迁移步骤见发布指南。

## 0.2.1 玻璃与动效复核

代码提交 df08122：静态分析无问题，30 项 Flutter 测试通过；新增底栏拖动释放/取消、减少动画/安全区、开书详情初始化次数的检查。Web release 已重新编译。

390 × 844 的真实浏览器中检查了悬浮毛玻璃底栏，封面内容在底栏后方可见并被模糊；实际拖动导航由发现页返回书架、点书打开详情并返回，控制台无错误。使用浏览器逐帧录制了导航切换和直接点书开封面，两段分别保存在本机 artifacts/frosted-navigation-motion.gif 与 book-opening-motion.gif。这些是实际运行记录，不是设计稿。

本轮 [df08122 Actions](https://github.com/LexianLix/manxia/actions/runs/39429969493) 全部通过：30 项 Flutter 测试、6 项网关测试、静态分析、Web 和 Android 调试 APK。0.2.1 安装包已下载至 artifacts/android-0.2.1/app-debug.apk，并确认与构建 ZIP 中的 APK 完全一致；大小 177123843 字节，SHA-256 为 d26955b3bacba5bf152b9c7a73ccf323004b98e9e0abc43890d6681301d0c2ff。夜间模式底栏已在浏览器检查并恢复原来的浅色设置。原生动效与折射的真机边界仍见下文。

## 当前本地结果

- Flutter 3.47.7 / Dart 3.13.5，静态分析无问题。
- 26 项 Flutter 测试通过：来源解析/解码、分类组合链接、日期推荐、备份合并与删除标记、完整图片备份校验、ZIP 自然排序/CBZ 导出、下载失败续传、乱序下载后的离线目录顺序、WebDAV ETag 与二进制书库传输、长图内位置恢复、裁白边、分页记录、双页末尾导航及从右页恢复、390/754/1440 布局及英文 150% 字号。
- 6 项 Node 网关测试通过：限制/拒绝/去重缓存、声明式来源注册、分类分页参数、WebDAV 二进制流传输及条件写入。
- Web release 编译成功，PDF.js 已本地打包；独立离线 app shell 生成。曾发现默认 Flutter worker 与自定义 worker 互相替换引发重载，现改用单一 worker，浏览器切页恢复稳定。
- 签名脚本在本机生成 RSA-3072/SHA256withRSA 密钥，确认 .private/manxia-release.jks 与 android/key.properties 被忽略。没有将其提交或上传到 GitHub。

## 真实动漫屋样本

最近一次 tool/probe.dart：80 本首页、26 类、分类第一页 10 本/下一页 10 本、三种排序及三种状态、搜索 22 项、《冰之城壁》119 个目录条目、第 1 话 15 张图片。首图 HTTP 200 / image/jpeg / 133848 字节。

这只证明当前样本。站点曾阶段性超时；缓存目录会标明日期，不把快照显示当作在线刷新成功。

## 浏览器

- 实际渲染立体书架、每日推荐、四榜与题材/状态筛选；手机 390 × 844 与桌面 1280 × 720 均已查看。
- 通过真实文件选择器导入自制三页 CBZ，显示页码 1/3，翻到 2/3 并实际显示第二、三页。
- 导入自制两页 PDF，PDF.js 在本地转图成功并显示 1/2 及页面文字。
- 仅对 QA 页模拟断网，刷新后应用仍启动、导入书架/封面/阅读记录恢复，继续阅读实际显示本地 PDF；测试后恢复网络。
- 双页的中缝过宽问题已在视觉检查中发现并修正为靠中线排布。
- 截图保存在 artifacts/mobile-discovery-0.2.png、pdf-import-reader.png、offline-reload-reader.png 等本机文件，不提交漫画图片。

## Android 与真实服务

最终代码提交 b51bacd 已通过 GitHub Actions 的静态分析、26 项 Flutter 测试、6 项网关测试、Web 和 Android 调试 APK 构建：[完整运行记录](https://github.com/LexianLix/manxia/actions/runs/39387721366)。调试包已下载至本机 artifacts/android-0.2/app-debug.apk，并逐字节确认与该次构建的 ZIP 内 APK 一致；同目录 build-info.json 记录提交、运行编号、大小及 SHA-256。

尚无连接的 Android 真机；折射后端、传感器、音量键、触感、常亮、旋转、实际性能、签名覆盖升级均未验收。WebDAV 尚无实际服务账号，已通过模拟协议与图片字节往返测试，不能据此宣称兼容具体网盘。

品牌补充：Android 普通/自适应图标与 Web 图标统一为深绿“匣”字标，源自项目内 OFL 字体；生成脚本位于 tools/generate-icons.py。

纸页检查：浏览器中开启纸页弯曲后，实际从 2/3 翻至 3/3，下一页正确禁用，控制台无渲染错误。

离线目录检查：保存原站完整章节顺序；用户先下载旧章、再下载新章，重启后仍按原站顺序展示。书库 ZIP 同时携带目录，未来不支持的资料版本在写入图片前拒绝。

双页最终检查：在桌面宽度恢复到第三页时，实际显示相邻的第二、三页，页码为 2–3 / 3，下一页禁用，控制台无渲染错误；截图为 artifacts/double-page-reader-0.2.png。

## 模拟器渲染兼容的诊断证据

[同 APK 后端对照](https://github.com/LexianLix/manxia/actions/runs/39755753262)只改变启动 Intent：默认 Impeller OpenGLES 在第三次冷启动时 UI 检测、日志超时且模拟器失联；Skia 连续三次通过。与 [Flutter 上游 x86 软件模拟器报告](https://github.com/flutter/flutter/issues/192736)相近。仅覆盖旧系统时，API35 仍在[构建号 8 复测](https://github.com/LexianLix/manxia/actions/runs/39756414660)失联，因此最终策略限定为 x86 / x86_64 且硬件标识 ranchu / goldfish 的 AVD，覆盖所有系统版本；物理设备保留平台默认后端。

模拟器启动检查会保存 PNG、RGB 预览、UI 树、日志、标题像素结果及命令超时。诊断命令失败不会覆盖前一项错误；正常发行检查不传渲染覆盖参数。后续升级 Flutter 时需复测该兼容策略。
