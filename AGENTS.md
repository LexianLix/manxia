# 漫匣工作约定

- 保留现有 Flutter 架构；优先保证 Android Release 启动和书库数据兼容。
- 动效必须可中断、可逆，遵守系统减少动效；界面改动须查看实际画面。
- README 介绍产品、使用、插件、版权、协议与致谢。修复记录放 CHANGELOG/Release；Release 名称采用版本号，说明按修复、改进、删除归纳实际完成项。
- 不提交 `.private/`、`android/key.properties`、签名密钥或个人书库。沿用项目发行签名。
- 开始工作时，若根目录存在 `WORK_START.md`，先执行 `powershell -NoProfile -ExecutionPolicy Bypass -File tools/Resume-Work.ps1`。脚本成功输出接续信息后自动删除该一次性文档；根据其中的提交、验证及待办继续，先检查实际工作区。
- 额度接近上限时，完成当前最小可验证改动，保存未完成边界并生成 `WORK_START.md`。不要把未完成工作写成已完成，也不要在未验证的中间状态发布 APK。
