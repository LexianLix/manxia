import 'localized_text.dart';
import 'package:flutter/material.dart';
import '../data/comic.dart';
import '../data/library.dart';
import 'book_object.dart';

Future<void> editBook(
  BuildContext context,
  Library library,
  Comic comic,
) async {
  final meta = library.meta(comic);
  final group = TextEditingController(text: meta['group'] ?? '未分组');
  final tags = TextEditingController(
    text: (meta['tags'] as List? ?? []).join('，'),
  );
  final series = TextEditingController(text: meta['series'] ?? '');
  String status = meta['status'] ?? '未读';
  final save = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, update) => AlertDialog(
        title: LocalizedText(comic.title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: group,
                decoration: const InputDecoration(label: LocalizedText('书架分组')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: series,
                decoration: const InputDecoration(label: LocalizedText('系列套装')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: tags,
                decoration: const InputDecoration(
                  label: LocalizedText('标签（逗号分隔）'),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: status,
                items: ['未读', '在读', '已读', '搁置']
                    .map(
                      (v) =>
                          DropdownMenuItem(value: v, child: LocalizedText(v)),
                    )
                    .toList(),
                onChanged: (v) => update(() => status = v!),
                decoration: const InputDecoration(label: LocalizedText('阅读状态')),
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
            child: const LocalizedText('保存'),
          ),
        ],
      ),
    ),
  );
  if (save == true) {
    await library.setMeta(comic, {
      'group': group.text.trim().isEmpty ? '未分组' : group.text.trim(),
      'series': series.text.trim(),
      'tags': tags.text
          .split(RegExp(r'[,，]'))
          .map((v) => v.trim())
          .where((v) => v.isNotEmpty)
          .toList(),
      'status': status,
    });
  }
  group.dispose();
  tags.dispose();
  series.dispose();
}

class LibraryManager extends StatefulWidget {
  const LibraryManager({
    super.key,
    required this.library,
    required this.web,
    required this.onOpen,
  });
  final Library library;
  final bool web;
  final ValueChanged<Comic> onOpen;
  @override
  State<LibraryManager> createState() => _LibraryManagerState();
}

class _LibraryManagerState extends State<LibraryManager> {
  final selection = <String>{};
  String query = '', group = '全部', status = '全部';
  bool series = false;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.library,
    builder: (c, _) {
      final library = widget.library;
      final books = library.favorites
          .where(
            (b) =>
                b.title.contains(query) &&
                (group == '全部' || library.meta(b)['group'] == group) &&
                (status == '全部' || library.meta(b)['status'] == status),
          )
          .toList();
      final sets = <String, List<Comic>>{};
      for (final b in books) {
        final name = library.meta(b)['series'] as String? ?? '';
        if (name.isNotEmpty) (sets[name] ??= []).add(b);
      }
      return Scaffold(
        appBar: AppBar(
          title: const LocalizedText('整理书架', style: TextStyle(fontSize: 21)),
          actions: [
            IconButton(
              tooltip: series ? '返回列表' : '系列套装',
              onPressed: () => setState(() => series = !series),
              icon: Icon(
                series ? Icons.view_list_outlined : Icons.inventory_2_outlined,
              ),
            ),
            PopupMenuButton<String>(
              tooltip: '书架排序',
              onSelected: (sort) {
                final list = [...library.favorites];
                switch (sort) {
                  case '书名':
                    list.sort((a, b) => a.title.compareTo(b.title));
                  case '最近阅读':
                    list.sort(
                      (a, b) => (library.record(b)?.updatedAt ?? 0).compareTo(
                        library.record(a)?.updatedAt ?? 0,
                      ),
                    );
                  case '最近更新':
                    list.sort(
                      (a, b) =>
                          (library.updates[b.path]?['updatedAt'] as int? ?? 0)
                              .compareTo(
                                library.updates[a.path]?['updatedAt'] as int? ??
                                    0,
                              ),
                    );
                }
                library.reorder(list);
              },
              itemBuilder: (_) => ['书名', '最近阅读', '最近更新']
                  .map((s) => PopupMenuItem(value: s, child: LocalizedText(s)))
                  .toList(),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 15),
              child: TextField(
                onChanged: (v) => setState(() => query = v),
                decoration: const InputDecoration(
                  hint: LocalizedText('搜索收藏'),
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  for (final g in library.groups)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: LocalizedText(g),
                        selected: group == g,
                        onSelected: (_) => setState(() => group = g),
                      ),
                    ),
                  const SizedBox(width: 10),
                  DropdownButton<String>(
                    value: status,
                    items: ['全部', '未读', '在读', '已读', '搁置']
                        .map(
                          (s) => DropdownMenuItem(
                            value: s,
                            child: LocalizedText(s),
                          ),
                        )
                        .toList(),
                    onChanged: (s) => setState(() => status = s!),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 15),
            if (selection.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    LocalizedText('已选 ${selection.length} 册'),
                    const Spacer(),
                    TextButton(
                      onPressed: () async {
                        final input = TextEditingController();
                        final name = await showDialog<String>(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: const LocalizedText('批量移入分组'),
                            content: TextField(
                              controller: input,
                              decoration: const InputDecoration(
                                hint: LocalizedText('输入分组名称'),
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(c, input.text.trim()),
                                child: const LocalizedText('保存'),
                              ),
                            ],
                          ),
                        );
                        input.dispose();
                        if (name != null && name.isNotEmpty) {
                          for (final b in library.favorites.where(
                            (b) => selection.contains(b.path),
                          )) {
                            await library.setMeta(b, {'group': name});
                          }
                          if (mounted) setState(selection.clear);
                        }
                      },
                      child: const LocalizedText('移入分组'),
                    ),
                    TextButton(
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: const LocalizedText('移出所选收藏？'),
                            content: const LocalizedText('只移除收藏，离线文件与阅读记录保留。'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(c, false),
                                child: const LocalizedText('取消'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(c, true),
                                child: const LocalizedText('移出'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true) {
                          for (final b in [
                            ...library.favorites,
                          ].where((b) => selection.contains(b.path))) {
                            await library.toggle(b);
                          }
                          if (mounted) setState(selection.clear);
                        }
                      },
                      child: const LocalizedText('移出收藏'),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: series ? seriesView(sets) : booksView(books, library),
            ),
          ],
        ),
      );
    },
  );
  Widget seriesView(Map<String, List<Comic>> sets) => ListView(
    children: [
      if (sets.isEmpty)
        const Padding(
          padding: EdgeInsets.all(35),
          child: LocalizedText('在漫画整理菜单填写“系列套装”，即可在这里陈列。'),
        ),
      for (final entry in sets.entries)
        ExpansionTile(
          title: LocalizedText(entry.key),
          subtitle: LocalizedText('${entry.value.length} 册'),
          leading: const Icon(Icons.inventory_2_outlined),
          children: [
            SizedBox(
              height: 210,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final b in entry.value)
                    SizedBox(
                      width: 130,
                      child: InkWell(
                        onTap: () => widget.onOpen(b),
                        child: BookObject(b, web: widget.web),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
    ],
  );
  Widget booksView(List<Comic> books, Library library) =>
      ReorderableListView.builder(
        buildDefaultDragHandles:
            query.isEmpty && group == '全部' && status == '全部',
        itemCount: books.length,
        onReorderItem: (oldIndex, newIndex) {
          if (query.isNotEmpty || group != '全部' || status != '全部') return;
          final list = [...library.favorites];
          final item = list.removeAt(oldIndex);
          list.insert(newIndex, item);
          library.reorder(list);
        },
        itemBuilder: (c, i) {
          final b = books[i];
          final m = library.meta(b);
          return ListTile(
            key: ValueKey(b.path),
            leading: Checkbox(
              value: selection.contains(b.path),
              onChanged: (v) => setState(() {
                if (v == true) {
                  selection.add(b.path);
                } else {
                  selection.remove(b.path);
                }
              }),
            ),
            title: LocalizedText(b.title, style: const TextStyle(fontSize: 14)),
            subtitle: LocalizedText(
              '${m['group'] ?? '未分组'} · ${m['status'] ?? '未读'}',
              style: const TextStyle(fontSize: 11),
            ),
            trailing: Padding(
              padding: const EdgeInsets.only(right: 35),
              child: IconButton(
                tooltip: '编辑分组与标签',
                onPressed: () => editBook(context, library, b),
                icon: const Icon(Icons.more_horiz),
              ),
            ),
            onTap: () => widget.onOpen(b),
          );
        },
      );
}
