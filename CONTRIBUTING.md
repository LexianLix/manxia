# 参与漫匣开发

感谢你愿意帮助改进漫匣。较大的交互调整或新来源适配建议先开 Issue 讨论范围；修正文档、缺陷和无障碍问题可以直接提交 Pull Request。

## 开发环境

使用 Flutter 3.47.7 / Dart 3.13.5。Web 网关与资源准备需要 Node.js 22+，Android 构建需要 JDK 17 和 Android SDK。克隆、预览和签名步骤见 [README](README.md#从源码构建)。

## 提交之前

1. 尽量让一个 PR 只解决一个问题，并说明触发条件、改动后的行为和验证方式。
2. Dart 文件运行 `dart format`。执行 `flutter analyze --no-pub`、`flutter test --timeout 30s` 和 `node --test tools/preview.test.mjs`。
3. 修改阅读器、书架或导航时，检查手机与宽屏布局、浅色／深色，以及减少动效选项；性能结论注明测试设备、构建模式和测量范围。
4. 修复解析、备份或同步问题时，为实际失败场景补充可离线运行的回归测试。来源样本应尽量小，不包含漫画正文或访问凭据。

## 代码位置

| 路径 | 内容 |
| --- | --- |
| `lib/data/` | 来源解析、推荐、书库、下载、同步与备份 |
| `lib/platform/` | 原生与浏览器存储、文件和平台能力 |
| `lib/ui/` | 立体书绘制、页面、导航与阅读器 |
| `shaders/` | 玻璃材质着色器 |
| `test/` | Flutter 测试 |
| `tools/` | 预览网关、资源准备、签名与构建 |
| `tool/` | 来源探测与快照工具 |
| `docs/` | 使用、设计、验证与发布文档 |

## 问题反馈

请使用 [Issue 模板](https://github.com/LexianLix/manxia/issues/new/choose)，填写版本、设备与系统、复现步骤和预期行为。来源问题请带上公开页面地址与发生时间；不要附带账号密码、WebDAV 地址中的凭据、备份文件或完整个人书库。

## 签名与发行

`android/key.properties`、`.private/`、密钥和环境变量文件不进入 Git。贡献者使用自己的开发密钥；官方发行由维护者使用项目固定密钥完成。请勿把未签名构建或 Profile 测试包当成 Release 安装包。详见 [发布指南](docs/RELEASE.md)。

提交的代码需有明确来源，并与本项目 MIT 许可兼容。新增第三方资源时同步补充许可与 [NOTICE](NOTICE)。
