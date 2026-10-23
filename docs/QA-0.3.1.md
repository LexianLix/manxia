# v0.3.1 验证记录

日期：2026-10-23。候选构建来自提交 `2524a4f476c54fa280bb86d1a8fb42dd6455b1f9`；发行结果见下文。

- 修复前回归：空书架实际返回七部演示；每日推荐只有六部；有效懒加载封面被漏掉。新增测试在修改前均已失败，修复后通过。
- 本地验证：flutter analyze --no-pub 无问题；62 项 Flutter、7 项 Node、3 项 Python 测试通过；Release Web 构建通过。
- 画面检查：Flutter 实际渲染 390、754、1440 宽度，手机每日完整列表、榜单、空书架及加入七部测试收藏后的立体书架；英文 150% 字号布局通过。
- 流程回归：旧 demo=true 不会混入收藏，真实收藏与阅读进度可重新加载；旧六部精选缓存不会截断十二部列表；源站更多链接可序列化且兼容旧缓存；分页去重、失败保留及同页重试通过模拟 HTTP 验证。
- 完整目录与远程完整列表采用 SliverGrid 按需构建。首页与书单预览限六张，完整列表保留该栏目全部已读取漫画。
- 当前内置目录共 80 部；八个源站栏目各 9–12 部，四类首页榜单各五部。未把其他栏目填充为额外排名。
- 源站现场验证（2026-10-23）：通过本机已配置的代理抓取动漫屋真实首页，应用解析器读到 76 部漫画与 7 个更多栏目链接；源站首页四类榜单各五部，没有额外完整榜单链接。强势安利完整栏目第一页与第二页均返回 21 部，应用解析后第二页新增 20 个唯一条目。真实 HTML 与分页响应保存于忽略目录 `.qa/dm5-v031-*`，解析验证 `.qa/v031_live_test.dart` 两项通过。
- 在线边界：上述验证确认服务端返回内容可被解析；未验证 iQOO 真机的直接联网、App 端代理行为、验证码或完整在线阅读。离线截图仍使用既有目录与本地封面缓存，不能与最新 76 部目录混同。
- 真机边界：iQOO / ARM64 的安装、真实网络、帧率和完整阅读流程未验证。
- 插件边界：本次未改动 API 1；DSH 式可执行插件生态仍待设计与实现。

可复现：

```powershell
flutter analyze --no-pub
flutter test --no-pub
node --test tools/preview.test.mjs tools/plugin-sdk.test.mjs
python -m unittest discover -s tools -p 'test_*.py'
$env:MANXIA_CAPTURE_DIR = "$PWD/.qa/discovery-redesign"
flutter test --no-pub test/discovery_page_test.dart
```

画面输出位于忽略目录 `.qa/discovery-redesign/`；公开产品截图见 `docs/images/`。可选截图使用本机已缓存的封面，不从网络补图，不写入用户真实书库。

## Android 候选包

- [Release 构建与启动检查](https://github.com/LexianLix/manxia/actions/runs/39780786304) 和 [常规 CI](https://github.com/LexianLix/manxia/actions/runs/39780771933) 均成功，源码提交一致。
- Android 11 / API30 与 Android 15 / API35 的 x86_64 模拟器，均各完成三次安装冷启动。六份 verdict 全部 passed=true，首页标题实际绘制，启动错误及命令错误均为空；未通过额外 renderer Intent 参数覆盖默认启动。
- 已查看两系统 screen-rgb.jpg 及标题区域裁剪，首页正常显示真实空书架与发现入口。原始证据位于 `artifacts/v031-candidate-qa/`（忽略目录）。完整大图的预览可能省略部分文字，使用实际标题像素与裁剪交叉检查。
- 这一步使用 CI 临时证书，仅证明候选二进制的原生启动；正式签名公开包需另行复测。

## 正式签名与发布

- [v0.3.1](https://github.com/LexianLix/manxia/releases/tag/v0.3.1) 已于 2026-10-23 发布，构建号 10；名称为版本号，说明按修复、改进、删除归纳。
- 三个 ABI 使用项目固定证书签名，签名验证、16 KB 对齐、API24 最低版本与分包版本码均通过。证书 SHA-256：`9618d4bb9b8ce8045c502c79fea0b8c2eb4d14f0a6ccb380cf22ac2bccdbc091`。
- 源构建归档 SHA-256 与 GitHub artifact digest 一致；本地 APK 与公开发行五附件的 GitHub digest、大小一致。二进制对应 `2524a4f476c54fa280bb86d1a8fb42dd6455b1f9`，tag 指向此提交；后续文档提交不用于二进制归因。
- [公开安装包启动复测](https://github.com/LexianLix/manxia/actions/runs/39945061170) 已成功；未传 build_run，从公开发行下载正式签名 APK。Android 11 / API30 与 Android 15 / API35 的 x86_64 模拟器均各连续三次冷启动通过，六份 verdict 中 passed=true、标题实际绘制且错误列表为空，renderer_override=platform。
- 已核对两系统正式包截图。公开包证据归档的 SHA-256 与 GitHub artifact digest 一致，原始日志和画面保存在 `artifacts/v031-public-qa/`（忽略目录）。物理 ARM64 与 iQOO 验证边界仍保留。

- 五个公开附件 HEAD 均返回 HTTP200；匿名下载的 release-manifest.json 与本地正式签名清单逐字节哈希一致。
