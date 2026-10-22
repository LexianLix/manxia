# v0.3.1 验证记录

日期：2026-10-22。当前为候选构建，APK 与原生验证结果另行补充。

- 修复前回归：空书架实际返回七部演示；每日推荐只有六部；有效懒加载封面被漏掉。新增测试在修改前均已失败，修复后通过。
- 本地验证：flutter analyze --no-pub 无问题；62 项 Flutter、7 项 Node、3 项 Python 测试通过；Release Web 构建通过。
- 画面检查：Flutter 实际渲染 390、754、1440 宽度，手机每日完整列表、榜单、空书架及加入七部测试收藏后的立体书架；英文 150% 字号布局通过。
- 流程回归：旧 demo=true 不会混入收藏，真实收藏与阅读进度可重新加载；旧六部精选缓存不会截断十二部列表；源站更多链接可序列化且兼容旧缓存；分页去重、失败保留及同页重试通过模拟 HTTP 验证。
- 完整目录与远程完整列表采用 SliverGrid 按需构建。首页与书单预览限六张，完整列表保留该栏目全部已读取漫画。
- 当前内置目录共 80 部；八个源站栏目各 9–12 部，四类首页榜单各五部。未把其他栏目填充为额外排名。
- 在线边界：本次 Windows HTTP、预览网关和网页抓取均访问动漫屋超时，未完成实时源站更多链接、分页及最新目录验证。测试与截图使用真实目录快照和本地已有封面缓存；没有伪造热度或补造漫画。
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
