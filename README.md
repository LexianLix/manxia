<p align="center">
  <img src="web/icons/Icon-512.png" width="96" alt="漫匣图标" />
</p>

<h1 align="center">漫匣 · Manxia</h1>

<p align="center">把喜欢的故事，留在手边。</p>
<p align="center">一个注重书籍质感与阅读体验的 Flutter 漫画阅读器</p>

<p align="center">
  <a href="https://github.com/LexianLix/manxia/releases/latest"><img src="https://img.shields.io/github/v/release/LexianLix/manxia?style=flat-square&color=47745e&cacheSeconds=300" alt="最新发行版" /></a>
  <a href="https://github.com/LexianLix/manxia/actions/workflows/ci.yml"><img src="https://github.com/LexianLix/manxia/actions/workflows/ci.yml/badge.svg?branch=main" alt="构建状态" /></a>
  <img src="https://img.shields.io/badge/Platform-Android-47745e?style=flat-square" alt="Android" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-47745e?style=flat-square" alt="MIT License" /></a>
</p>

<p align="center">
  <a href="https://github.com/LexianLix/manxia/releases/latest">下载安装</a> ·
  <a href="CHANGELOG.md">更新日志</a> ·
  <a href="docs/USER_GUIDE.md">使用指南</a> ·
  <a href="https://github.com/LexianLix/manxia/issues">问题反馈</a> ·
  <a href="docs/RELEASE.md">构建与发布</a>
</p>

## 简介

漫匣面向 Android 手机与平板，将漫画发现、个人书架、本地导入与离线阅读放在一起。奶白与墨绿构成界面的底色，立体书脊、翻开封面的过渡和悬浮毛玻璃导航，让收藏与阅读保留一点实体书的手感。

默认接入动漫屋，支持每日精选、分类搜索和原站榜单；也可以导入自己的图片、CBZ 或 PDF，整理成随身书库。收藏、进度和离线内容保存在本机，可手动备份或配置 WebDAV。

## 界面预览

<p align="center">
  <img src="docs/images/shelf.png" width="30%" alt="立体书架与悬浮玻璃导航" />
  &nbsp;
  <img src="docs/images/discovery.png" width="30%" alt="发现页与人气排行榜" />
  &nbsp;
  <img src="docs/images/settings.png" width="30%" alt="阅读与外观设置" />
</p>

<p align="center"><sub>立体书架 · 发现与排行 · 个性设置。截图来自当前版本的手机尺寸 Web 预览，Android 系统栏与渲染细节可能有所不同。</sub></p>

## 功能特性

- **立体书架**：循环轮播、惯性滚动与弹簧吸附，随指针变化的透视和光照；支持抽书、开封面、收藏飞入，以及列表展示。
- **玻璃界面**：悬浮毛玻璃底栏、可拖动的选中滑块、封面取色与页面过渡；可调整材质质量、减少动效和高对比度。
- **漫画发现**：每日精选、人气／新番／收藏／吐槽榜单，分类、连载状态、排序与翻页；支持书名和作者搜索、搜索历史及收藏追更。
- **沉浸阅读**：连续条漫、横向或竖向分页、左右阅读方向与宽屏双页；支持曲面翻页、缩放、裁白边、自动滚动、图片内位置续读和逐本偏好。
- **阅读工具**：章节目录、多书签、笔记、页面收藏、图片预载，以及亮度、暖色和背景调整。
- **书库整理**：自定义分组、标签、阅读状态、排序、拖动与批量操作；阅读足迹可按日期查看和搜索。
- **离线与导入**：章节下载队列、并发控制、暂停续传、失败重试、缓存统计与 CBZ 导出；支持图片、原生端文件夹、ZIP／CBZ 和 PDF 导入。
- **备份与同步**：JSON 资料备份、包含离线图片及 SHA-256 清单的 ZIP 书库备份；WebDAV 支持元数据合并与完整书库传输。
- **来源与偏好**：可配置静态 HTML 漫画源、检查来源状态；提供大字号及主要界面的简体、繁体和英文切换。

首次打开时会显示标明“演示书架”的示例目录，收藏漫画后切换为个人书架。榜单沿用原站顺序；每日精选与个人推荐从目录选取，不生成虚构热度。

## 下载与更新

当前发行版：**[v0.2.4](https://github.com/LexianLix/manxia/releases/tag/v0.2.4)**，支持 **Android 7.0+**。提供使用固定项目密钥签名的 **Release 模式 APK**，按设备架构分包。

v0.2.4 修复 Android Release 启动白屏；已安装 v0.2.3 的用户请下载相同架构的新包覆盖更新。[故障原因及启动验证](docs/STARTUP.md)。

| 设备 | 安装包 |
| --- | --- |
| 常见 Android 手机、平板（推荐） | [ARM64 · arm64-v8a](https://github.com/LexianLix/manxia/releases/download/v0.2.4/Manxia-0.2.4-arm64-v8a.apk) |
| 旧款 32 位 ARM 设备 | [ARMv7 · armeabi-v7a](https://github.com/LexianLix/manxia/releases/download/v0.2.4/Manxia-0.2.4-armeabi-v7a.apk) |
| x86_64 设备或模拟器 | [x86_64](https://github.com/LexianLix/manxia/releases/download/v0.2.4/Manxia-0.2.4-x86_64.apk) |
| 下载完整性校验 | [SHA256SUMS.txt](https://github.com/LexianLix/manxia/releases/download/v0.2.4/SHA256SUMS.txt) |

下载对应 APK 后安装即可。设置中的“检查更新”会查询 GitHub 最新发行版，并提供下载入口。历史版本、源码归档和发行说明见 [GitHub Releases](https://github.com/LexianLix/manxia/releases)。

**从旧测试包迁移**：旧 Debug／Profile 包使用临时证书，无法保证覆盖安装。请先在旧版导出完整离线书库 ZIP 和资料 JSON，保存到应用外，再卸载旧包、安装发行版并导入备份。WebDAV 密码需重新填写。详见 [升级与恢复](docs/RELEASE.md#升级与恢复)。

## 使用说明

| 想做什么 | 从这里开始 |
| --- | --- |
| 找漫画、收藏、阅读与导入 | [使用指南](docs/USER_GUIDE.md) |
| 备份、换机与安装包签名 | [发布与迁移](docs/RELEASE.md) |
| 配置默认源或自定义来源 | [漫画来源](docs/SOURCES.md) |
| 调整玻璃、动画和性能 | [界面动效](docs/MOTION.md) · [性能说明](docs/PERFORMANCE.md) |
| 了解功能支持范围 | [功能实现状态](docs/IMPLEMENTATION.md) · [验证记录](docs/VALIDATION.md) |

0.2.x 仍在持续完善：WebDAV 尚待真实服务账号验收，体感、音量键、旋转和覆盖升级尚待 Android 真机验证；CBR 暂不支持。在线内容的可用性取决于来源站点与网络。浏览器清理站点数据会移除本地书库，请定期导出备份。

## 从源码构建

开发环境：**Flutter 3.47.7 / Dart 3.13.5**；Android 构建另需 **JDK 17 与 Android SDK**。Web 预览使用 **Node.js 22+**。

```sh
git clone https://github.com/LexianLix/manxia.git
cd manxia
flutter pub get
```

### Android

先完成 `flutter doctor` 中的 Android 环境配置。Windows 下生成自己的私有签名配置，再构建：

```powershell
.\tools\Create-Signing.ps1
.\tools\Build-Android.ps1 -Release
```

其他平台按 [发布指南](docs/RELEASE.md) 配置 `android/key.properties` 后运行：

```sh
flutter build apk --release --split-per-abi
```

自行构建的签名与官方发行包不同，不能直接作为官方包的覆盖更新。密钥与密码不要提交到仓库。

### Web 本地预览

```sh
npm ci --ignore-scripts
node tools/prepare-web.mjs
flutter build web --no-web-resources-cdn --no-wasm-dry-run
node tools/offline-shell.mjs
node tools/preview.mjs
```

打开 <http://127.0.0.1:4173>。Windows 也可运行 `.\启动预览.ps1 -Rebuild`，后续运行 `.\启动预览.ps1` 复用已有构建。

预览服务仅监听本机，并提供在线来源所需的 `/api` 网关。首次加载后支持离线打开应用及已缓存内容；单独部署静态文件或使用 `flutter run -d chrome` 不包含该网关。Android 直接访问来源站点。

### 检查与自动构建

```sh
flutter analyze --no-pub
flutter test --timeout 30s
node --test tools/preview.test.mjs
```

- [Check and build](https://github.com/LexianLix/manxia/actions/workflows/ci.yml)：分析、测试、Web 构建与 Android Profile 测试包。
- [Prepare Android release](https://github.com/LexianLix/manxia/actions/workflows/release-build.yml)：手动触发校验与各架构 Release 构建，产出供维护者本地签名的未签名包；**可安装发行包以 Releases 为准**。

需要在线检查来源时运行 `dart run tool/probe.dart`，结果仅代表当时网络与样本的状态。

## 参与贡献

欢迎通过 [Issues](https://github.com/LexianLix/manxia/issues/new/choose) 反馈问题或提出建议，也欢迎提交 Pull Request 改进阅读体验、来源解析和无障碍支持。

反馈时请提供应用版本、设备与系统版本、复现步骤，以及去除个人信息的截图或日志。开发约定与检查方式见 [贡献指南](CONTRIBUTING.md)。

## 致谢与许可

视觉设计受到 [Wenku8_Flutter](https://github.com/mikufoxxx/Wenku8_Flutter) 的启发。漫匣的应用代码独立实现，未复制其应用代码。

- 应用源码：[MIT License](LICENSE)。
- 内置字体：[Adobe Source Han Serif](https://github.com/adobe-fonts/source-han-serif)，[SIL OFL 1.1](assets/fonts/OFL.txt)。
- Web PDF 渲染：[Mozilla PDF.js](https://github.com/mozilla/pdf.js)，Apache License 2.0。
- 界面与跨平台能力：[Flutter](https://flutter.dev)。

第三方声明见 [NOTICE](NOTICE)。远程漫画元数据、封面与正文的权利归相应权利人，不适用应用代码许可；仓库不包含漫画正文图片。
