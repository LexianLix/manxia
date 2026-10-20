import 'localized_text.dart';
import 'package:flutter/material.dart';
import '../data/library.dart';
import '../data/dm5_source.dart';
import '../data/comic.dart';
import 'book_object.dart';
import 'reader_page.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({
    super.key,
    required this.library,
    required this.source,
    required this.web,
  });
  final Library library;
  final Dm5Source source;
  final bool web;
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  String query = '';
  bool marks = false;
  bool favoritesOnly = false;
  void read(ReadingRecord r) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ReaderPage(
        comic: r.comic,
        chapter: Chapter(r.chapterPath, r.chapterTitle),
        library: widget.library,
        source: widget.source,
        web: widget.web,
        initialPage: r.page,
        initialPosition: r.position,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.library,
    builder: (c, _) {
      final records = widget.library.history
          .where(
            (r) => '${r.comic.title} ${r.chapterTitle}'.toLowerCase().contains(
              query.toLowerCase(),
            ),
          )
          .toList();
      String? lastDate;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LocalizedText(
            '阅读足迹',
            style: TextStyle(fontSize: 30, letterSpacing: 2),
          ),
          const SizedBox(height: 10),
          const LocalizedText('沿着书签，回到故事停下的地方。'),
          const SizedBox(height: 24),
          TextField(
            onChanged: (v) => setState(() => query = v),
            decoration: const InputDecoration(
              hint: LocalizedText('搜索漫画、章节或笔记'),
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 16),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: LocalizedText('最近阅读')),
              ButtonSegment(value: true, label: LocalizedText('书签与笔记')),
            ],
            selected: {marks},
            onSelectionChanged: (v) => setState(() => marks = v.first),
          ),
          const SizedBox(height: 24),
          if (marks) ...[
            FilterChip(
              label: const LocalizedText('只看页面收藏'),
              selected: favoritesOnly,
              onSelected: (v) => setState(() => favoritesOnly = v),
            ),
            if (widget.library.bookmarks.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: LocalizedText('阅读时点击书签，即可在这里保存某一页和笔记。'),
              ),
            for (final b in widget.library.bookmarks.where(
              (b) =>
                  (!favoritesOnly || b['favorite'] == true) &&
                  '${b['comic']['title']} ${b['note']} ${b['chapterTitle']}'
                      .toLowerCase()
                      .contains(query.toLowerCase()),
            ))
              ListTile(
                title: LocalizedText(b['comic']['title']),
                subtitle: LocalizedText(
                  '${b['chapterTitle']} · 第 ${(b['page'] as int) + 1} 页\n${b['note']}',
                ),
                trailing: IconButton(
                  tooltip: '删除书签',
                  icon: const Icon(Icons.bookmark_remove_outlined),
                  onPressed: () => widget.library.removeBookmark(b['id']),
                ),
                onTap: () => read(
                  ReadingRecord(
                    comic: Comic.fromJson(
                      Map<String, dynamic>.from(b['comic']),
                    ),
                    chapterPath: b['chapterPath'],
                    chapterTitle: b['chapterTitle'],
                    page: b['page'],
                    position: (b['position'] as num? ?? 0).toDouble(),
                    total: 0,
                    updatedAt: 0,
                  ),
                ),
              ),
          ] else ...[
            if (records.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: LocalizedText('这里还没有足迹，去翻开第一本漫画吧。'),
              ),
            for (final r in records) ...[
              if (lastDate !=
                  DateTime.fromMillisecondsSinceEpoch(
                    r.updatedAt,
                  ).toIso8601String().substring(0, 10))
                Padding(
                  padding: const EdgeInsets.only(top: 18, bottom: 10),
                  child: LocalizedText(
                    lastDate = DateTime.fromMillisecondsSinceEpoch(
                      r.updatedAt,
                    ).toIso8601String().substring(0, 10),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: SizedBox(
                  width: 44,
                  height: 62,
                  child: ComicCover(r.comic, web: widget.web),
                ),
                title: LocalizedText(r.comic.title),
                subtitle: LocalizedText(
                  '${r.chapterTitle} · 第 ${r.page + 1} / ${r.total} 页',
                ),
                onTap: () => read(r),
                trailing: IconButton(
                  tooltip: '移除这条足迹',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => widget.library.removeHistory(r.comic),
                ),
              ),
            ],
          ],
        ],
      );
    },
  );
}
