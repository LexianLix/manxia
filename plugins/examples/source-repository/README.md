# 漫匣漫画源仓库模板

1. 新建一个公开仓库，使用 `main` 作为默认分支。将此处的 `.github/workflows/publish.yml` 和漫匣的 `tools/plugin-sdk.mjs`、`tools/character-package.mjs` 按原路径复制进去。
2. 将 `plugins/examples/script-source/` 复制为新仓库根目录下的 `source/`。修改 `source/manifest.json` 的插件 ID、书源 ID、版本和授权域名，再实现 `source/source.js` 的查询、目录和图片接口。
3. 在仓库设置的 **Pages → Build and deployment → Source** 中选择 **GitHub Actions**。推送 `main` 或运行 **Publish Manxia source**，工作流会校验清单、打包并将带 SHA-256 的 `index.json` 发布到 Pages。
4. 在漫匣「插件商城 → 插件管理 → 插件仓库」填写 Pages 地址末尾加 `/index.json`。安装前检查权限，安装后运行「试跑脚本源」。更新时保留两个 ID 并递增插件版本。

本地检查使用 `node tools/plugin-sdk.mjs publish-source source https://example.com/ _site`。命令生成新的输出目录，其中包含可导入的插件 JSON 和仓库索引。
