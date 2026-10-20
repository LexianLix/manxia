import 'localized_text.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../data/comic.dart';
import '../data/dm5_source.dart';
import '../data/file_actions.dart';
import '../data/library.dart';
import '../data/offline_library.dart';
import 'book_object.dart';
import 'reader_page.dart';

class OfflinePage extends StatefulWidget {
  const OfflinePage({
    super.key,
    required this.library,
    required this.source,
    required this.web,
  });
  final Library library;
  final Dm5Source source;
  final bool web;
  @override
  State<OfflinePage> createState() => _OfflinePageState();
}

class _OfflinePageState extends State<OfflinePage> {
  bool busy = false;
  String? message;
  Future<void> import(String type) async {
    final offline = OfflineLibrary.instance;
    if (offline == null) return;
    setState(() {
      busy = true;
      message = '正在选择并导入漫画…';
    });
    try {
      final comic = await FileActions.importBook(
        offline,
        images: type == 'images',
        folder: type == 'folder',
      );
      if (mounted) {
        setState(
          () => message = comic == null ? null : '${comic.title} 已加入本地书库',
        );
      }
    } catch (e) {
      if (mounted) setState(() => message = '导入失败：$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext c) {
    final offline = OfflineLibrary.instance;
    return Scaffold(
      appBar: AppBar(
        title: const LocalizedText('下载与本地书库', style: TextStyle(fontSize: 21)),
        actions: [
          PopupMenuButton<String>(
            tooltip: '导入漫画',
            enabled: !busy,
            onSelected: import,
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'archive',
                child: LocalizedText('导入 ZIP / CBZ / PDF'),
              ),
              const PopupMenuItem(
                value: 'images',
                child: LocalizedText('多选图片导入'),
              ),
              if (!kIsWeb)
                const PopupMenuItem(
                  value: 'folder',
                  child: LocalizedText('导入图片文件夹'),
                ),
            ],
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: offline == null
          ? const Center(child: LocalizedText('离线书库尚未初始化'))
          : ListenableBuilder(
              listenable: offline,
              builder: (c, _) => Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 18, 22, 15),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              LocalizedText(
                                '${offline.entries.where((e) => e['status'] == 'complete').length} 个离线章节',
                                style: const TextStyle(fontSize: 23),
                              ),
                              const SizedBox(height: 7),
                              LocalizedText(
                                '已用 ${(offline.bytes / 1024 / 1024).toStringAsFixed(1)} MB · 文件保存在当前设备',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: '刷新任务',
                          onPressed: offline.pump,
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                  ),
                  if (busy) const LinearProgressIndicator(minHeight: 2),
                  if (message != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 12,
                      ),
                      child: LocalizedText(
                        message!,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  if (offline.entries.isEmpty)
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.auto_stories_outlined, size: 40),
                            const SizedBox(height: 22),
                            const LocalizedText(
                              '把故事带到离线的地方',
                              style: TextStyle(fontSize: 21),
                            ),
                            const SizedBox(height: 10),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 28),
                              child: LocalizedText(
                                '可从漫画详情下载章节，也可以导入本地漫画。',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            FilledButton.icon(
                              onPressed: busy ? null : () => import('archive'),
                              icon: const Icon(Icons.file_open_outlined),
                              label: const LocalizedText('导入漫画'),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        itemCount: offline.entries.length,
                        itemBuilder: (c, i) {
                          final e = offline.entries[i];
                          final comic = Comic.fromJson(
                            Map<String, dynamic>.from(e['comic']),
                          );
                          final chapter = Chapter.fromJson(
                            Map<String, dynamic>.from(e['chapter']),
                          );
                          final status = switch (e['status']) {
                            'complete' => '已离线',
                            'downloading' => '下载中',
                            'queued' => '等待下载',
                            'paused' => '已暂停',
                            _ => '下载失败',
                          };
                          return Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Theme.of(c).dividerColor,
                              ),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    SizedBox(
                                      width: 48,
                                      height: 64,
                                      child: ComicCover(comic, web: widget.web),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          LocalizedText(
                                            comic.title,
                                            style: const TextStyle(
                                              fontSize: 15,
                                            ),
                                          ),
                                          const SizedBox(height: 5),
                                          LocalizedText(
                                            '${chapter.title} · $status',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    PopupMenuButton<String>(
                                      tooltip: '离线章节操作',
                                      onSelected: (action) async {
                                        try {
                                          if (action == 'pause') {
                                            await offline.pause(e['id']);
                                          }
                                          if (action == 'resume') {
                                            await offline.resume(e['id']);
                                          }
                                          if (action == 'export') {
                                            await FileActions.exportChapter(
                                              offline,
                                              e,
                                            );
                                          }
                                          if (action == 'delete' ||
                                              action == 'deleteComic') {
                                            if (!c.mounted) return;
                                            final ok = await showDialog<bool>(
                                              context: c,
                                              builder: (d) => AlertDialog(
                                                title: LocalizedText(
                                                  action == 'deleteComic'
                                                      ? '清理这本漫画的全部离线文件？'
                                                      : '删除离线章节？',
                                                ),
                                                content: LocalizedText(
                                                  '将移除此设备上的 ${comic.title} ${chapter.title}。收藏与阅读记录会保留。',
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(d, false),
                                                    child: const LocalizedText(
                                                      '取消',
                                                    ),
                                                  ),
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(d, true),
                                                    child: const LocalizedText(
                                                      '删除',
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                            if (ok == true) {
                                              if (action == 'deleteComic') {
                                                await offline.removeComic(
                                                  comic.path,
                                                );
                                              } else {
                                                await offline.remove(e['id']);
                                              }
                                            }
                                          }
                                        } catch (error) {
                                          if (mounted) {
                                            setState(
                                              () => message = error.toString(),
                                            );
                                          }
                                        }
                                      },
                                      itemBuilder: (_) => [
                                        if ([
                                          'queued',
                                          'downloading',
                                        ].contains(e['status']))
                                          const PopupMenuItem(
                                            value: 'pause',
                                            child: LocalizedText('暂停下载'),
                                          ),
                                        if ([
                                          'paused',
                                          'failed',
                                        ].contains(e['status']))
                                          const PopupMenuItem(
                                            value: 'resume',
                                            child: LocalizedText('继续 / 重试'),
                                          ),
                                        if (e['status'] == 'complete')
                                          const PopupMenuItem(
                                            value: 'export',
                                            child: LocalizedText('导出 CBZ'),
                                          ),
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: LocalizedText('删除离线章节'),
                                        ),
                                        const PopupMenuItem(
                                          value: 'deleteComic',
                                          child: LocalizedText('清理这本漫画的离线文件'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                if (e['status'] == 'downloading' ||
                                    e['status'] == 'paused' ||
                                    e['status'] == 'failed') ...[
                                  LinearProgressIndicator(
                                    value: (e['total'] as int) > 0
                                        ? (e['done'] as int) /
                                              (e['total'] as int)
                                        : null,
                                    minHeight: 2,
                                  ),
                                  const SizedBox(height: 8),
                                  LocalizedText(
                                    '${e['done']} / ${e['total']} 页',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                                if (e['error'] != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: LocalizedText(
                                      e['error'],
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.orange,
                                      ),
                                    ),
                                  ),
                                if (e['status'] == 'complete')
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton.icon(
                                      onPressed: () => Navigator.push(
                                        c,
                                        MaterialPageRoute(
                                          builder: (_) => ReaderPage(
                                            comic: comic,
                                            chapter: chapter,
                                            chapters: offline.chapters(comic),
                                            library: widget.library,
                                            source: widget.source,
                                            web: widget.web,
                                          ),
                                        ),
                                      ),
                                      icon: const Icon(
                                        Icons.menu_book_outlined,
                                        size: 16,
                                      ),
                                      label: const LocalizedText(
                                        '离线阅读',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

Future<void> selectDownloads(
  BuildContext context,
  Comic comic,
  List<Chapter> chapters,
) async {
  final offline = OfflineLibrary.instance;
  if (offline == null) return;
  final selected = <String>{};
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => StatefulBuilder(
      builder: (c, update) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(c).height * .75,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Row(
                  children: [
                    const LocalizedText(
                      '选择离线章节',
                      style: TextStyle(fontSize: 21),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => update(() {
                        if (selected.length == chapters.length) {
                          selected.clear();
                        } else {
                          selected.addAll(chapters.map((c) => c.path));
                        }
                      }),
                      child: const LocalizedText('全选'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: chapters.length,
                  itemBuilder: (c, i) {
                    final chapter = chapters[i];
                    final exists = offline.entries.any(
                      (e) => e['chapter']['path'] == chapter.path,
                    );
                    return CheckboxListTile(
                      title: LocalizedText(
                        chapter.title,
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: exists ? const LocalizedText('已在离线书库中') : null,
                      value: selected.contains(chapter.path),
                      onChanged: exists
                          ? null
                          : (v) => update(() {
                              if (v == true) {
                                selected.add(chapter.path);
                              } else {
                                selected.remove(chapter.path);
                              }
                            }),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: FilledButton(
                  onPressed: selected.isEmpty
                      ? null
                      : () async {
                          for (final chapter in chapters.where(
                            (c) => selected.contains(c.path),
                          )) {
                            await offline.enqueue(comic, chapter);
                          }
                          if (c.mounted) Navigator.pop(c);
                        },
                  child: LocalizedText('下载 ${selected.length} 个章节'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
