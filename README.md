# 漫匣 · Manxia

[GitHub 源码](https://github.com/LexianLix/manxia) · [功能选择清单](docs/FEATURE_CHOICES.md) · [自动构建](https://github.com/LexianLix/manxia/actions)

把喜欢的故事，留在手边。

一个以实体书质感为中心的 Flutter 漫画阅读器。默认漫画源为动漫屋，Android 为目标平台，同时提供可操作的浏览器预览。

## 当前可用

当前为早期开发版本，动效与材质仅完成基础实现。完整待选范围见 [功能选择清单](docs/FEATURE_CHOICES.md)。

- 纸质立体书架基础版：固定投影的书脊/纸张厚度绘制、抽书位移与封面展开、Hero 和淡入转场。惯性循环书架、真实开书动作和玻璃折射尚未实现。
- 立体 / 封面网格切换，手机底部导航与宽屏侧边导航。
- 动漫屋真实首页、搜索、漫画详情、分组章节目录。
- 公开章节图片阅读、横向 / 纵向逐页翻阅、左右阅读方向、双指缩放。
- 收藏、阅读历史、页码续读，保存在当前设备。
- 夜间外观、动效开关、系统减少动画偏好。

首次打开是标明“演示书架”的目录快照；第一次真实收藏后切换为个人书架。演示收藏没有预设阅读记录。发现、搜索、详情与章节图片使用真实来源请求，失败会提示，不能直接读取的章节可打开原站。

## 本地预览（Windows）

需要 Flutter **3.47.7**（Dart 3.13.5）与 Node.js 22 或更新版本。工程首次在此版本验证；SDK 的安装说明见 [Flutter 官方文档](https://docs.flutter.dev/install/manual)。

```powershell
Set-Location 'D:\project\comic'
& 'D:\tools\flutter\bin\flutter.bat' pub get
& 'D:\tools\flutter\bin\flutter.bat' build web --no-web-resources-cdn --no-wasm-dry-run
node tools/preview.mjs
```

打开 <http://127.0.0.1:4173>。终端保持运行；按 Ctrl+C 停止。如果 Flutter 已加入 PATH，可直接用 `flutter` 替换完整路径。

也可在项目目录运行 `./启动预览.ps1`；需要重新编译源码时运行 `./启动预览.ps1 -Rebuild`。

预览服务只绑定本机，负责提供编译产物和动漫屋跨域代理。不需要账号、数据库或第三方付费服务。Android 客户端直接访问动漫屋，不依赖这个预览服务。仅运行 `flutter run -d chrome` 或将静态文件直接放到 GitHub Pages，并不能提供浏览器版本需要的 `/api` 代理。

## Android

安装 Android Studio、Android SDK 与 JDK 17，完成官方开发环境设置及许可证确认后：

```powershell
flutter doctor
flutter devices
flutter run -d 你的设备ID
flutter build apk --debug
```

调试 APK：`build/app/outputs/flutter-apk/app-debug.apk`。

当前默认 release 配置沿用 Flutter 的开发签名，仅供本机开发；正式发布前需要独立签名、密钥备份和升级安装测试。仓库不会存放签名密钥。CI 提供调试 APK 构建，不代表已经通过 Android 真机验收。

## 检查

```powershell
flutter analyze --no-pub
flutter test --timeout 30s
node --test tools/preview.test.mjs
dart run tool/probe.dart
```

前三项为本地离线检查；最后一项实际访问动漫屋，验证首页、搜索、目录与首张图片。结果保存在忽略提交的 `artifacts/source-probe.json`。站点内容、网络和页面结构会变化，单次通过不等于全部漫画或未来长期可用。

## 工程

```text
lib/data/          漫画模型、动漫屋适配、收藏与阅读记录
lib/ui/            书架、实体书绘制、详情与阅读器
assets/catalog.json  演示缩略图地址与标题，不包含漫画图片
tools/preview.mjs  浏览器预览与受限来源代理
tool/probe.dart    真实来源连通检查
test/             解析、数据恢复、布局与阅读交互检查
docs/             设计说明、GitHub 上传步骤与验收记录
```

## 后续迭代

连续条漫滚动、本地 ZIP/CBZ 导入、离线章节下载管理、真实追更检测与正式签名发布尚未实现。当前重点是立体书架的视觉与在线阅读主流程。

## GitHub 与许可

上传说明见 [docs/GITHUB.md](docs/GITHUB.md)。提交后 GitHub Actions 会运行检查，构建 Web 产物与 Android 调试 APK，可在 Actions 的 Artifacts 中下载。

本项目代码独立实现，使用 MIT 许可。视觉灵感来自 [mikufoxxx/Wenku8_Flutter](https://github.com/mikufoxxx/Wenku8_Flutter)，未复制其应用源码。思源宋体使用 SIL OFL 1.1；动漫屋漫画元数据与远程图片不属于本项目的 MIT 许可内容，详见 [NOTICE](NOTICE)。
