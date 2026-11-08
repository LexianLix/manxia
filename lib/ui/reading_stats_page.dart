import 'package:flutter/material.dart';
import '../data/dm5_source.dart';
import '../data/library.dart';
import '../data/reading_journal.dart';
import '../data/personal_review.dart';
import 'book_navigation.dart';
import 'localized_text.dart';
import 'personal_review.dart';
import 'room_design.dart';
import 'visible_listenable_builder.dart';

String readingDuration(BuildContext context, int milliseconds) {
  final seconds = milliseconds ~/ 1000;
  final locale = Localizations.localeOf(context);
  if (seconds > 0 && seconds < 60) {
    return translate('{count} 秒', locale, arguments: {'count': seconds});
  }
  if (seconds < 3600) {
    return translate('{count} 分钟', locale, arguments: {'count': seconds ~/ 60});
  }
  return translate(
    '{hours} 小时 {minutes} 分钟',
    locale,
    arguments: {'hours': seconds ~/ 3600, 'minutes': seconds % 3600 ~/ 60},
  );
}

class ReadingStatsPage extends StatefulWidget {
  const ReadingStatsPage({
    super.key,
    required this.library,
    required this.source,
    required this.web,
  });
  final Library library;
  final Dm5Source source;
  final bool web;
  @override
  State<ReadingStatsPage> createState() => _ReadingStatsState();
}

class _ReadingStatsState extends State<ReadingStatsPage> {
  String range = 'week';
  Future<void> clear() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const LocalizedText('清空阅读统计？'),
        content: const LocalizedText('仅清空时长和浏览页数，保留收藏、评分与阅读位置。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const LocalizedText('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const LocalizedText('清空'),
          ),
        ],
      ),
    );
    if (yes == true) {
      widget.library.journal.clearStatistics(
        DateTime.now().millisecondsSinceEpoch,
      );
      await widget.library.persistFeatures();
    }
  }

  Widget durationValue(int milliseconds) {
    final seconds = milliseconds ~/ 1000;
    final parts = seconds >= 3600
        ? [(seconds ~/ 3600, '小时'), (seconds % 3600 ~/ 60, '分钟')]
        : seconds >= 60 || seconds == 0
        ? [(seconds ~/ 60, '分钟')]
        : [(seconds, '秒')];
    return Wrap(
      spacing: 8,
      children: [
        for (final part in parts)
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${part.$1}',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(
                  text:
                      ' ${translate(part.$2, Localizations.localeOf(context))}',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget metric(String title, String value, {String? key, Widget? content}) =>
      Expanded(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LocalizedText(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              content ??
                  Text(
                    value,
                    key: key == null ? null : ValueKey(key),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
            ],
          ),
        ),
      );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: RoomGlassBar(
      title: '阅读统计',
      actions: [
        PopupMenuButton<String>(
          tooltip: translate('更多操作', Localizations.localeOf(context)),
          onSelected: (_) => clear(),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'clear', child: LocalizedText('清空阅读统计')),
          ],
        ),
      ],
    ),
    body: VisibleListenableBuilder(
      listenable: widget.library,
      builder: (context, _) {
        final now = DateTime.now(),
            first = DateTime.now().subtract(const Duration(days: 6));
        final since = DateTime(first.year, first.month, first.day);
        final totals = ReadingTotals(
          widget.library.journal,
          since: range == 'week' ? since : null,
        );
        final week = ReadingTotals(widget.library.journal, since: since);
        final ranked = totals.byBook.keys.toList()
          ..sort((a, b) => totals.byBook[b]!.compareTo(totals.byBook[a]!));
        final readChapters = widget.library.metadata.values.fold<int>(
          0,
          (sum, m) =>
              sum +
              (m['readChapters'] is Map
                  ? (m['readChapters'] as Map).values
                        .where((v) => v == true)
                        .length
                  : 0),
        );
        final days = [
          for (var i = 6; i >= 0; i--)
            DateTime(now.year, now.month, now.day - i),
        ];
        final largest = week.byDay.values.fold<int>(1, (a, b) => a > b ? a : b);
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 36),
              children: [
                RoomTabs<String>(
                  value: range,
                  labels: const {'week': '最近七天', 'all': '全部记录'},
                  onChanged: (v) => setState(() => range = v),
                ),
                const SizedBox(height: 22),
                RoomGroupedSection(
                  dividerIndent: 16,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        metric(
                          '有效阅读',
                          readingDuration(context, totals.milliseconds),
                          key: 'reading-time',
                          content: durationValue(totals.milliseconds),
                        ),
                        metric('浏览页数', '${totals.pages}', key: 'reading-pages'),
                      ],
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        metric('阅读作品', '${totals.books.length}'),
                        metric('累计已读章节', '$readChapters'),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 26),
                const LocalizedText(
                  '最近七天',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                RoomGroupedSection(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
                      child: SizedBox(
                        height: 148,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (final day in days)
                              Expanded(
                                child: Semantics(
                                  label:
                                      '${readingDay(day)} · ${readingDuration(context, week.byDay[readingDay(day)] ?? 0)}',
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Container(
                                        width: 18,
                                        height:
                                            8 +
                                            102 *
                                                (week.byDay[readingDay(day)] ??
                                                    0) /
                                                largest,
                                        decoration: BoxDecoration(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary
                                              .withValues(
                                                alpha:
                                                    (week.byDay[readingDay(
                                                              day,
                                                            )] ??
                                                            0) >
                                                        0
                                                    ? .8
                                                    : .09,
                                              ),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 9),
                                      Text(
                                        MaterialLocalizations.of(
                                          context,
                                        ).narrowWeekdays[day.weekday % 7],
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 26),
                const LocalizedText(
                  '常读作品',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                if (ranked.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: LocalizedText('还没有阅读统计，翻开一本漫画开始记录。'),
                  ),
                if (ranked.isNotEmpty)
                  RoomGroupedSection(
                    dividerIndent: 16,
                    children: [
                      for (final path in ranked.take(10))
                        ListTile(
                          title: Text(
                            totals.books[path]!.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            readingDuration(context, totals.byBook[path]!),
                          ),
                          trailing: const Icon(Icons.chevron_right, size: 18),
                          onTap: () => Navigator.push(
                            context,
                            comicDetailRoute(
                              context,
                              comic: totals.books[path]!,
                              library: widget.library,
                              source: widget.source,
                              web: widget.web,
                            ),
                          ),
                        ),
                    ],
                  ),
                const SizedBox(height: 20),
                LocalizedText(
                  '只记录前台显示正文的阅读时间；加载、锁屏和长时间无操作不计入。停留不足两秒的页面不计入浏览页数，旧版本的时长不会补算。',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.7,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class PersonalReviewsPage extends StatelessWidget {
  const PersonalReviewsPage({super.key, required this.library});
  final Library library;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const RoomGlassBar(title: '我的评分与短评'),
    body: VisibleListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final reviews = library.reviewedComics;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView.builder(
              padding: const EdgeInsets.all(22),
              itemCount: reviews.isEmpty ? 1 : reviews.length,
              itemBuilder: (context, i) => reviews.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: LocalizedText('还没有评分与短评，可以在漫画详情中记录感想。'),
                    )
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: RoomGroupedSection(
                        children: [
                          PersonalReviewTile(
                            library: library,
                            comic: reviews[i],
                            showBookTitle: true,
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        );
      },
    ),
  );
}
