import 'package:flutter/material.dart';
import '../data/comic.dart';
import '../data/chapter_matching.dart';
import 'localized_text.dart';

class ChapterMatchPage extends StatefulWidget {
  const ChapterMatchPage({
    super.key,
    required this.record,
    required this.detail,
  });
  final ReadingRecord record;
  final ComicDetail detail;
  @override
  State<ChapterMatchPage> createState() => _ChapterMatchState();
}

class _ChapterMatchState extends State<ChapterMatchPage> {
  late final candidates = matchChapters(
    Chapter(widget.record.chapterPath, widget.record.chapterTitle),
    widget.detail.chapters,
  );
  Chapter? selected;
  String query = '';
  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final shown = candidates
        .where((c) => chapterName(c.chapter.title).contains(chapterName(query)))
        .toList();
    return Scaffold(
      appBar: AppBar(title: const LocalizedText('匹配新来源章节')),
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      18,
                      keyboard ? 4 : 18,
                      18,
                      keyboard ? 4 : 18,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!keyboard) ...[
                          Text(
                            widget.detail.comic.title,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          LocalizedText(
                            '原进度：{chapter} · 第 {page} 页',
                            arguments: {
                              'chapter': widget.record.chapterTitle,
                              'page': widget.record.page + 1,
                            },
                          ),
                          const SizedBox(height: 8),
                          const LocalizedText(
                            '不同来源的章节和图片可能不同。请确认对应章节，新源从章首开始；原收藏和进度保留。',
                          ),
                          const SizedBox(height: 12),
                        ],
                        TextField(
                          key: const ValueKey('chapter-match-query'),
                          onChanged: (v) => setState(() => query = v),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search),
                            hint: const LocalizedText('搜索对应章节'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (shown.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: LocalizedText('没有匹配的章节')),
                  )
                else
                  SliverList.builder(
                    itemCount: shown.length,
                    itemBuilder: (_, i) => ListTile(
                      selected: selected?.path == shown[i].chapter.path,
                      leading: Icon(
                        selected?.path == shown[i].chapter.path
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                      ),
                      title: Text(shown[i].chapter.title),
                      subtitle: LocalizedText(
                        shown[i].score == 100
                            ? '名称一致，仍需确认来源内容'
                            : shown[i].score >= 60
                            ? '编号相近，请核对分卷与上下篇'
                            : '请手动核对',
                      ),
                      onTap: () {
                        FocusScope.of(context).unfocus();
                        setState(() => selected = shown[i].chapter);
                      },
                    ),
                  ),
              ],
            ),
          ),
          if (!keyboard)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 12,
                  children: [
                    FilledButton(
                      onPressed: selected == null
                          ? null
                          : () => Navigator.pop(context, selected),
                      child: const LocalizedText('从此章节开头继续'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const LocalizedText('仅查看详情'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
