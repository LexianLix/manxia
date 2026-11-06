import 'package:flutter/material.dart';
import '../data/library.dart';
import '../data/plugin_registry.dart';
import '../data/reading_profiles.dart';
import '../data/appearance.dart';
import 'companion.dart';
import 'localized_text.dart';
import 'reading_profiles_page.dart';
import 'plugin_labels.dart';
import 'visible_listenable_builder.dart';

class PluginEffectsPage extends StatefulWidget {
  const PluginEffectsPage({super.key, required this.library});
  final Library library;
  @override
  State<PluginEffectsPage> createState() => _PluginEffectsPageState();
}

class _PluginEffectsPageState extends State<PluginEffectsPage> {
  bool busy = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const LocalizedText('生效与覆盖关系')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: VisibleListenableBuilder(
            listenable: widget.library,
            builder: (context, _) {
              final library = widget.library,
                  registry = PluginRegistry(library);
              final snapshot = registry.snapshot;
              final locale = Localizations.localeOf(context);
              final appearance = RoomAppearance(library.options);
              final defaults = ReadingProfile.defaults(library.options);
              String name(ManxiaPlugin p) =>
                  p.localized('name', locale.toString());
              final disabled = registry.installed.where(
                (e) => e['enabled'] != true,
              );
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  const LocalizedText(
                    '现在是谁在生效？',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  const LocalizedText(
                    '逐本设置 > 默认阅读方案 > 阅读插件 > 基础设置',
                    style: TextStyle(fontSize: 12, height: 1.7),
                  ),
                  const LocalizedText(
                    '停用插件会恢复下层设置，不会删除书库或逐本偏好。',
                    style: TextStyle(fontSize: 12, height: 1.7),
                  ),
                  const SizedBox(height: 24),
                  if (snapshot.origins.isEmpty)
                    const LocalizedText('当前使用应用基础设置。'),
                  for (final capability in capabilityLabels.keys)
                    Builder(
                      builder: (c) {
                        final fields = snapshot.origins.entries
                            .where(
                              (e) =>
                                  e.key == capability ||
                                  e.key.startsWith('$capability.'),
                            )
                            .toList();
                        if (fields.isEmpty) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              LocalizedText(
                                capabilityLabels[capability]!,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              for (final e in fields)
                                Builder(
                                  builder: (c) {
                                    final key = e.key
                                        .split('.')
                                        .skip(1)
                                        .join('.');
                                    var label = e.key,
                                        value = '',
                                        state = '正在生效';
                                    if (capability == 'theme') {
                                      label =
                                          const {
                                            'seed': '主色',
                                            'lightSurface': '浅色材质',
                                            'darkSurface': '深色材质',
                                          }[key] ??
                                          key;
                                      value = '${snapshot.theme[key]}';
                                      if (appearance.wallpaper != null &&
                                          appearance.follow) {
                                        state = '由背景图片配色覆盖';
                                      }
                                    } else if (capability == 'reader') {
                                      label = readingOptionLabels[key] ?? key;
                                      value = readingValue(
                                        c,
                                        key,
                                        library.defaultReaderOptions()[key],
                                      );
                                      if (defaults.containsKey(key)) {
                                        state = '由默认阅读方案覆盖';
                                      }
                                    } else if (capability == 'navigation') {
                                      label = '底部导航';
                                      final ids =
                                          library.options['navigation'] is List
                                          ? library.options['navigation']
                                                as List
                                          : snapshot.navigation!;
                                      value = ids
                                          .map(
                                            (id) => translate(
                                              const [
                                                '书架',
                                                '发现',
                                                '足迹',
                                                '设置',
                                                '下载',
                                                '插件',
                                              ][id as int],
                                              locale,
                                            ),
                                          )
                                          .join(' · ');
                                      if (library.options['navigation']
                                          is List) {
                                        state = '由个人导航设置覆盖';
                                      }
                                    } else if (capability == 'character') {
                                      label = '阅读伙伴';
                                      value = '';
                                      if (!CompanionPreferences(
                                        library.options,
                                      ).visible) {
                                        state = '已启用，显示已关闭';
                                      }
                                    } else if (capability == 'source') {
                                      final source = snapshot.sources
                                          .where((s) => s['id'] == key)
                                          .firstOrNull;
                                      label =
                                          source?['name']?.toString() ?? key;
                                      value =
                                          source?['baseUrl']?.toString() ?? '';
                                      state =
                                          library.option<String>(
                                                'source',
                                                'dm5',
                                              ) ==
                                              key
                                          ? '当前漫画源'
                                          : '可在漫画源设置中选用';
                                    }
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 9,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: LocalizedText(
                                                  label,
                                                  style: const TextStyle(
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Flexible(
                                                child: Text(
                                                  value,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                  ),
                                                  textAlign: TextAlign.end,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          LocalizedText(
                                            '{provider} · {state}',
                                            arguments: {
                                              'provider': name(e.value),
                                              'state': translate(state, locale),
                                            },
                                            style: TextStyle(
                                              fontSize: 11,
                                              height: 1.6,
                                              color: Theme.of(
                                                c,
                                              ).colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  if (defaults.isNotEmpty)
                    const LocalizedText('本书已有的单独设置仍然优先。'),
                  if (disabled.isNotEmpty) ...[
                    const Divider(height: 32),
                    const LocalizedText(
                      '已停用插件',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    for (final entry in disabled)
                      Builder(
                        builder: (c) {
                          final p = ManxiaPlugin(
                            Map<String, dynamic>.from(entry['manifest']),
                          );
                          final byEntry = registry.entry(
                            entry['disabledBy']?.toString() ?? '',
                          );
                          final by = byEntry == null
                              ? null
                              : ManxiaPlugin(
                                  Map<String, dynamic>.from(
                                    byEntry['manifest'],
                                  ),
                                );
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(name(p)),
                            subtitle: p.apiVersion == 2
                                ? const LocalizedText('在插件商城确认域名权限后启用')
                                : by == null
                                ? const LocalizedText('手动停用')
                                : LocalizedText(
                                    '被 {name} 停用',
                                    arguments: {'name': name(by)},
                                  ),
                            trailing: p.apiVersion == 2
                                ? null
                                : TextButton(
                                    onPressed: busy
                                        ? null
                                        : () async {
                                            setState(() => busy = true);
                                            try {
                                              await registry.enable(p.id, true);
                                            } catch (e) {
                                              if (c.mounted) {
                                                ScaffoldMessenger.of(
                                                  c,
                                                ).showSnackBar(
                                                  SnackBar(content: Text('$e')),
                                                );
                                              }
                                            } finally {
                                              if (mounted) {
                                                setState(() => busy = false);
                                              }
                                            }
                                          },
                                    child: const LocalizedText('启用'),
                                  ),
                          );
                        },
                      ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}
