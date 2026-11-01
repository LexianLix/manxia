import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../data/library.dart';
import '../data/plugin_registry.dart';
import '../data/plugin_package.dart';
import '../data/character_definition.dart';
import 'companion.dart';
import 'localized_text.dart';
import 'preference_choice.dart';
import 'room_motion.dart';
import 'visible_listenable_builder.dart';

class CharacterSettingsPage extends StatefulWidget {
  const CharacterSettingsPage({super.key, required this.library});
  final Library library;
  @override
  State<CharacterSettingsPage> createState() => _CharacterSettingsPageState();
}

class _CharacterSettingsPageState extends State<CharacterSettingsPage> {
  late final registry = PluginRegistry(widget.library);
  late final official = PluginCatalog.bundled().then(
    (v) => v.firstWhere((p) => p.id == 'manxia.xiaxia'),
  );
  bool busy = false;
  String? error;
  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> preference(String key, dynamic value) => run(
    () => widget.library.setOption('companion', {
      ...CompanionPreferences(widget.library.options).values,
      key: value,
    }),
  );
  Future<void> importRole() => run(() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['zip', 'json'],
    );
    if (file == null) return;
    if ((await file.length() ?? 0) > 2 * 1024 * 1024) {
      throw const FormatException('角色包不能超过 2 MB');
    }
    final plugin = PluginPackage.decode(await file.readAsBytes());
    if (!plugin.contributions.containsKey('character')) {
      throw const FormatException('请选择角色插件');
    }
    await registry.install(plugin);
  });
  Future<void> exportRole(ManxiaPlugin plugin) => run(() async {
    final bytes = await PluginPackage.encode(plugin, registry.assets);
    await FilePicker.saveFile(
      fileName: '${plugin.id}-${plugin.version}.zip',
      bytes: bytes,
      mimeType: 'application/zip',
    );
  });
  Future<void> remove(ManxiaPlugin plugin) async {
    final ok = await showDialog<bool>(
      context: context,
      animationStyle: RoomMotion.sheet(context),
      builder: (c) => AlertDialog(
        title: const LocalizedText('卸载角色？'),
        content: const LocalizedText('将删除不再使用的角色图片。自制角色请先导出 ZIP；书库和阅读进度会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const LocalizedText('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const LocalizedText('卸载'),
          ),
        ],
      ),
    );
    if (ok == true) await run(() => registry.uninstall(plugin.id));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const LocalizedText('小夏与阅读伙伴')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: VisibleListenableBuilder(
            listenable: widget.library,
            builder: (context, _) {
              final prefs = CompanionPreferences(widget.library.options);
              final roles = registry.installed
                  .where(
                    (e) => (e['manifest']['contributes'] as Map).containsKey(
                      'character',
                    ),
                  )
                  .toList();
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  const LocalizedText(
                    '轻轻陪你，留出阅读的空间。',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  const LocalizedText(
                    '角色只出现在书架、空状态和操作反馈中。阅读正文自动隐藏，不请求通知权限。',
                    style: TextStyle(fontSize: 12, height: 1.7),
                  ),
                  const SizedBox(height: 16),
                  FutureBuilder<ManxiaPlugin>(
                    future: official,
                    builder: (c, s) {
                      if (s.data == null) return const SizedBox.shrink();
                      final p = s.data!;
                      return Column(
                        children: [
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            children: [
                              for (final state in [
                                'idle',
                                'blink',
                                'happy',
                                'puzzled',
                              ])
                                CompanionPortrait(
                                  expression: state,
                                  size: 64,
                                  definition: CharacterDefinition(
                                    Map<String, dynamic>.from(
                                      p.contributions['character'],
                                    ),
                                  ),
                                  resources: p.resources,
                                ),
                            ],
                          ),
                          if (registry.entry(p.id) == null)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: FilledButton.icon(
                                onPressed: busy
                                    ? null
                                    : () => run(() => registry.install(p)),
                                icon: const Icon(Icons.add, size: 18),
                                label: const LocalizedText('安装并启用小夏'),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const LocalizedText('显示阅读伙伴'),
                    value: prefs.visible,
                    onChanged: busy ? null : (v) => preference('visible', v),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const LocalizedText('角色小动作'),
                    subtitle: const LocalizedText('轻轻眨眼；遵守系统减少动效'),
                    value: prefs.animate,
                    onChanged: busy ? null : (v) => preference('animate', v),
                  ),
                  PreferenceChoice<String>(
                    title: '角色大小',
                    value: prefs.size,
                    choices: const {'small': '小', 'normal': '标准', 'large': '大'},
                    onChanged: busy
                        ? null
                        : (v) => preference('size', v ?? 'small'),
                  ),
                  PreferenceChoice<String>(
                    title: '陪伴提醒',
                    value: prefs.frequency,
                    choices: const {'quiet': '安静', 'normal': '标准', 'off': '关闭'},
                    onChanged: busy
                        ? null
                        : (v) => preference('frequency', v ?? 'quiet'),
                  ),
                  const SizedBox(height: 8),
                  const LocalizedText(
                    '安静模式每 30 秒最多提醒一次；标准模式为 8 秒。提醒在 4 秒后自动收起，可随时关闭。',
                    style: TextStyle(fontSize: 12, height: 1.7),
                  ),
                  const Divider(height: 32),
                  const LocalizedText(
                    '已安装角色',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (roles.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: LocalizedText('还没有安装角色，安装后即可显示。'),
                    ),
                  for (final entry in roles)
                    Builder(
                      builder: (c) {
                        final p = ManxiaPlugin(
                          Map<String, dynamic>.from(entry['manifest']),
                        );
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CompanionPortrait(
                            size: 48,
                            definition: CharacterDefinition(
                              Map<String, dynamic>.from(
                                p.resolve(
                                  Map<String, dynamic>.from(
                                    entry['config'] ?? {},
                                  ),
                                )['character'],
                              ),
                            ),
                          ),
                          title: Text(
                            p.localized(
                              'name',
                              Localizations.localeOf(c).toString(),
                            ),
                          ),
                          subtitle: LocalizedText(
                            entry['enabled'] == true ? '已启用' : '已停用',
                          ),
                          trailing: PopupMenuButton<String>(
                            enabled: !busy,
                            tooltip: translate(
                              '更多操作',
                              Localizations.localeOf(c),
                            ),
                            onSelected: (v) {
                              switch (v) {
                                case 'toggle':
                                  run(
                                    () => registry.enable(
                                      p.id,
                                      entry['enabled'] != true,
                                    ),
                                  );
                                case 'export':
                                  exportRole(p);
                                case 'remove':
                                  remove(p);
                              }
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'toggle',
                                child: LocalizedText(
                                  entry['enabled'] == true ? '停用' : '启用',
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'export',
                                child: LocalizedText('导出角色 ZIP'),
                              ),
                              const PopupMenuItem(
                                value: 'remove',
                                child: LocalizedText('卸载'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : importRole,
                      icon: const Icon(Icons.file_open_outlined, size: 18),
                      label: const LocalizedText('导入角色 ZIP'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const LocalizedText(
                    '角色图片随 ZIP 单独导入导出；书库 JSON 备份只保存插件清单。恢复自制角色后，需重新导入原 ZIP。',
                    style: TextStyle(fontSize: 12, height: 1.7),
                  ),
                  if (busy)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: LinearProgressIndicator(),
                    ),
                  if (error != null)
                    SelectableText(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}
