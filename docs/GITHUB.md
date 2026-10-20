# 上传 GitHub

当前代码已上传到公开仓库：<https://github.com/LexianLix/manxia>。本地 `origin` 已关联该地址，`main` 已设置跟踪。已有工作区后续使用本页第 5 步即可；第 1 至 3 步仅供重新建立其他仓库时参考。

当前源码保存在 `D:\project\comic`。先预览确认页面，再上传仓库。下面只复制代码围栏里面的命令，不要复制围栏符号。

## 1. 新建空仓库

登录 GitHub，打开 <https://github.com/new>：

- Repository name：建议 `manxia`，也可使用其他名称。
- Description：`有实体书质感的 Flutter 漫画阅读器，默认动漫屋。`
- Public / Private：按你的需要选择；Public 会公开仓库源码。
- 不勾选初始化 README、.gitignore、License，项目本地已经准备好这些文件。
- 点击 Create repository，复制仓库 HTTPS 地址。

## 2. 本地提交

打开 PowerShell：

```powershell
Set-Location 'D:\project\comic'
git status
```

如果尚未初始化仓库，执行：

```powershell
git init -b main
```

如果 Git 首次提交提示缺少身份，配置你想展示在提交记录里的姓名与邮箱。仅在本项目设置：

```powershell
git config user.name "你的GitHub用户名"
git config user.email "你的GitHub提交邮箱"
```

可以从 GitHub Settings → Emails 中复制自己的 GitHub noreply 邮箱。不要使用别人的身份。

```powershell
git add .
git diff --cached --stat
git status
git commit -m "Build Manxia comic reader"
```

提交列表应该是源码、字体许可和说明。`.gitignore` 已排除构建目录、图片缓存、QA 结果、本地配置、环境变量与常见签名文件。

## 3. 关联并推送

把下方地址中的账号和仓库名换成你刚创建的仓库：

```powershell
git remote add origin https://github.com/你的用户名/manxia.git
git push -u origin main
```

第一次推送可能弹出 Git Credential Manager 登录窗口，按提示用自己的 GitHub 账号登录。不要将密码或 token 写进源码、README 或远程地址。

如果提示 `remote origin already exists`，先检查：

```powershell
git remote -v
```

确认需要改成新仓库后：

```powershell
git remote set-url origin https://github.com/你的用户名/manxia.git
git push -u origin main
```

## 4. 下载自动构建产物

打开仓库 → Actions → `Check and build` → 最近一次运行。构建成功后，页面底部 Artifacts 有：

- `manxia-web`：浏览器前端编译产物，运行仍需要预览网关。
- `manxia-android-debug`：测试安装用的 APK。它是调试签名包，不能作为正式版签名升级承诺。

前一版自动构建已通过。每次新增插件后，仍需查看对应提交的运行结果；绿色成功才表示该次 APK 实际生成。真机运行与正式签名升级需另行测试。

## 5. 后续更新

```powershell
Set-Location 'D:\project\comic'
git add .
git diff --cached --stat
git commit -m "Improve bookshelf interaction"
git push
```

想发布下载版本时，在 Releases 新建版本并附上验证过的安装包。正式发布前先配置自己的 Android 签名，不上传私钥和密钥密码。

官方参考：<https://docs.github.com/en/migrations/importing-source-code/using-the-command-line-to-import-source-code/adding-locally-hosted-code-to-github>
