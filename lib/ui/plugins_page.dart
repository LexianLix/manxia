import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/library.dart';
import '../data/plugin_registry.dart';

const capabilityLabels = {
  'theme': '主题材质',
  'reader': '阅读预设',
  'source': '漫画源',
  'navigation': '导航布局',
};

class PluginsPage extends StatefulWidget {
  const PluginsPage({super.key, required this.library});
  final Library library;
  @override
  State<PluginsPage> createState() => _PluginsPageState();
}

class _PluginsPageState extends State<PluginsPage> {
  late final registry = PluginRegistry(widget.library);
  late Future<List<ManxiaPlugin>> catalog = PluginCatalog.bundled();
  bool installedOnly = false, busy = false;
  String search = '', status = '内置目录 · 可离线安装';

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      status = '正在处理…';
    });
    try {
      await action();
      if (mounted && status == '正在处理…') setState(() => status = '已完成');
    } catch (e) {
      if (mounted) setState(() => status = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<String?> input(
    String title,
    String initial, {
    bool multiline = false,
  }) {
    var text = initial;
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 520,
          child: TextFormField(
            initialValue: initial,
            minLines: multiline ? 8 : 1,
            maxLines: multiline ? 16 : 3,
            onChanged: (v) => text = v,
            decoration: InputDecoration(
              labelText: multiline
                  ? '插件 manifest JSON'
                  : 'HTTPS 仓库 index.json 地址',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, text),
            child: const Text('继续'),
          ),
        ],
      ),
    );
  }

  Future<void> install(ManxiaPlugin plugin) async {
    final source = plugin.contributions['source'];
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(plugin.name),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${plugin.author} · v${plugin.version} · ${plugin.json['license']}',
              ),
              const SizedBox(height: 16),
              Text(plugin.description),
              const SizedBox(height: 20),
              Text(
                '扩展范围：${plugin.capabilities.map((c) => capabilityLabels[c]).join('、')}',
              ),
              if (source is Map) ...[
                const SizedBox(height: 12),
                Text(
                  '漫画站点：${source['baseUrl']}\n图片域名：${source['imageHosts'] ?? '与站点相同'}',
                ),
              ],
              const SizedBox(height: 12),
              const Text('启用后立即应用；可在“已安装”停用或卸载。个人书籍与逐本阅读设置保留。'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('安装并启用'),
          ),
        ],
      ),
    );
    if (ok == true) await run(() => registry.install(plugin));
  }

  Future<void> importFile() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (file == null || !mounted) return;
    try {
      if ((await file.length() ?? 0) > 128 * 1024) {
        throw const FormatException('请选择小于 128 KB 的 JSON 插件');
      }
      await install(
        ManxiaPlugin(
          Map<String, dynamic>.from(
            jsonDecode(utf8.decode(await file.readAsBytes())),
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => status = '$e');
    }
  }

  Future<void> repository() async {
    final url = await input(
      '插件仓库',
      widget.library.option<String>(
        'plugins.repository',
        PluginCatalog.official,
      ),
    );
    if (url == null || !mounted) return;
    await run(() async {
      final plugins = await PluginCatalog.remote(url.trim());
      await widget.library.setOption('plugins.repository', url.trim());
      if (mounted) {
        setState(() {
          catalog = Future.value(plugins);
          status = '在线仓库 · ${plugins.length} 个插件';
        });
      }
    });
  }

  Widget setting(
    ManxiaPlugin plugin,
    Map<String, dynamic> item,
    Map<String, dynamic> definition,
  ) {
    final key = definition['key'] as String;
    final value = (item['config'] as Map? ?? {})[key] ?? definition['default'];
    void save(dynamic v) => run(() => registry.configure(plugin.id, key, v));
    final title = Text(definition['label']);
    return switch (definition['type']) {
      'boolean' => SwitchListTile(
        title: title,
        value: value,
        onChanged: busy ? null : save,
      ),
      'number' => ListTile(
        title: title,
        subtitle: Slider(
          value: (value as num).toDouble(),
          min: (definition['min'] as num).toDouble(),
          max: (definition['max'] as num).toDouble(),
          divisions: 20,
          label: value.toString(),
          onChanged: busy ? null : save,
        ),
      ),
      'choice' => ListTile(
        title: title,
        trailing: DropdownButton<String>(
          value: value,
          items: (definition['choices'] as List)
              .map((v) => DropdownMenuItem<String>(value: v, child: Text(v)))
              .toList(),
          onChanged: busy ? null : save,
        ),
      ),
      _ => Padding(
        key: PageStorageKey('plugin-setting-field-${plugin.id}-$key'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: TextFormField(
          key: ValueKey('${plugin.id}-$key-$value'),
          initialValue: value,
          decoration: InputDecoration(
            labelText: definition['label'],
            helperText: '#RRGGBB · 回车应用',
          ),
          onFieldSubmitted: busy ? null : save,
        ),
      ),
    };
  }

  Widget tile(ManxiaPlugin plugin) {
    final item = registry.entry(plugin.id);
    final update =
        item != null &&
        PluginRegistry.compareVersions(
              plugin.version,
              item['manifest']['version'],
            ) >
            0;
    final installed = item != null;
    final active = item?['enabled'] == true;
    final color = Theme.of(context).colorScheme.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .045),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  plugin.capabilities.contains('theme')
                      ? Icons.palette_outlined
                      : plugin.capabilities.contains('reader')
                      ? Icons.menu_book_outlined
                      : plugin.capabilities.contains('source')
                      ? Icons.public
                      : Icons.water_drop_outlined,
                  color: color,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(plugin.name, style: const TextStyle(fontSize: 18)),
                    const SizedBox(height: 5),
                    Text(
                      '${plugin.author} · v${plugin.version}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ),
              if (installed)
                Switch(
                  value: active,
                  onChanged: busy
                      ? null
                      : (v) => run(() => registry.enable(plugin.id, v)),
                )
              else
                FilledButton(
                  onPressed: busy ? null : () => install(plugin),
                  child: const Text('安装'),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            plugin.description,
            style: const TextStyle(fontSize: 12, height: 1.7),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: plugin.capabilities
                .map(
                  (c) => Text(
                    capabilityLabels[c]!,
                    style: TextStyle(fontSize: 11, color: color),
                  ),
                )
                .toList(),
          ),
          if (installed) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  active ? '已启用' : '已停用',
                  style: TextStyle(fontSize: 11, color: color),
                ),
                const Spacer(),
                if (update)
                  TextButton(
                    onPressed: busy ? null : () => install(plugin),
                    child: const Text('更新'),
                  ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => run(() => registry.uninstall(plugin.id)),
                  child: const Text('卸载'),
                ),
              ],
            ),
            if (plugin.settings.isNotEmpty)
              ExpansionTile(
                key: PageStorageKey('plugin-settings-expanded-${plugin.id}'),
                tilePadding: EdgeInsets.zero,
                title: const Text('插件设置', style: TextStyle(fontSize: 13)),
                children: plugin.settings
                    .map((s) => setting(plugin, item, s))
                    .toList(),
              ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.library,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: const Text('插件商城'),
        actions: [
          IconButton(
            tooltip: '插件开发文档',
            onPressed: () => launchUrl(
              Uri.parse(
                'https://github.com/LexianLix/manxia/blob/main/docs/PLUGINS.md',
              ),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.code),
          ),
          PopupMenuButton<String>(
            tooltip: '插件管理',
            enabled: !busy,
            onSelected: (value) async {
              if (value == 'file') {
                await importFile();
              }
              if (value == 'json') {
                final text = await input('从 JSON 安装', '', multiline: true);
                if (text != null && mounted) {
                  try {
                    await install(
                      ManxiaPlugin(Map<String, dynamic>.from(jsonDecode(text))),
                    );
                  } catch (e) {
                    if (mounted) setState(() => status = '$e');
                  }
                }
              }
              if (value == 'repo') await repository();
              if (value == 'bundled') {
                setState(() {
                  catalog = PluginCatalog.bundled();
                  status = '内置目录 · 可离线安装';
                });
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'file', child: Text('导入插件文件')),
              PopupMenuItem(value: 'json', child: Text('从 JSON 安装')),
              PopupMenuItem(value: 'repo', child: Text('添加 / 刷新在线仓库')),
              PopupMenuItem(value: 'bundled', child: Text('使用内置目录')),
            ],
          ),
        ],
      ),
      body: FutureBuilder<List<ManxiaPlugin>>(
        future: catalog,
        builder: (context, state) {
          final plugins = installedOnly
              ? registry.installed
                    .map(
                      (e) => ManxiaPlugin(
                        Map<String, dynamic>.from(e['manifest']),
                      ),
                    )
                    .toList()
              : state.data ?? [];
          final shown = plugins
              .where(
                (p) => '${p.name} ${p.author} ${p.description}'
                    .toLowerCase()
                    .contains(search.toLowerCase()),
              )
              .toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 140),
            children: [
              const Text(
                '你的漫匣，\n由你定义。',
                style: TextStyle(fontSize: 24, height: 1.3),
              ),
              const SizedBox(height: 12),
              const Text(
                '主题、阅读习惯与常用入口，组合成自己的阅读室。',
                style: TextStyle(fontSize: 12, height: 1.7),
              ),
              const SizedBox(height: 24),
              SegmentedButton<bool>(
                segments: [
                  const ButtonSegment(value: false, label: Text('发现插件')),
                  ButtonSegment(
                    value: true,
                    label: Text('已安装 ${registry.installed.length}'),
                  ),
                ],
                selected: {installedOnly},
                onSelectionChanged: (v) =>
                    setState(() => installedOnly = v.first),
              ),
              const SizedBox(height: 18),
              TextField(
                onChanged: (v) => setState(() => search = v),
                decoration: const InputDecoration(
                  hintText: '搜索插件、作者或用途',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 12),
              Text(status, style: const TextStyle(fontSize: 11)),
              if (busy || state.connectionState == ConnectionState.waiting)
                const LinearProgressIndicator(),
              if (state.hasError && !installedOnly)
                Text('目录读取失败：${state.error}'),
              const SizedBox(height: 18),
              if (shown.isEmpty &&
                  state.connectionState != ConnectionState.waiting)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 36),
                  child: Text('这里还没有插件。可以浏览内置目录，或导入自己制作的 JSON 插件。'),
                ),
              ...shown.map(tile),
              const SizedBox(height: 16),
              const Text(
                '声明式插件 API 1 · 支持主题、阅读预设、静态 HTML 漫画源和导航布局。',
                style: TextStyle(fontSize: 11, height: 1.8),
              ),
            ],
          );
        },
      ),
    ),
  );
}
