import 'package:flutter/material.dart';
import '../data/library.dart';
import '../data/plugin.dart';
import 'glass_navigation.dart';

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
  const PersonalizationSettings({super.key, required this.library});
  final Library library;
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
          title: Text(title),
          subtitle: Text(hint, style: const TextStyle(fontSize: 12)),
          value: library.option<bool>(key, fallback),
          onChanged: (v) => library.setOption(key, v),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 26),
        Text(
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
          title: const Text('书架疏密'),
          trailing: DropdownButton<String>(
            value: library.option<String>('shelfDensity', 'balanced'),
            items: const [
              DropdownMenuItem(value: 'compact', child: Text('紧凑')),
              DropdownMenuItem(value: 'balanced', child: Text('均衡')),
              DropdownMenuItem(value: 'airy', child: Text('舒展')),
            ],
            onChanged: (v) {
              if (v != null) library.setOption('shelfDensity', v);
            },
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('启动后打开'),
          trailing: DropdownButton<int>(
            value: ids.contains(library.option<int>('startTab', 0))
                ? library.option<int>('startTab', 0)
                : 0,
            items: ids
                .map(
                  (id) => DropdownMenuItem(
                    value: id,
                    child: Text(roomDestinations[id].label),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) library.setOption('startTab', v);
            },
          ),
        ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('底部入口与顺序'),
          subtitle: const Text(
            '3–6 个入口；书架和设置常驻。拖动已选入口排序。',
            style: TextStyle(fontSize: 11),
          ),
          children: [
            ReorderableListView.builder(
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
                title: Text(roomDestinations[ids[i]].label),
              ),
            ),
            ...roomDestinations.map(
              (d) => CheckboxListTile(
                title: Text(d.label),
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
              child: const Text('恢复插件 / 默认布局'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          '阅读默认习惯',
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontSize: 13,
          ),
        ),
        const Divider(),
        const Text('逐本设置优先；已启用的阅读插件可提供默认预设。', style: TextStyle(fontSize: 11)),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('阅读时保持亮屏'),
          value: defaults['keepAwake'] == true,
          onChanged: (v) => reader('keepAwake', v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('宽屏默认双页'),
          value: defaults['doublePage'] != false,
          onChanged: (v) => reader('doublePage', v),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('阅读默认背景'),
          trailing: DropdownButton<String>(
            value: defaults['background'] as String? ?? 'ink',
            items: const [
              DropdownMenuItem(value: 'ink', child: Text('夜墨')),
              DropdownMenuItem(value: 'paper', child: Text('纸白')),
              DropdownMenuItem(value: 'sepia', child: Text('旧纸')),
            ],
            onChanged: (v) {
              if (v != null) reader('background', v);
            },
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('阅读工具栏自动收起'),
          trailing: DropdownButton<int>(
            value: library.option<int>('chromeTimeout', 0),
            items: const [
              DropdownMenuItem(value: 0, child: Text('手动控制')),
              DropdownMenuItem(value: 3, child: Text('3 秒')),
              DropdownMenuItem(value: 5, child: Text('5 秒')),
              DropdownMenuItem(value: 8, child: Text('8 秒')),
            ],
            onChanged: (v) {
              if (v != null) library.setOption('chromeTimeout', v);
            },
          ),
        ),
      ],
    );
  }
}
