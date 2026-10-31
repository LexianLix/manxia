import 'package:flutter/material.dart';
import '../data/comic.dart';
import '../data/dm5_source.dart';
import '../data/follow_calendar.dart';
import '../data/library.dart';
import '../data/offline_library.dart';
import '../data/reading_progress.dart';
import 'app_shell.dart' show EmptyState, friendlyError;
import 'book_object.dart' show ComicCover;
import 'content_handoff.dart';
import 'follow_reminder_sheet.dart';
import 'localized_text.dart';
import 'materials.dart';
import 'reader_page.dart';
import 'room_motion.dart';

class FollowCalendarPage extends StatefulWidget {
  const FollowCalendarPage({
    super.key,
    required this.library,
    required this.source,
    required this.web,
    required this.onOpen,
  });
  final Library library;
  final Dm5Source source;
  final bool web;
  final ValueChanged<Comic> onOpen;
  @override
  State<FollowCalendarPage> createState() => _FollowCalendarState();
}

class _FollowCalendarState extends State<FollowCalendarPage> {
  DateTime selected = DateUtils.dateOnly(DateTime.now());
  late DateTime month = DateTime(selected.year, selected.month);
  String view = '月历';
  bool checking = false, downloading = false;
  String? message;
  String label(String value) =>
      translate(value, Localizations.localeOf(context));
  bool pinned(Comic book) => widget.library.meta(book)['followPinned'] == true;

  Future<void> check() async {
    if (checking) return;
    setState(() {
      checking = true;
      message = null;
    });
    try {
      final failed = await FollowChecker.check(
        widget.library,
        widget.source,
        active: () => mounted,
      );
      if (mounted) {
        setState(
          () => message = failed == 0
              ? '检查完成；首次检查建立基线，之后的新章节记入日历。'
              : '部分作品检查失败，已有日历记录保留。',
        );
      }
    } catch (error) {
      if (mounted) setState(() => message = friendlyError(error));
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  Future<void> read(FollowEvent event) async {
    final library = widget.library, book = event.comic;
    final chapter =
        event.chapters.reversed
            .where((c) => !library.chapterRead(book, c.path))
            .firstOrNull ??
        event.chapters.last;
    final record = library.record(book);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReaderPage(
          comic: book,
          chapter: chapter,
          library: library,
          source: widget.source,
          web: widget.web,
          initialPage: record?.chapterPath == chapter.path ? record?.page : 0,
          initialPosition: record?.chapterPath == chapter.path
              ? record!.position
              : 0,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> download(FollowEvent event) async {
    if (downloading) return;
    setState(() => downloading = true);
    try {
      final offline = OfflineLibrary.instance;
      if (offline == null) throw StateError('离线书库尚未就绪');
      for (final chapter in event.chapters.reversed) {
        if (!widget.library.chapterRead(event.comic, chapter.path)) {
          await offline.enqueue(event.comic, chapter);
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: LocalizedText('待读章节已加入下载队列')));
      }
    } catch (error) {
      if (mounted) setState(() => message = friendlyError(error));
    } finally {
      if (mounted) setState(() => downloading = false);
    }
  }

  Future<void> focusBooks() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    sheetAnimationStyle: RoomMotion.sheet(context),
    builder: (c) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(c).height * .7,
        child: ListenableBuilder(
          listenable: widget.library,
          builder: (_, _) {
            final books = widget.library.favorites
                .where((b) => b.sourceId != 'local')
                .toList();
            return Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: LocalizedText(
                    '选择特别关注的漫画',
                    style: TextStyle(fontSize: 20),
                  ),
                ),
                Expanded(
                  child: books.isEmpty
                      ? const Center(child: LocalizedText('收藏在线漫画后，可以在这里特别关注'))
                      : ListView.builder(
                          itemCount: books.length,
                          itemBuilder: (_, i) => CheckboxListTile(
                            value: pinned(books[i]),
                            title: Text(books[i].title),
                            onChanged: (value) => widget.library.setMeta(
                              books[i],
                              {'followPinned': value == true},
                            ),
                          ),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );

  Widget calendar(List<FollowEvent> events) {
    final local = MaterialLocalizations.of(context);
    final first = DateTime(month.year, month.month);
    final offset = (first.weekday % 7 - local.firstDayOfWeekIndex + 7) % 7;
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    final counts = <int, int>{};
    for (final e in events) {
      final date = e.observedAt;
      if (date.year == month.year && date.month == month.month) {
        counts[date.day] = (counts[date.day] ?? 0) + 1;
      }
    }
    return MilkGlass(
      high: false,
      radius: 20,
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: label('上个月'),
                icon: const Icon(Icons.chevron_left),
                onPressed: () => setState(
                  () => month = DateTime(month.year, month.month - 1),
                ),
              ),
              Expanded(
                child: Text(
                  local.formatMonthYear(month),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: label('下个月'),
                icon: const Icon(Icons.chevron_right),
                onPressed: () => setState(
                  () => month = DateTime(month.year, month.month + 1),
                ),
              ),
            ],
          ),
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Center(
                    child: Text(
                      local.narrowWeekdays[(local.firstDayOfWeekIndex + i) % 7],
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, box) => Wrap(
              children: [
                for (var i = 0; i < ((offset + days + 6) ~/ 7) * 7; i++)
                  SizedBox(
                    width: box.maxWidth / 7,
                    height: 52,
                    child: i < offset || i >= offset + days
                        ? null
                        : day(i - offset + 1, counts),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget day(int number, Map<int, int> counts) {
    final date = DateTime(month.year, month.month, number);
    final active = DateUtils.isSameDay(date, selected);
    final count = counts[number] ?? 0;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: active,
      label:
          '${MaterialLocalizations.of(context).formatFullDate(date)}, $count ${label('部更新')}',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => selected = date),
        child: AnimatedContainer(
          duration: RoomMotion.duration(context, RoomMotion.feedback),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: active ? scheme.primaryContainer : Colors.transparent,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ExcludeSemantics(
                child: Text(
                  '$number',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 4,
                width: 4,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: count > 0 ? scheme.primary : Colors.transparent,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget eventTile(FollowEvent event) {
    final unread = widget.library.eventUnread(event);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: MilkGlass(
        high: false,
        radius: 16,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 48,
                  height: 66,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: ComicCover(event.comic, web: widget.web),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () => widget.onOpen(event.comic),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.comic.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        LocalizedText(
                          '检查到更新 · {date}',
                          arguments: {
                            'date': MaterialLocalizations.of(
                              context,
                            ).formatCompactDate(event.observedAt),
                          },
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          event.chapters
                              .map((c) => c.title)
                              .take(3)
                              .join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: label(pinned(event.comic) ? '取消特别关注' : '特别关注'),
                  onPressed: () => widget.library.setMeta(event.comic, {
                    'followPinned': !pinned(event.comic),
                  }),
                  icon: Icon(
                    pinned(event.comic)
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => read(event),
                  icon: const Icon(Icons.menu_book_outlined, size: 18),
                  label: LocalizedText(unread ? '阅读新章' : '再次阅读'),
                ),
                TextButton(
                  onPressed: unread && !downloading
                      ? () => download(event)
                      : null,
                  child: const LocalizedText('下载待读'),
                ),
                TextButton(
                  onPressed: () => widget.library.markEventRead(event, unread),
                  child: LocalizedText(unread ? '标为已读' : '标为未读'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const LocalizedText('追漫日历'),
      actions: [
        IconButton(
          tooltip: label('追漫提醒'),
          icon: const Icon(Icons.notifications_none_rounded),
          onPressed: () => showFollowReminder(context),
        ),
        IconButton(
          tooltip: label('检查更新'),
          icon: const Icon(Icons.refresh_rounded),
          onPressed:
              checking ||
                  !widget.library.favorites.any((b) => b.sourceId != 'local')
              ? null
              : check,
        ),
      ],
    ),
    body: ListenableBuilder(
      listenable: widget.library,
      builder: (context, _) {
        final events = widget.library.followEvents;
        final list = events
            .where(
              (e) => view == '待读'
                  ? widget.library.eventUnread(e)
                  : view == '特别关注'
                  ? pinned(e.comic)
                  : DateUtils.isSameDay(e.observedAt, selected),
            )
            .toList();
        list.sort((a, b) {
          final priority = (pinned(b.comic) ? 1 : 0).compareTo(
            pinned(a.comic) ? 1 : 0,
          );
          return priority != 0
              ? priority
              : b.observedAt.compareTo(a.observedAt);
        });
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const LocalizedText(
                      '把更新留在日历里',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const LocalizedText('日期表示漫匣检查到更新的时间；原站未提供发布时间时不作推测。'),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final value in ['月历', '待读', '特别关注'])
                          ChoiceChip(
                            label: LocalizedText(value),
                            selected: view == value,
                            onSelected: (_) => setState(() => view = value),
                          ),
                        TextButton(
                          onPressed: focusBooks,
                          child: const LocalizedText('管理关注'),
                        ),
                        if (view == '月历')
                          TextButton(
                            onPressed: () => setState(() {
                              selected = DateUtils.dateOnly(DateTime.now());
                              month = DateTime(selected.year, selected.month);
                            }),
                            child: const LocalizedText('今天'),
                          ),
                      ],
                    ),
                    if (checking) const LinearProgressIndicator(),
                    if (message != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: LocalizedText(message!),
                      ),
                    if (view == '月历') calendar(events),
                    const SizedBox(height: 16),
                    ContentHandoff(
                      child: LocalizedText(
                        view == '月历'
                            ? MaterialLocalizations.of(
                                context,
                              ).formatFullDate(selected)
                            : view,
                        key: ValueKey((view, selected)),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (list.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: EmptyState(
                    icon: Icons.auto_stories_outlined,
                    title: view == '待读' ? '暂时没有待读新章' : '这里还没有更新记录',
                    message: '首次检查建立基线，后续新章节才会记入日历。可点击右上角检查更新。',
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
              sliver: SliverList.builder(
                itemCount: list.length,
                itemBuilder: (_, i) => eventTile(list[i]),
              ),
            ),
          ],
        );
      },
    ),
  );
}
