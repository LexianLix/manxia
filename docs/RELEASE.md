# 构建、发行与数据迁移

## 安装发行版

从 [GitHub Releases](https://github.com/LexianLix/manxia/releases/latest) 下载设备对应的 APK。当前 v0.3.2 支持 Android 7.0（API 24）及以上，提供 ARM64、ARMv7 和 x86_64 三个分包。常见手机和平板优先选择 ARM64。

发行包使用 Release 模式编译，并由项目固定密钥签名。发行页包含 `SHA256SUMS.txt` 与 `release-manifest.json`，后者记录构建提交、工作流、架构、版本码和签名证书指纹。GitHub 自动提供的 Source code 归档是源码，不是安装包。

下载后可在 PowerShell 中检查文件哈希，并与发行页的校验文件比对：

```powershell
Get-FileHash .\Manxia-0.3.2-arm64-v8a.apk -Algorithm SHA256
```

项目签名证书 SHA-256：

```text
9618d4bb9b8ce8045c502c79fea0b8c2eb4d14f0a6ccb380cf22ac2bccdbc091
```

证书指纹用于区分签名身份，与某个 APK 文件的 SHA-256 不同。持有 Android Build Tools 时，也可运行 `apksigner verify --verbose --print-certs <APK>` 检查签名。

## 升级与恢复

旧 Debug／Profile 测试包使用构建环境的临时证书，与项目发行签名不同。换装前请依次：

1. 在旧版“设置 → 备份与同步 → 导出完整离线书库”保存 ZIP，再导出一份资料 JSON。确认文件已保存在应用外可访问的位置。
2. 卸载旧测试包，安装发行版。不要在尚未成功保存备份时清除应用数据。
3. 在新版“恢复离线书库”导入 ZIP；需要时通过“导入并合并备份”补入 JSON。WebDAV 密码不包含在备份中，需重新填写。

后续同架构发行包沿用相同 applicationId 和签名，并递增构建号。切换架构或降级可能受 Android 版本码限制，请优先沿用相同架构。真机覆盖安装与恢复仍需实际设备验证，备份应独立保留。

0.2 保留旧 favorites/history 键，旧记录没有图片内位置时按 0 恢复；新分组、书签与删除标记使用 features.v2，离线索引使用 offline.v1。备份格式带 schema，遇到更新的不支持版本会拒绝导入。

设置中的“检查更新”读取本仓库最新发行版，并打开 GitHub 下载入口，不在后台自行安装 APK。

## 自行构建

准备 Flutter 3.47.7、Dart 3.13.5、JDK 17 与 Android SDK，先运行 `flutter doctor` 完成环境配置。

### Windows 签名与构建

```powershell
.\tools\Create-Signing.ps1
.\tools\Build-Android.ps1 -Release
```

签名脚本生成随机密码，以环境变量传给 keytool；密钥放在 `.private/manxia-release.jks`，配置放在 `android/key.properties`。两者都被 Git 忽略。脚本拒绝覆盖已有密钥，后续构建请继续使用原密钥。

### 其他平台

使用 JDK 的 keytool 在仓库外生成自己的密钥，并在 `android/key.properties` 中写入以下字段，替换示例值。路径建议使用正斜杠；相对路径以 `android/app` 为基准。

```properties
storeFile=/private/path/manxia-release.jks
storePassword=YOUR_PRIVATE_STORE_PASSWORD
keyAlias=manxia
keyPassword=YOUR_PRIVATE_KEY_PASSWORD
```

然后运行：

```sh
flutter pub get
flutter build apk --release --split-per-abi
```

产物位于 `build/app/outputs/flutter-apk/`。自行构建使用自己的签名，不能覆盖项目官方签名的安装包。密钥与配置应一起保存在加密备份中；不要上传到 Issues、聊天、公开仓库或构建附件。

普通 Release 构建缺少签名配置时会失败，不会自动使用临时 Debug 证书。`tools/Build-Android.ps1` 不带参数时构建 Profile，`-Debug` 构建调试包，`-Release` 构建正式签名包。

## 维护者发布流程

1. 更新 `pubspec.yaml` 的版本和构建号、`CHANGELOG.md`、README 下载链接。检查签名文件仍被 Git 忽略；提交源码与文档。
2. 在待发布提交上创建 `vX.Y.Z` 标签，推送后手动运行 [Prepare Android release](https://github.com/LexianLix/manxia/actions/workflows/release-build.yml)，选择该标签。工作流通过代码分析、Flutter 与 Node 测试后，按架构构建 Release APK。
3. 下载该次运行的 `manxia-unsigned-release` 附件并解压。它是**未签名的准备产物**，不要直接放到 Releases 供安装。`build-info.json` 记录确切提交、版本与文件哈希。
4. 在保存项目密钥的 Windows 机器上，使用 Android SDK Build Tools 执行本地签名：

```powershell
.\tools\Sign-Release.ps1 -InputDirectory .\artifacts\unsigned -BuildToolsDirectory 'C:\Android\Sdk\build-tools\36.0.0' -OutputDirectory .\artifacts\release
```

脚本核对输入哈希、版本、包名、架构与版本码，先执行 16 KB ZIP 对齐，再签名、验证签名和对齐。密码通过环境变量传递；输出包含 APK、`SHA256SUMS.txt`、`release-manifest.json` 及各架构的验证日志。已有 APK 不会被覆盖。

5. 核对三包签名一致且与既往发行版相同。Flutter 分包会为构建号增加架构偏移，当前构建号 9 对应 ARMv7 `1009`、ARM64 `2009`、x86_64 `4009`，不要把这些值误认为版本不一致。
6. 在 GitHub 创建关联标签的 Release 草稿，上传三个已签名 APK、哈希清单和发行清单。检查附件名称与 README 链接一致，再发布并确认公开下载可用。发布后不替换同名安装包；修订应用需增加构建号并发布新版本。

签名密钥保留本机，没有上传到 GitHub Secrets。CI 通过显式环境变量 `MANXIA_UNSIGNED_RELEASE=true` 准备未签名产物；只有维护者签名、核对并发布后的附件才是发行包。

签名工具使用方式参考 Android 官方的 [apksigner](https://developer.android.com/tools/apksigner) 与 [zipalign](https://developer.android.com/tools/zipalign) 文档。

## 验证范围

v0.2.4 修复了 v0.2.3 在 Android Release 下的启动白屏。现已加入安装后首屏控件、截图、日志及重开检查；历史缺口与当前结果见 [启动故障记录](STARTUP.md)和[验证记录](VALIDATION.md)。代码分析、自动测试、各架构 Release 编译、APK 签名与 ZIP 对齐另行检查，发行清单记录确切构建出处。模拟器不能证明各厂商真机上的持续阅读、体感、音量键、旋转、升级与回滚均通过；WebDAV 协议测试也不能代替真实网盘账号验收。
