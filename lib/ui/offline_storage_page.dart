import 'package:flutter/material.dart';
import '../data/comic.dart';
import '../data/library.dart';
import '../data/offline_library.dart';
import '../data/reading_progress.dart';
import 'localized_text.dart';
import 'room_motion.dart';

class OfflineStoragePage extends StatefulWidget {
  const OfflineStoragePage({
    super.key,
    required this.library,
    required this.offline,
    this.comic,
  });
  final Library library;
  final OfflineLibrary offline;
  final Comic? comic;
  @override
  State<OfflineStoragePage> createState() => _OfflineStorageState();
}

class _OfflineStorageState extends State<OfflineStoragePage> {
  final selected = <String>{};
  String filter = '全部';
  bool cleaning = false;
  String size(int value) => '${(value / 1024 / 1024).toStringAsFixed(1)} MB';
  bool isRead(Map e) => widget.library.chapterRead(
    Comic.fromJson(Map<String, dynamic>.from(e['comic'])),
    e['chapter']['path'],
  );
  List<Map<String, dynamic>> get scoped => widget.offline.entries
      .where(
        (e) => widget.comic == null || e['comic']['path'] == widget.comic!.path,
      )
      .toList();
  List<Map<String, dynamic>> get shown => scoped
      .where((e) => filter == '全部' || (filter == '已读' ? isRead(e) : !isRead(e)))
      .toList();
  Future<void> clean(Iterable<String> ids) async {
    final snapshot = widget.offline.entries
        .where((e) => ids.contains(e['id']) && e['status'] == 'complete')
        .toList();
    if (snapshot.isEmpty || cleaning) return;
    final keys = snapshot.map((e) => e['id'] as String).toSet();
    final confirmed = await showDialog<bool>(
      context: context,
      animationStyle: RoomMotion.sheet(context),
      builder: (c) => AlertDialog(
        title: const LocalizedText('清理选中的离线章节？'),
        scrollable: true,
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LocalizedText(
                '将移除 {count} 章，释放 {size}。收藏、书签和阅读进度保留。',
                arguments: {
                  'count': snapshot.length,
                  'size': size(widget.offline.reclaimableBytes(keys)),
                },
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 180,
                child: ListView.builder(
                  itemCount: snapshot.length,
                  itemBuilder: (_, i) => ListTile(
                    dense: true,
                    title: Text(snapshot[i]['comic']['title']),
                    subtitle: Text(snapshot[i]['chapter']['title']),
                  ),
                ),
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
            child: const LocalizedText('清理'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => cleaning = true);
    try {
      await widget.offline.removeMany(keys);
      selected.removeAll(keys);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: LocalizedText('选中章节已清理，阅读资料保留')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => cleaning = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: widget.comic == null
          ? const LocalizedText('离线空间')
          : Text(widget.comic!.title),
    ),
    body: ListenableBuilder(
      listenable: Listenable.merge([widget.library, widget.offline]),
      builder: (context, _) {
        final offline = widget.offline;
        final list = shown;
        final books = <String, Comic>{
          for (final e in scoped)
            e['comic']['path']: Comic.fromJson(
              Map<String, dynamic>.from(e['comic']),
            ),
        }.values.toList();
        final read = scoped
            .where((e) => e['status'] == 'complete' && isRead(e))
            .toList();
        final cap = widget.library.option<int>('offlineLimitMb', 0);
        return Column(
          children: [
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LocalizedText(
                            '已用 {size}',
                            arguments: {'size': size(offline.bytes)},
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (cap > 0) ...[
                            const SizedBox(height: 10),
                            LinearProgressIndicator(
                              value: (offline.bytes / offline.capacityBytes)
                                  .clamp(0, 1),
                            ),
                            const SizedBox(height: 8),
                          ],
                          if (offline.nearCapacity)
                            const LocalizedText('接近容量上限，可清理已读章节或调整上限。'),
                          if (widget.comic == null) const SizedBox(height: 12),
                          if (widget.comic == null)
                            DropdownButtonFormField<int>(
                              isExpanded: true,
                              initialValue: cap,
                              decoration: const InputDecoration(
                                label: LocalizedText('下载容量上限'),
                              ),
                              items: {0, 256, 512, 1024, 2048, 4096, 8192, cap}
                                  .map(
                                    (value) => DropdownMenuItem(
                                      value: value,
                                      child: value == 0
                                          ? const LocalizedText('不设上限')
                                          : Text('$value MB'),
                                    ),
                                  )
                                  .toList(),
                              onChanged: cleaning
                                  ? null
                                  : (value) {
                                      if (value != null) {
                                        widget.library.setOption(
                                          'offlineLimitMb',
                                          value,
                                        );
                                      }
                                    },
                            ),
                          if (widget.comic == null)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: LocalizedText(
                                '达到上限会暂停下载；调整上限后可回下载页继续任务。',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          if (widget.comic != null)
                            Wrap(
                              spacing: 8,
                              children: [
                                for (final value in ['全部', '已读', '未读'])
                                  ChoiceChip(
                                    label: LocalizedText(value),
                                    selected: filter == value,
                                    onSelected: (_) =>
                                        setState(() => filter = value),
                                  ),
                                TextButton(
                                  onPressed: cleaning
                                      ? null
                                      : () => setState(
                                          () => selected.addAll(
                                            list
                                                .where(
                                                  (e) =>
                                                      e['status'] == 'complete',
                                                )
                                                .map((e) => e['id'] as String),
                                          ),
                                        ),
                                  child: const LocalizedText('选择当前筛选'),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (cleaning)
                    const SliverToBoxAdapter(child: LinearProgressIndicator()),
                  if (scoped.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: LocalizedText('当前筛选没有离线章节')),
                    )
                  else if (widget.comic == null)
                    SliverList.builder(
                      itemCount: books.length,
                      itemBuilder: (context, i) {
                        final book = books[i],
                            entries = scoped
                                .where(
                                  (e) => e['comic']['path'] == books[i].path,
                                )
                                .toList();
                        return ListTile(
                          title: Text(book.title),
                          subtitle: LocalizedText(
                            '{count} 章 · {size}',
                            arguments: {
                              'count': entries.length,
                              'size': size(
                                offline.reclaimableBytes(
                                  entries.map((e) => e['id'] as String),
                                ),
                              ),
                            },
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: cleaning
                              ? null
                              : () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => OfflineStoragePage(
                                      library: widget.library,
                                      offline: offline,
                                      comic: book,
                                    ),
                                  ),
                                ),
                        );
                      },
                    )
                  else if (list.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: LocalizedText('当前筛选没有离线章节')),
                    )
                  else
                    SliverList.builder(
                      itemCount: list.length,
                      itemBuilder: (context, i) {
                        final entry = list[i], id = entry['id'] as String;
                        return CheckboxListTile(
                          value: selected.contains(id),
                          onChanged: cleaning || entry['status'] != 'complete'
                              ? null
                              : (value) => setState(() {
                                  if (value == true) {
                                    selected.add(id);
                                  } else {
                                    selected.remove(id);
                                  }
                                }),
                          title: Text(entry['chapter']['title']),
                          subtitle: LocalizedText(
                            '{state} · {size}',
                            arguments: {
                              'state': translate(
                                isRead(entry) ? '已读' : '未读',
                                Localizations.localeOf(context),
                              ),
                              'size': size(entry['bytes'] as int? ?? 0),
                            },
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.tonalIcon(
                  icon: const Icon(Icons.cleaning_services_outlined),
                  label: LocalizedText(
                    widget.comic == null
                        ? '清理已读章节（{count}）'
                        : '清理选中章节（{count}）',
                    arguments: {
                      'count': widget.comic == null
                          ? read.length
                          : selected.length,
                    },
                  ),
                  onPressed:
                      cleaning ||
                          (widget.comic == null
                              ? read.isEmpty
                              : selected.isEmpty)
                      ? null
                      : () => clean(
                          widget.comic == null
                              ? read.map((e) => e['id'] as String)
                              : selected,
                        ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}
