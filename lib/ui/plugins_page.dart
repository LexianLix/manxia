import 'localized_text.dart';
import 'plugin_labels.dart';
import 'plugin_effects_page.dart';
import 'character_settings_page.dart';
import 'companion.dart';
import 'preference_choice.dart';
import '../data/plugin_package.dart';
import '../data/character_definition.dart';
import 'visible_listenable_builder.dart';
import 'script_source_check_page.dart';
import '../data/source_profile.dart';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/library.dart';
import '../data/plugin_registry.dart';

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
        title: LocalizedText(title),
        content: SizedBox(
          width: 520,
          child: TextFormField(
            initialValue: initial,
            minLines: multiline ? 8 : 1,
            maxLines: multiline ? 16 : 3,
            onChanged: (v) => text = v,
            decoration: InputDecoration(
              labelText: translate(
                multiline ? '插件 manifest JSON' : 'HTTPS 仓库 index.json 地址',
                Localizations.localeOf(context),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const LocalizedText('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, text),
            child: const LocalizedText('继续'),
          ),
        ],
      ),
    );
  }

  Future<void> install(ManxiaPlugin plugin) async {
    if (kIsWeb && plugin.apiVersion == 2) {
      setState(() => status = '脚本漫画源需要 Android');
      return;
    }
    final source = plugin.contributions['source'];
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          plugin.localized('name', Localizations.localeOf(context).toString()),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${plugin.author} · v${plugin.version} · ${plugin.json['license']}',
              ),
              const SizedBox(height: 16),
              Text(
                plugin.localized(
                  'description',
                  Localizations.localeOf(context).toString(),
                ),
              ),
              if (plugin.contributions['character'] is Map)
                Center(
                  child: CompanionPortrait(
                    size: 96,
                    expression: 'happy',
                    definition: CharacterDefinition(
                      Map<String, dynamic>.from(
                        plugin.contributions['character'],
                      ),
                    ),
                    resources: plugin.resources,
                  ),
                ),
              const SizedBox(height: 20),
              Text(
                translate(
                  '扩展范围：{capabilities}',
                  Localizations.localeOf(context),
                  arguments: {
                    'capabilities': plugin.capabilities
                        .map(
                          (c) => translate(
                            capabilityLabels[c]!,
                            Localizations.localeOf(context),
                          ),
                        )
                        .join(' · '),
                  },
                ),
              ),
              if (source is Map) ...[
                const SizedBox(height: 12),
                Text(
                  '漫画站点：${source['baseUrl']}\n图片域名：${source['imageHosts'] ?? '与站点相同'}',
                ),
              ],
              if (plugin.apiVersion == 2) ...[
                const SizedBox(height: 12),
                const LocalizedText('脚本请求域名'),
                Text(
                  SourceProfile.scripted(
                    Map<String, dynamic>.from(source as Map),
                  ).requestHosts.join('\n'),
                ),
                const SizedBox(height: 8),
                const LocalizedText('脚本由 Android 隔离执行，只能向获准域名请求数据。'),
              ],
              const SizedBox(height: 12),
              const LocalizedText('启用后立即应用；可在“已安装”停用或卸载。个人书籍与逐本阅读设置保留。'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const LocalizedText('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const LocalizedText('安装并启用'),
          ),
        ],
      ),
    );
    if (ok == true) await run(() => registry.install(plugin));
  }

  Future<void> importFile() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json', 'zip'],
    );
    if (file == null || !mounted) return;
    try {
      if ((await file.length() ?? 0) > 2 * 1024 * 1024) {
        throw const FormatException('请选择小于 2 MB 的 JSON 或角色 ZIP 插件');
      }
      await install(PluginPackage.decode(await file.readAsBytes()));
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
          status = translate(
            '在线仓库 · {count} 个插件',
            Localizations.localeOf(context),
            arguments: {'count': plugins.length},
          );
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
    final title = LocalizedText(definition['label']);
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
      'choice' => PreferenceChoice<String>(
        title: definition['label'],
        value: value,
        choices: {
          for (final v in definition['choices'] as List)
            v.toString(): v.toString(),
        },
        onChanged: busy ? null : save,
      ),
      _ => Padding(
        key: PageStorageKey('plugin-setting-field-${plugin.id}-$key'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: TextFormField(
          key: ValueKey('${plugin.id}-$key-$value'),
          initialValue: value,
          decoration: InputDecoration(
            labelText: translate(
              definition['label'],
              Localizations.localeOf(context),
            ),
            helperText: translate(
              '#RRGGBB · 回车应用',
              Localizations.localeOf(context),
            ),
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
                  plugin.capabilities.contains('character')
                      ? Icons.face_outlined
                      : plugin.capabilities.contains('theme')
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
                    Text(
                      plugin.localized(
                        'name',
                        Localizations.localeOf(context).toString(),
                      ),
                      style: const TextStyle(fontSize: 16),
                    ),
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
                      : (v) {
                          if (v && item['manifest']['apiVersion'] == 2) {
                            install(
                              ManxiaPlugin(
                                Map<String, dynamic>.from(item['manifest']),
                              ),
                            );
                          } else {
                            run(() => registry.enable(plugin.id, v));
                          }
                        },
                )
              else
                FilledButton(
                  onPressed: busy || kIsWeb && plugin.apiVersion == 2
                      ? null
                      : () => install(plugin),
                  child: LocalizedText(
                    kIsWeb && plugin.apiVersion == 2 ? '仅 Android' : '安装',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            plugin.localized(
              'description',
              Localizations.localeOf(context).toString(),
            ),
            style: const TextStyle(fontSize: 12, height: 1.7),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: plugin.capabilities
                .map(
                  (c) => LocalizedText(
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
                LocalizedText(
                  active ? '已启用' : '已停用',
                  style: TextStyle(fontSize: 11, color: color),
                ),
                const Spacer(),
                if (update)
                  TextButton(
                    onPressed: busy ? null : () => install(plugin),
                    child: const LocalizedText('更新'),
                  ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => run(() => registry.uninstall(plugin.id)),
                  child: const LocalizedText('卸载'),
                ),
              ],
            ),
            if (item['manifest']['apiVersion'] == 2)
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: busy || !active
                        ? null
                        : () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ScriptSourceCheckPage(
                                source: SourceProfile.scripted(
                                  Map<String, dynamic>.from(
                                    item['manifest']['contributes']['source'],
                                  ),
                                ),
                              ),
                            ),
                          ),
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const LocalizedText('试跑脚本源'),
                  ),
                  if (item['previous'] != null)
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => run(() => registry.rollback(plugin.id)),
                      child: const LocalizedText('回退上一版'),
                    ),
                  TextButton(
                    onPressed:
                        busy ||
                            !active ||
                            widget.library.options['source'] ==
                                item['manifest']['contributes']['source']['id']
                        ? null
                        : () => run(
                            () => widget.library.setOption(
                              'source',
                              item['manifest']['contributes']['source']['id'],
                            ),
                          ),
                    child: LocalizedText(
                      widget.library.options['source'] ==
                              item['manifest']['contributes']['source']['id']
                          ? '当前默认发现源'
                          : '设为默认发现源',
                    ),
                  ),
                ],
              ),
            if (plugin.settings.isNotEmpty)
              ExpansionTile(
                key: PageStorageKey('plugin-settings-expanded-${plugin.id}'),
                tilePadding: EdgeInsets.zero,
                title: const LocalizedText(
                  '插件设置',
                  style: TextStyle(fontSize: 13),
                ),
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
  Widget build(BuildContext context) => VisibleListenableBuilder(
    listenable: widget.library,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: const LocalizedText('插件商城'),
        actions: [
          PopupMenuButton<String>(
            tooltip: translate('插件管理', Localizations.localeOf(context)),
            enabled: !busy,
            onSelected: (value) async {
              if (value == 'effects') {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PluginEffectsPage(library: widget.library),
                  ),
                );
              }
              if (value == 'characters' && context.mounted) {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        CharacterSettingsPage(library: widget.library),
                  ),
                );
              }
              if (value == 'docs') {
                await launchUrl(
                  Uri.parse(
                    'https://github.com/LexianLix/manxia/blob/main/docs/PLUGINS.md',
                  ),
                  mode: LaunchMode.externalApplication,
                );
              }
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
              PopupMenuItem(value: 'effects', child: LocalizedText('生效与覆盖关系')),
              PopupMenuItem(
                value: 'characters',
                child: LocalizedText('小夏与阅读伙伴'),
              ),
              PopupMenuItem(value: 'file', child: LocalizedText('导入插件文件')),
              PopupMenuItem(value: 'json', child: LocalizedText('从 JSON 安装')),
              PopupMenuItem(value: 'repo', child: LocalizedText('添加 / 刷新在线仓库')),
              PopupMenuItem(value: 'bundled', child: LocalizedText('使用内置目录')),
              PopupMenuItem(value: 'docs', child: LocalizedText('插件开发文档')),
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
                (p) =>
                    '${p.name} ${p.author} ${p.description} ${p.localized('name', Localizations.localeOf(context).toString())} ${p.localized('description', Localizations.localeOf(context).toString())}'
                        .toLowerCase()
                        .contains(search.toLowerCase()),
              )
              .toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 32),
            children: [
              const LocalizedText(
                '你的漫匣，\n由你定义。',
                style: TextStyle(fontSize: 22, height: 1.3),
              ),
              const SizedBox(height: 12),
              const LocalizedText(
                '主题、阅读习惯与常用入口，组合成自己的阅读室。',
                style: TextStyle(fontSize: 12, height: 1.7),
              ),
              const SizedBox(height: 24),
              SegmentedButton<bool>(
                segments: [
                  const ButtonSegment(
                    value: false,
                    label: LocalizedText('发现插件'),
                  ),
                  ButtonSegment(
                    value: true,
                    label: LocalizedText(
                      '已安装 {count}',
                      arguments: {'count': registry.installed.length},
                    ),
                  ),
                ],
                selected: {installedOnly},
                onSelectionChanged: (v) =>
                    setState(() => installedOnly = v.first),
              ),
              const SizedBox(height: 18),
              TextField(
                onChanged: (v) => setState(() => search = v),
                decoration: InputDecoration(
                  hintText: translate(
                    '搜索插件、作者或用途',
                    Localizations.localeOf(context),
                  ),
                  prefixIcon: const Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 12),
              LocalizedText(status, style: const TextStyle(fontSize: 11)),
              if (busy || state.connectionState == ConnectionState.waiting)
                const LinearProgressIndicator(),
              if (state.hasError && !installedOnly)
                LocalizedText(
                  '目录读取失败：{message}',
                  arguments: {'message': '${state.error}'},
                ),
              const SizedBox(height: 18),
              if (shown.isEmpty &&
                  state.connectionState != ConnectionState.waiting)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 36),
                  child: LocalizedText('这里还没有插件。可以浏览内置目录，或导入 JSON、角色 ZIP 插件。'),
                ),
              ...shown.map(tile),
              const SizedBox(height: 16),
              const LocalizedText(
                'API 1 支持声明式扩展。API 2 支持 Android 脚本漫画源。',
                style: TextStyle(fontSize: 11, height: 1.8),
              ),
            ],
          );
        },
      ),
    ),
  );
}
