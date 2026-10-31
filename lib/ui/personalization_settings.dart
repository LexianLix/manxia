import 'package:flutter/material.dart';
import '../data/library.dart';
import '../data/plugin.dart';
import 'glass_navigation.dart';
import 'localized_text.dart';

List<int> navigationIds(Library library) {
  final manual = library.options['navigation'];
  final raw = manual is List
      ? manual
      : PluginSnapshot(library.options).navigation;
  if (raw is List &&
      raw.length >= 3 &&
      raw.length <= 6 &&
      raw.contains(0) &&
      raw.contains(3) &&
      raw.every((id) => id is int && id >= 0 && id < roomDestinations.length) &&
      raw.toSet().length == raw.length) {
    return List<int>.from(raw);
  }
  return [0, 1, 4, 5, 3];
}

class PersonalizationSettings extends StatelessWidget {
  const PersonalizationSettings({
    super.key,
    required this.library,
    this.section,
  });
  final Library library;
  final String? section;
  @override
  Widget build(BuildContext context) {
    final ids = navigationIds(library);
    final rawDefaults = library.options['readerDefaults'];
    final defaults = rawDefaults is Map
        ? Map<String, dynamic>.from(rawDefaults)
        : <String, dynamic>{};
    void reader(String key, dynamic value) =>
        library.setOption('readerDefaults', {...defaults, key: value});
    Widget toggle(String key, String title, String hint, bool fallback) =>
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: LocalizedText(title),
          subtitle: LocalizedText(hint, style: const TextStyle(fontSize: 12)),
          value: library.option<bool>(key, fallback),
          onChanged: (v) => library.setOption(key, v),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (section != 'reading') ...[
          const SizedBox(height: 26),
          LocalizedText(
            '定制你的阅读室',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 13,
            ),
          ),
          const Divider(),
          toggle('liquidNavigation', '水滴导航', '拖动时拉伸连接，松手后吸附归位', true),
          toggle('bookOpening', '翻开实体书', '封面与书页绕书脊展开，返回时合书归位', true),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const LocalizedText('书架疏密'),
            trailing: DropdownButton<String>(
              value: library.option<String>('shelfDensity', 'balanced'),
              items: const [
                DropdownMenuItem(value: 'compact', child: LocalizedText('紧凑')),
                DropdownMenuItem(value: 'balanced', child: LocalizedText('均衡')),
                DropdownMenuItem(value: 'airy', child: LocalizedText('舒展')),
              ],
              onChanged: (v) {
                if (v != null) library.setOption('shelfDensity', v);
              },
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const LocalizedText('启动后打开'),
            trailing: DropdownButton<int>(
              value: ids.contains(library.option<int>('startTab', 0))
                  ? library.option<int>('startTab', 0)
                  : 0,
              items: ids
                  .map(
                    (id) => DropdownMenuItem(
                      value: id,
                      child: LocalizedText(roomDestinations[id].label),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) library.setOption('startTab', v);
              },
            ),
          ),
          ExpansionTile(
            key: const PageStorageKey('settings-navigation-expanded'),
            tilePadding: EdgeInsets.zero,
            title: const LocalizedText('底部入口与顺序'),
            subtitle: const LocalizedText(
              '3–6 个入口；书架和设置常驻。拖动已选入口排序。',
              style: TextStyle(fontSize: 11),
            ),
            children: [
              ReorderableListView.builder(
                key: const PageStorageKey('settings-navigation-reorder-scroll'),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: ids.length,
                onReorderItem: (from, to) {
                  final next = [...ids];
                  next.insert(to, next.removeAt(from));
                  library.setOption('navigation', next);
                },
                itemBuilder: (context, i) => ListTile(
                  key: ValueKey('nav-${ids[i]}'),
                  leading: Icon(roomDestinations[ids[i]].icon),
                  title: LocalizedText(roomDestinations[ids[i]].label),
                ),
              ),
              ...roomDestinations.map(
                (d) => CheckboxListTile(
                  title: LocalizedText(d.label),
                  value: ids.contains(d.id),
                  onChanged: [0, 3].contains(d.id)
                      ? null
                      : (value) {
                          if (value == false && ids.length <= 3) return;
                          library.setOption(
                            'navigation',
                            value == true
                                ? [...ids, d.id]
                                : ids.where((id) => id != d.id).toList(),
                          );
                        },
                ),
              ),
              TextButton(
                onPressed: () => library.setOption('navigation', null),
                child: const LocalizedText('恢复插件 / 默认布局'),
              ),
            ],
          ),
        ],
        if (section != 'appearance') ...[
          const SizedBox(height: 20),
          LocalizedText(
            '阅读默认习惯',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 13,
            ),
          ),
          const Divider(),
          const LocalizedText(
            '逐本设置优先；已启用的阅读插件可提供默认预设。',
            style: TextStyle(fontSize: 11),
          ),
          toggle('autoArchiveRead', '读完自动归档', '只有全部已知章节标为已读时归档，收藏与进度保留', false),
          toggle('warmNextChapter', '预备下一章首屏', '接近章末时准备下一章，关闭预载时不请求', true),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const LocalizedText('阅读时保持亮屏'),
            value: defaults['keepAwake'] == true,
            onChanged: (v) => reader('keepAwake', v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const LocalizedText('宽屏默认双页'),
            value: defaults['doublePage'] != false,
            onChanged: (v) => reader('doublePage', v),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const LocalizedText('阅读默认背景'),
            trailing: DropdownButton<String>(
              value: defaults['background'] as String? ?? 'theme',
              items: const [
                DropdownMenuItem(value: 'theme', child: LocalizedText('跟随应用')),
                DropdownMenuItem(value: 'ink', child: LocalizedText('夜墨')),
                DropdownMenuItem(value: 'paper', child: LocalizedText('纸白')),
                DropdownMenuItem(value: 'sepia', child: LocalizedText('旧纸')),
              ],
              onChanged: (v) {
                if (v != null) reader('background', v);
              },
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const LocalizedText('阅读工具栏自动收起'),
            trailing: DropdownButton<int>(
              value: library.option<int>('chromeTimeout', 0),
              items: const [
                DropdownMenuItem(value: 0, child: LocalizedText('手动控制')),
                DropdownMenuItem(value: 3, child: LocalizedText('3 秒')),
                DropdownMenuItem(value: 5, child: LocalizedText('5 秒')),
                DropdownMenuItem(value: 8, child: LocalizedText('8 秒')),
              ],
              onChanged: (v) {
                if (v != null) library.setOption('chromeTimeout', v);
              },
            ),
          ),
        ],
      ],
    );
  }
}
