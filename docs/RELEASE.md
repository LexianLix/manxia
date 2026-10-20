# Android 发布与数据迁移

开发包从 GitHub Actions 下载。它使用构建环境的临时调试证书，不保证与另一次构建同签名。正式安装前先在应用中导出资料及离线书库。

## 私有正式签名

本机配置 JDK 17、Android SDK、Flutter，完成 flutter doctor 所列条件后：

```powershell
.\tools\Create-Signing.ps1
.\tools\Build-Android.ps1 -Release
```

脚本生成随机签名密码，以环境变量传给 keytool，不把密码放入进程参数；私有材料放 `.private/manxia-release.jks` 和 `android/key.properties`，均被 Git 忽略。脚本拒绝覆盖已有密钥。正式 release 没有此配置时会构建失败，不会悄悄退回调试签名。

把密钥和配置一起放到自己的加密备份中。不要提交、发到聊天或放进公开仓库。后续更新必须使用相同 applicationId 和密钥，并递增 pubspec.yaml 的构建号。

本机已生成并检查 Git 忽略的私有 RSA-3072 签名密钥，未上传到仓库。本机没有完整 Android SDK，本轮未生成自有正式签名安装包。CI 负责测试构建；没有自动上传私有密钥到 GitHub Secrets。

## 升级与恢复

0.2 保留旧 favorites/history 键，旧记录没有图片内位置时按 0 恢复；新分组/书签/删除标记使用 features.v2，离线索引使用 offline.v1。导出格式带 schema，遇到更新的不支持版本拒绝导入。

正式发布前需在真机依次做：旧版本收藏/阅读/下载 → 导出备份 → 相同密钥覆盖安装新版 → 核对进度与离线页 → 再次导出/恢复。降级不强行覆盖不兼容数据库；使用对应版本和备份恢复。

设置中的更新按钮读取本仓库 latest release，展示当前版本与最新标签，用户前往 GitHub 选择下载，不在后台自行安装 APK。

## 当前未验证

真机安装、同签名覆盖升级、正式签名 APK 构建和回滚。源码与模拟持久化测试不能代替以上验证。
## 性能测试包补充（0.2.2）

Actions 默认产出 `manxia-android-profile/app-profile.apk`，用 Profile 模式 AOT 编译，以免把 Debug 模式开销带入流畅度试用。它仍是临时测试签名，保留性能分析能力；正式发行和稳定覆盖升级继续使用自己的固定 Release 密钥。默认执行 `tools/Build-Android.ps1` 也构建 Profile，`-Debug` 用于开发调试，`-Release` 用于正式签名构建。

已比较本机保存的 0.2.1 与 0.2.2 安装包，测试签名不同，不能直接覆盖。手动换装时：

1. 在旧版“设置 → 备份与同步 → 导出完整离线书库”保存 ZIP，并另存一份“导出资料备份”JSON；确认导出成功且文件已保存到应用外的位置。
2. 再卸载旧测试包，安装新包。
3. 在新版“恢复离线书库”导入 ZIP；必要时通过“导入并合并备份”补入 JSON。重新填写 WebDAV 密码，备份不会包含密码。

本轮只提供安装文件和迁移说明，没有执行卸载、清除数据或安装到真机。
