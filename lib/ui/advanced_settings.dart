import 'localized_text.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../data/library.dart';
import '../data/dm5_source.dart';
import '../data/file_actions.dart';
import '../data/source_hub.dart';
import '../data/sync_service.dart';
import '../data/offline_library.dart';

class AdvancedSettings extends StatefulWidget {
  const AdvancedSettings({
    super.key,
    required this.library,
    required this.source,
    required this.web,
    this.sliver = false,
  });
  final Library library;
  final Dm5Source source;
  final bool web, sliver;
  @override
  State<AdvancedSettings> createState() => _AdvancedSettingsState();
}

class _AdvancedSettingsState extends State<AdvancedSettings> {
  Library get library => widget.library;
  String? status;
  bool busy = false;
  Future<void> run(Future<String> Function() task) async {
    setState(() {
      busy = true;
      status = null;
    });
    try {
      final result = await task();
      if (mounted) setState(() => status = result);
    } catch (e) {
      if (mounted) setState(() => status = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget group(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(top: 26),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LocalizedText(
          title,
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontSize: 13,
          ),
        ),
        const Divider(),
        ...children,
      ],
    ),
  );
  Widget toggle(String key, String title, String subtitle, bool fallback) =>
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: LocalizedText(title),
        subtitle: LocalizedText(subtitle, style: const TextStyle(fontSize: 12)),
        value: library.option<bool>(key, fallback),
        onChanged: (v) => library.setOption(key, v),
      );
  Widget choice(
    String key,
    String title,
    Map<String, String> choices,
    String fallback,
  ) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: LocalizedText(title),
    trailing: SizedBox(
      width: MediaQuery.sizeOf(context).width < 600 ? 160 : 240,
      child: DropdownButton<String>(
        isExpanded: true,
        value: choices.containsKey(library.option<String>(key, fallback))
            ? library.option<String>(key, fallback)
            : fallback,
        items: choices.entries
            .map(
              (e) => DropdownMenuItem(
                value: e.key,
                child: LocalizedText(
                  e.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        onChanged: (v) {
          if (v != null) library.setOption(key, v);
        },
      ),
    ),
  );
  Future<void> configureSync() async {
    final sync = SyncService(library, gateway: widget.web ? Uri.base : null);
    final url = TextEditingController(
      text: library.option<String>('webdav.url', ''),
    );
    final user = TextEditingController(
      text: library.option<String>('webdav.user', ''),
    );
    final pass = TextEditingController(text: await sync.password());
    if (!mounted) {
      sync.close();
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const LocalizedText('WebDAV 同步'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const LocalizedText(
                '先在网盘创建专用文件夹，再填写完整文件地址，例如 https://dav.example.com/Manxia/library.json。同步收藏、进度、分组、书签；漫画文件可用 CBZ 导出后放入网盘。',
              ),
              TextField(
                controller: url,
                decoration: const InputDecoration(
                  label: LocalizedText('HTTPS 文件地址'),
                ),
              ),
              TextField(
                controller: user,
                decoration: const InputDecoration(label: LocalizedText('用户名')),
              ),
              TextField(
                controller: pass,
                obscureText: true,
                decoration: const InputDecoration(
                  label: LocalizedText('密码 / 应用密码'),
                ),
              ),
              LocalizedText(
                widget.web ? '浏览器密码仅在本次会话保留。' : '密码保存在系统安全存储。',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const LocalizedText('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const LocalizedText('保存并同步'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await library.setOption('webdav.url', url.text.trim());
      await library.setOption('webdav.user', user.text.trim());
      await sync.savePassword(pass.text);
      await run(sync.synchronize);
    }
    sync.close();
    // Dialog routes finish animating after their returned future completes.
    Future.delayed(const Duration(seconds: 1), () {
      url.dispose();
      user.dispose();
      pass.dispose();
    });
  }

  Future<void> transferLibrary(bool upload) async {
    final offline = OfflineLibrary.instance;
    if (offline == null) return;
    if (upload) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const LocalizedText('上传离线书库？'),
          content: const LocalizedText(
            '将更新云端的离线 ZIP 快照。其他设备有独有章节时，请先恢复合并，再上传完整书库。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const LocalizedText('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const LocalizedText('上传'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    final sync = SyncService(library, gateway: widget.web ? Uri.base : null);
    await run(
      () =>
          upload ? sync.uploadLibrary(offline) : sync.downloadLibrary(offline),
    );
    sync.close();
  }

  Future<void> editSource([Map<String, dynamic>? original]) async {
    final text = TextEditingController(
      text: const JsonEncoder.withIndent('  ').convert(
        original ??
            {
              'id': 'my_comics',
              'name': '我的漫画源',
              'baseUrl': 'https://example.com',
              'home': '/',
              'search': '/search?q={query}',
              'cards': '.comic',
              'title': '.title',
              'link': 'a',
              'cover': 'img',
              'coverAttribute': 'src',
              'chapters': '.chapters a',
              'pages': '.reader img',
              'pageAttribute': 'src',
              'imageHosts': ['example.com'],
              'reverseChapters': false,
            },
      ),
    );
    String? error;
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: LocalizedText(original == null ? '添加漫画源' : '编辑漫画源'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const LocalizedText(
                    '填写静态 HTML 的 CSS 选择器。章节和图片按网页顺序读取；不执行网站脚本。动态加密源需要独立适配器。',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: text,
                    minLines: 12,
                    maxLines: 20,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                  if (error != null)
                    LocalizedText(
                      error!,
                      style: TextStyle(color: Theme.of(c).colorScheme.error),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            if (original != null)
              TextButton(
                onPressed: () async {
                  library.sourceProfiles.removeWhere(
                    (p) => p['id'] == original['id'],
                  );
                  if (library.option<String>('source', 'dm5') ==
                      original['id']) {
                    await library.setOption('source', 'dm5');
                  }
                  await library.persistFeatures();
                  if (c.mounted) Navigator.pop(c);
                },
                child: const LocalizedText('删除'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const LocalizedText('取消'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  final p = SourceProfile(
                    Map<String, dynamic>.from(jsonDecode(text.text)),
                  );
                  if (original != null) {
                    library.sourceProfiles.removeWhere(
                      (v) => v['id'] == original['id'],
                    );
                  }
                  library.sourceProfiles.removeWhere((v) => v['id'] == p.id);
                  library.sourceProfiles.add(p.json);
                  await library.persistFeatures();
                  if (widget.source is SourceHub) {
                    await (widget.source as SourceHub).register();
                  }
                  if (c.mounted) Navigator.pop(c);
                } catch (e) {
                  update(() => error = '$e');
                }
              },
              child: const LocalizedText('保存'),
            ),
          ],
        ),
      ),
    );
    Future.delayed(const Duration(seconds: 1), text.dispose);
  }

  Future<String> diagnose() async {
    final watch = Stopwatch()..start();
    final books = await widget.source.home();
    if (books.isEmpty) throw StateError('连通成功，但未解析到漫画，请检查源配置。');
    final listMs = watch.elapsedMilliseconds;
    final detail = await widget.source.detail(books.first);
    if (detail.chapters.isEmpty) throw StateError('列表可用，章节解析为空。');
    final pages = await widget.source.networkPages(detail.chapters.first.path);
    return '列表 ${books.length} 本 / ${listMs}ms；首本 ${detail.chapters.length} 章；首章 ${pages.length} 页 / 总计 ${watch.elapsedMilliseconds}ms。图片加载请在阅读器检查。';
  }

  Future<String> checkUpdate() async {
    final installed = await PackageInfo.fromPlatform();
    final response = await http
        .get(
          Uri.parse(
            'https://api.github.com/repos/LexianLix/manxia/releases/latest',
          ),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 404) {
      return '当前版本 ${installed.version}。GitHub 暂未发布正式安装包，可在 Actions 下载调试包。';
    }
    if (response.statusCode != 200) {
      throw StateError('版本检查返回 HTTP ${response.statusCode}');
    }
    final release = jsonDecode(response.body) as Map;
    final tag = release['tag_name'] as String;
    if (!mounted) return '';
    final open = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: LocalizedText('GitHub 最新版本 $tag'),
        content: LocalizedText(
          '本机 ${installed.version}\n${release['name'] ?? ''}\n${release['body'] ?? ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const LocalizedText('关闭'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const LocalizedText('前往下载'),
          ),
        ],
      ),
    );
    if (open == true) {
      await launchUrl(
        Uri.parse('https://github.com/LexianLix/manxia/releases/latest'),
        mode: LaunchMode.externalApplication,
      );
    }
    return '已检查 GitHub 正式发布：$tag。本机 ${installed.version}。';
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: library,
    builder: (context, _) => widget.sliver
        ? SliverList.list(children: _sections(context))
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _sections(context),
          ),
  );
  List<Widget> _sections(BuildContext context) => [
    group('质感与性能', [
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.cleaning_services_outlined),
        title: const LocalizedText('清理临时图片缓存'),
        subtitle: const LocalizedText('清理内存中的解码图片；浏览器版可同时清理预览服务的网络缓存'),
        onTap: busy
            ? null
            : () => run(() async {
                PaintingBinding.instance.imageCache.clear();
                PaintingBinding.instance.imageCache.clearLiveImages();
                if (widget.web) {
                  final before = await http.get(Uri.base.resolve('/api/cache'));
                  final size =
                      (jsonDecode(before.body)['bytes'] as num) / 1024 / 1024;
                  await http.post(
                    Uri.base.resolve('/api/cache'),
                    headers: {'Content-Type': 'application/json'},
                    body: '{"action":"clear"}',
                  );
                  return '已清理 ${size.toStringAsFixed(1)} MB 网络缓存；已下载章节保存在离线书库。';
                }
                return '解码图片缓存已清理。';
              }),
      ),
      choice('quality', '画质与材质', {
        'high': '高 · 折射与高清',
        'standard': '标准 · 柔光',
        'low': '省电 · 简化材质',
      }, 'high'),
      toggle('parallax', '指针视差', '移动指针时书脊随光线轻微变化', true),
      if (!kIsWeb) toggle('tilt', '设备倾斜视差', '使用加速度计；可随时关闭', false),
      toggle('coverColor', '封面取色', '从真实封面提取书架环境色', true),
      toggle('haptics', '轻触反馈', '切换实体书时提供触感反馈', true),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const LocalizedText('预载页数'),
        trailing: DropdownButton<int>(
          value: library.option<int>('preload', 2),
          items: [0, 1, 2, 3, 5]
              .map(
                (i) => DropdownMenuItem(value: i, child: LocalizedText('$i 页')),
              )
              .toList(),
          onChanged: (v) {
            if (v != null) library.setOption('preload', v);
          },
        ),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const LocalizedText('同时下载'),
        trailing: DropdownButton<int>(
          value: library.option<int>('downloadParallel', 2),
          items: [1, 2, 3, 4]
              .map(
                (i) => DropdownMenuItem(value: i, child: LocalizedText('$i 章')),
              )
              .toList(),
          onChanged: (v) {
            if (v != null) library.setOption('downloadParallel', v);
          },
        ),
      ),
    ]),
    group('可读性', [
      choice('language', '界面语言', {
        'zh_CN': '简体中文',
        'zh_TW': '繁體中文',
        'en': 'English',
      }, 'zh_CN'),
      toggle('highContrast', '高对比度', '增强边框与文字对比', false),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const LocalizedText('界面文字大小'),
        subtitle: Slider(
          value: library.option<double>('textScale', 1).clamp(.85, 1.5),
          min: .85,
          max: 1.5,
          divisions: 13,
          label: '${(library.option<double>('textScale', 1) * 100).round()}%',
          onChanged: (v) => library.setOption('textScale', v),
        ),
      ),
      const ListTile(
        contentPadding: EdgeInsets.zero,
        title: LocalizedText('键盘与辅助功能'),
        subtitle: LocalizedText(
          '书架可 Tab 聚焦，阅读器用方向键翻页、空格显示控制栏、Esc 返回；动画跟随系统减少动画设置。',
        ),
      ),
    ]),
    group('备份与同步', [
      if (OfflineLibrary.instance != null) ...[
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.cloud_upload_outlined),
          title: const LocalizedText('上传离线书库到 WebDAV'),
          subtitle: const LocalizedText('完整图片快照 · 与资料 JSON 相邻保存为 offline.zip'),
          onTap: busy ? null : () => transferLibrary(true),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.cloud_download_outlined),
          title: const LocalizedText('从 WebDAV 恢复离线书库'),
          subtitle: const LocalizedText('先检查清单和图片校验，再合并到本机'),
          onTap: busy ? null : () => transferLibrary(false),
        ),
      ],
      if (OfflineLibrary.instance != null) ...[
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.inventory_2_outlined),
          title: const LocalizedText('导出完整离线书库'),
          subtitle: const LocalizedText('包含已完成章节的图片与资料，可保存到网盘；上限 512 MB'),
          onTap: busy
              ? null
              : () => run(() async {
                  await FileActions.exportLibrary(OfflineLibrary.instance!);
                  return '已打开书库保存窗口。';
                }),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.restore),
          title: const LocalizedText('恢复离线书库'),
          subtitle: const LocalizedText('导入漫匣 ZIP 书库，校验图片后合并'),
          onTap: busy
              ? null
              : () => run(() async {
                  return await FileActions.importLibrary(
                        OfflineLibrary.instance!,
                      )
                      ? '离线书库已恢复。'
                      : '已取消。';
                }),
        ),
      ],
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.file_download_outlined),
        title: const LocalizedText('导出资料备份'),
        subtitle: const LocalizedText('收藏、分组、笔记和阅读位置 · JSON'),
        onTap: busy
            ? null
            : () => run(() async {
                await FileActions.exportBackup(library);
                return '已打开备份保存窗口。';
              }),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.upload_file),
        title: const LocalizedText('导入并合并备份'),
        subtitle: const LocalizedText('同一本漫画保留较新的阅读位置；收藏取并集'),
        onTap: busy
            ? null
            : () => run(() async {
                return await FileActions.importBackup(library)
                    ? '备份已合并。'
                    : '已取消。';
              }),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.sync),
        title: const LocalizedText('WebDAV 同步'),
        subtitle: LocalizedText(
          library.option<String>('webdav.lastSync', '配置自己的 WebDAV / NAS'),
        ),
        onTap: busy ? null : configureSync,
      ),
    ]),
    group('漫画源与维护', [
      choice('source', '默认发现源', {
        'dm5': '动漫屋',
        for (final p in library.sourceProfiles)
          p['id'] as String: p['name'] as String,
      }, 'dm5'),
      for (final p in library.sourceProfiles)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: LocalizedText(p['name']),
          subtitle: LocalizedText(p['baseUrl']),
          trailing: const Icon(Icons.edit_outlined),
          onTap: () => editSource(p),
        ),
      TextButton.icon(
        onPressed: () => editSource(),
        icon: const Icon(Icons.add),
        label: const LocalizedText('添加声明式漫画源'),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.network_check),
        title: const LocalizedText('检查当前源'),
        subtitle: const LocalizedText('依次验证列表、详情、章节图片地址'),
        onTap: busy ? null : () => run(diagnose),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.system_update),
        title: const LocalizedText('检查 GitHub 更新'),
        onTap: busy ? null : () => run(checkUpdate),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.code),
        title: const LocalizedText('GitHub · LexianLix/manxia'),
        onTap: () => launchUrl(
          Uri.parse('https://github.com/LexianLix/manxia'),
          mode: LaunchMode.externalApplication,
        ),
      ),
    ]),
    if (busy) const LinearProgressIndicator(),
    if (status != null)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: SelectableText(status!),
      ),
  ];
}
