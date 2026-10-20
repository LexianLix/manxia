# 漫匣 · Manxia

[源码](https://github.com/LexianLix/manxia) · [自动构建与 APK](https://github.com/LexianLix/manxia/actions) · [42 项实现状态](docs/IMPLEMENTATION.md) · [使用指南](docs/USER_GUIDE.md)

把喜欢的故事，留在手边。

一个以实体书质感为中心的 Flutter 漫画阅读器。默认动漫屋，Android 为目标平台，提供手机与桌面布局的浏览器预览。当前为 **0.2.1 开发版**。

本轮重做悬浮毛玻璃导航、可拖动的弹簧选中块、页面失焦过渡、书架入场与跟手倾斜，以及从所点书籍位置开始的开书动画。详见 [玻璃与动效调整](docs/MOTION.md)。

## 已接入的主要功能

- 惯性循环立体书架、弹簧吸附、抽书开封面、随指针变化的透视/光照、封面取色、收藏飞入；高档材质支持毛玻璃及 Impeller 折射，其他渲染器使用模糊回退。
- 每日精选、原站四种榜单、收藏追更、26 种真实分类、连载状态/排序/翻页、完结与主题书单、个人推荐、搜索历史和本地候选提示。
- 连续条漫及图片内位置续读、横/竖分页、宽屏双页、章节面板、多书签/笔记/页面收藏、图片预载、曲面纸页翻动、裁白边、缩放、自动滚动、亮度/暖色/背景、逐本偏好。
- 分组、标签、状态、排序、拖动和批量整理，系列套装；按日期的阅读历史与检索。
- 图片、文件夹（原生端）、ZIP/CBZ、PDF 导入；章节下载队列、并发控制、暂停后续传/重试、离线阅读、空间统计、CBZ 导出。
- JSON 资料备份、带图片与校验清单的离线 ZIP 书库备份；合并较新记录并保留删除标记。
- WebDAV 配置与带 ETag 的元数据合并、自定义静态 HTML 漫画源、来源诊断、GitHub 版本查询、大字号/高对比度及主要界面的中英/繁体切换。

首次收藏为空时显示标明“演示书架”的示例目录；真实收藏后切换为个人书架。每日推荐来自目录选取，榜单保持原站顺序，不生成虚构热度。源站不可达时显示有日期的缓存提示。

这是功能集成中的开发版，**不代表 42 项均已通过真机/实际网盘验收**。体感、折射性能、音量键、旋转、正式签名升级尚需 Android 真机；WebDAV 尚需实际服务账号。CBR 没有接入。完整边界见实现状态和验收记录。

## Windows 本地预览

需要 Flutter **3.47.7 / Dart 3.13.5**、Node.js 22+。本机已有 Flutter 时：

```powershell
Set-Location 'D:\project\comic'
.\启动预览.ps1 -Rebuild
```

打开 <http://127.0.0.1:4173>，保留终端。之后无需重新编译可直接运行 `.\启动预览.ps1`。

其他平台或手动构建：

```sh
flutter pub get
npm ci --ignore-scripts
node tools/prepare-web.mjs
flutter build web --no-web-resources-cdn --no-wasm-dry-run
node tools/offline-shell.mjs
node tools/preview.mjs
```

PDF.js 本地组件在构建前准备，应用资源离线缓存由独立的 `sw.js` 管理。首次成功加载资源后可离线打开应用和已下载/导入的漫画；浏览器清理站点数据会移除本机数据，先导出备份。浏览器存储、127.0.0.1 和 localhost 是不同空间。

预览服务只监听本机，负责浏览器跨域访问。Android 直接访问源站。GitHub Pages 或单纯 `flutter run -d chrome` 不提供这些 `/api` 接口。

## Android 构建与安装

GitHub Actions 检查成功后，进入该次运行底部 **Artifacts → manxia-android-debug**，解压得到调试 APK。下载步骤见 [GitHub 指南](docs/GITHUB.md)。调试包用于试用，跨运行的临时调试证书不保证可覆盖安装。

本机需安装 JDK 17 与 Android SDK，并完成 `flutter doctor` 中的开发环境配置：

```powershell
.\tools\Build-Android.ps1
```

正式签名需先运行 `.\tools\Create-Signing.ps1`，私下备份密钥和配置，再运行 `.\tools\Build-Android.ps1 -Release`。不会自动用临时调试证书生成 release。签名材料不进入 Git；详细升级和迁移说明见 [发布指南](docs/RELEASE.md)。

## 验证

```sh
flutter analyze --no-pub
flutter test --timeout 30s
node --test tools/preview.test.mjs
dart run tool/probe.dart
```

前三项离线执行。最后一项访问动漫屋首页、分类筛选和翻页、搜索、目录、章节及首图，结果保存在不提交的 `artifacts/source-probe.json`。站点内容与网络会变化；单次通过只证明该次样本。

## 目录

```text
lib/data/       漫画来源、推荐、收藏、同步、下载与备份
lib/platform/   原生文件存储 / 浏览器缓存存储
lib/ui/         实体书绘制、界面与阅读器
shaders/        支持的渲染器上的玻璃折射
assets/         演示目录、来源元数据快照、字体及许可
tools/          预览代理、Web 资源准备、Android 签名和构建脚本
tool/           来源探测与快照工具
test/           数据合并、来源解析、下载恢复、布局及阅读交互检查
docs/           使用、状态、验收与发布说明
```

## 许可

应用代码独立实现，使用 MIT。视觉灵感来自 [Wenku8_Flutter](https://github.com/mikufoxxx/Wenku8_Flutter)，未复制其应用代码。思源宋体使用 SIL OFL 1.1，浏览器 PDF.js 使用 Apache 2.0。远程漫画元数据和图片不属于应用代码许可，仓库不包含漫画正文图片。见 [NOTICE](NOTICE)。
