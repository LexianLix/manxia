import 'localized_text.dart';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/comic.dart';
import '../data/discovery.dart';
import '../data/dm5_source.dart';
import '../data/library.dart';
import '../data/source_hub.dart';
import 'app_shell.dart' show ComicGrid, EmptyState, friendlyError, quiet, small;
import 'materials.dart';
import 'source_browser.dart';
import 'discovery_collection.dart';
import 'book_link.dart';
import 'retained_sections.dart';
import 'content_handoff.dart';
import 'room_motion.dart';
import 'search_page.dart';

class DiscoveryPage extends StatefulWidget {
  const DiscoveryPage({
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
  State<DiscoveryPage> createState() => _DiscoveryPageState();
}

class _DiscoveryPageState extends State<DiscoveryPage>
    with SingleTickerProviderStateMixin {
  Discovery? shown, pending;
  bool refreshing = false, applying = false;
  final headingKey = GlobalKey();
  late final reveal = AnimationController(
    vsync: this,
    duration: RoomMotion.feedback,
    value: 1,
  );

  String tab = '精选', rank = '人气';
  final tabsKey = GlobalKey();
  void selectTab(String value) {
    setState(() => tab = value);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && tabsKey.currentContext != null) {
        Scrollable.ensureVisible(
          tabsKey.currentContext!,
          alignment: 0,
          duration: RoomMotion.duration(context, RoomMotion.page),
          curve: RoomMotion.ease,
        );
      }
    });
  }

  String? error;
  bool checking = false;
  List<Comic> dailyPicks(Discovery snapshot, DateTime date) => snapshot.daily(
    date,
    edition: widget.library.option<int>('dailyEdition', 0),
  );

  void openCollection(String title, List<Comic> books, {String? path}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DiscoveryCollection(
          title: title,
          books: books,
          library: widget.library,
          source: widget.source,
          web: widget.web,
          onOpen: widget.onOpen,
          path: path,
        ),
      ),
    );
  }

  Widget preview(List<Comic> books) => books.isEmpty
      ? Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: LocalizedText('这个栏目暂时没有漫画，试试其他栏目。', style: small(context)),
        )
      : ComicGrid(
          books: books.take(6).toList(),
          web: widget.web,
          onOpen: widget.onOpen,
          minItemWidth: 106,
        );

  String get cacheKey =>
      'discovery.cache.${widget.library.option<String>('source', 'dm5')}';
  Future<Discovery?> cached() async {
    final saved = widget.library.prefs.getString(cacheKey);
    if (saved != null) {
      try {
        return Discovery.fromJson(jsonDecode(saved), cached: true);
      } catch (_) {
        /* An invalid cache must not block a fresh source request. */
      }
    }
    if (widget.source is SourceHub &&
        (widget.source as SourceHub).selected != null) {
      return null;
    }
    return Discovery.fromJson(
      jsonDecode(await rootBundle.loadString('assets/discovery.json')),
      cached: true,
    );
  }

  @override
  void initState() {
    super.initState();
    initialize();
  }

  Future<void> initialize() async {
    try {
      final saved = await cached();
      if (!mounted) return;
      setState(() => shown = saved);
    } catch (_) {
      /* Network loading remains available without the bundled cache. */
    }
    if (mounted) refresh();
  }

  String contentIdentity(Discovery value) {
    final json = value.toJson()..remove('capturedAt');
    return jsonEncode(json);
  }

  Future<void> refresh() async {
    if (refreshing) return;
    final requestedCache = cacheKey;
    setState(() {
      refreshing = true;
      error = null;
    });
    try {
      final result = await widget.source.discover();
      if (!mounted || cacheKey != requestedCache) return;
      await widget.library.prefs.setString(
        requestedCache,
        jsonEncode(result.toJson()),
      );
      if (!mounted) return;
      setState(() {
        if (shown == null ||
            contentIdentity(shown!) == contentIdentity(result)) {
          shown = result;
          pending = null;
        } else {
          // Keep the list being read, its filters and its scroll extent stable.
          pending = result;
        }
      });
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      if (mounted) setState(() => refreshing = false);
    }
  }

  Future<void> applyPending() async {
    if (pending == null || applying) return;
    setState(() => applying = true);
    try {
      if (headingKey.currentContext != null) {
        await Scrollable.ensureVisible(
          headingKey.currentContext!,
          alignment: 0,
          duration: RoomMotion.duration(context, RoomMotion.page),
          curve: RoomMotion.ease,
        );
      }
      if (!mounted) return;
      if (!MediaQuery.disableAnimationsOf(context)) {
        try {
          await reveal.reverse().orCancel;
        } on TickerCanceled {
          /* Reduction or disposal. */
        }
      }
      if (!mounted) return;
      setState(() {
        shown = pending ?? shown;
        pending = null;
        applying = false;
      });
      if (MediaQuery.disableAnimationsOf(context)) {
        reveal.value = 1;
      } else {
        reveal.forward();
      }
    } finally {
      if (mounted && applying) setState(() => applying = false);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      reveal.value = applying ? 0 : 1;
    }
  }

  @override
  void dispose() {
    reveal.dispose();
    super.dispose();
  }

  Widget heading(String title, String sub, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LocalizedText(
                title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              LocalizedText(sub, style: small(context)),
            ],
          ),
        ),
        ?trailing,
      ],
    ),
  );
  @override
  Widget build(BuildContext context) =>
      ContentHandoff(child: buildContent(context));
  Widget buildContent(BuildContext context) {
    final snapshot = shown;
    if (snapshot == null) {
      if (error != null && !refreshing) {
        return EmptyState(
          key: const ValueKey('discovery-error'),
          icon: Icons.cloud_off,
          title: '暂时无法打开漫画源',
          message: error!,
          action: refresh,
          actionLabel: '重试',
        );
      }
      return Column(
        key: const ValueKey('discovery-loading'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          heading('发现漫画', '正在打开下一段故事'),
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Container(
                height: 140,
                decoration: BoxDecoration(
                  color: quiet(context).withValues(alpha: .06),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
        ],
      );
    }
    final date = DateTime.now().toUtc().add(const Duration(hours: 8));
    final day =
        '${date.month.toString().padLeft(2, '0')} / ${date.day.toString().padLeft(2, '0')}';
    final daily = dailyPicks(snapshot, date);
    final activeRank = snapshot.ranks.containsKey(rank)
        ? rank
        : snapshot.ranks.keys.firstOrNull ?? rank;
    final ranks = snapshot.ranks[activeRank] ?? [];
    final updated = snapshot.sections['万人追更'] ?? [];
    final personal = snapshot.forYou([
      ...widget.library.favorites,
      ...widget.library.history.map((r) => r.comic),
    ], count: snapshot.books.length);
    final editorial = snapshot.sections.entries
        .where((e) => !e.key.contains('VIP'))
        .toList();
    return FadeTransition(
      key: const ValueKey('discovery-ready'),
      opacity: reveal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KeyedSubtree(
            key: headingKey,
            child: heading(
              '发现漫画',
              '今天，也有值得翻开的故事。',
              trailing: pending != null
                  ? TextButton(
                      onPressed: applying ? null : applyPending,
                      child: const LocalizedText('查看新内容'),
                    )
                  : IconButton(
                      tooltip: translate(
                        '刷新发现页',
                        Localizations.localeOf(context),
                      ),
                      onPressed: refreshing ? null : refresh,
                      icon: refreshing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                              ),
                            )
                          : const Icon(Icons.refresh, size: 20),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: InkWell(
              key: const ValueKey('open-comic-search'),
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ComicSearchPage(
                    library: widget.library,
                    source: widget.source,
                    web: widget.web,
                    onOpen: widget.onOpen,
                  ),
                ),
              ),
              child: Ink(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: .045),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, size: 19, color: quiet(context)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: LocalizedText(
                        '搜索漫画名称',
                        style: TextStyle(fontSize: 13, color: quiet(context)),
                      ),
                    ),
                    Icon(Icons.arrow_forward, size: 16, color: quiet(context)),
                  ],
                ),
              ),
            ),
          ),
          SingleChildScrollView(
            key: tabsKey,
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final label in ['精选', '排行', '更新', '分类', '书单'])
                  Padding(
                    padding: const EdgeInsets.only(right: 20),
                    child: Semantics(
                      selected: tab == label,
                      child: InkWell(
                        onTap: () => selectTab(label),
                        child: AnimatedContainer(
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: tab == label
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                          ),
                          child: LocalizedText(
                            label,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: tab == label
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: tab == label
                                  ? Theme.of(context).colorScheme.primary
                                  : quiet(context),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ContentHandoff(
              child: Row(
                key: ValueKey((
                  pending != null,
                  error != null,
                  refreshing,
                  snapshot.cached,
                )),
                children: [
                  Icon(
                    pending != null
                        ? Icons.update
                        : error != null
                        ? Icons.cloud_off_outlined
                        : Icons.check_circle_outline,
                    size: 14,
                    color: quiet(context),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LocalizedText(
                      pending != null
                          ? '发现页有新内容，当前列表已保留'
                          : error != null
                          ? '刷新失败，已保留当前目录'
                          : refreshing
                          ? '正在刷新，仍可继续浏览'
                          : snapshot.cached
                          ? '正在浏览离线目录'
                          : '目录已更新',
                      style: small(context),
                    ),
                  ),
                  if (error != null && !refreshing)
                    TextButton(
                      onPressed: refresh,
                      child: const LocalizedText('重试'),
                    ),
                ],
              ),
            ),
          ),
          RetainedSections(
            index: tab,
            order: const ['精选', '排行', '更新', '分类', '书单'],
            animate: widget.library.motion,
            builder: (section) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (section == '精选') ...[
                  if (daily.isNotEmpty)
                    _dailyHero(
                      daily.first,
                      day,
                      companions: daily.skip(1).take(3).toList(),
                    ),
                  const SizedBox(height: 28),
                  _sectionTitle(
                    '每日精选',
                    '${daily.length} 部故事，换一组新灵感',
                    () => openCollection('每日精选', daily),
                    actionLabel: '查看全部',
                  ),
                  preview(daily.skip(1).toList()),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () async {
                        await widget.library.setOption(
                          'dailyEdition',
                          widget.library.option<int>('dailyEdition', 0) + 1,
                        );
                        if (mounted) setState(() {});
                      },
                      icon: const Icon(Icons.refresh, size: 15),
                      label: const LocalizedText('换一组'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _sectionTitle(
                    '大家都在读',
                    '从人气榜开始，找到下一本',
                    () => selectTab('排行'),
                    actionLabel: '看榜单',
                  ),
                  for (final entry
                      in (snapshot.ranks['人气'] ??
                              snapshot.ranks.values.firstOrNull ??
                              <Comic>[])
                          .take(3)
                          .indexed)
                    _rankRow(entry.$2, entry.$1 + 1),
                  const SizedBox(height: 24),
                  _sectionTitle(
                    '你可能还喜欢',
                    widget.library.favorites.isEmpty &&
                            widget.library.history.isEmpty
                        ? '从更多故事里，找到你的偏爱'
                        : '沿着你喜欢的题材，继续发现',
                    () => openCollection('你可能还喜欢', personal),
                    actionLabel: '查看全部',
                  ),
                  preview(personal),
                  const SizedBox(height: 24),
                  if (editorial.isNotEmpty) ...[
                    _sectionTitle(
                      editorial.first.key,
                      '编辑栏目 · 再多看一些',
                      () => openCollection(
                        editorial.first.key,
                        editorial.first.value,
                        path: snapshot.sectionPaths[editorial.first.key],
                      ),
                      actionLabel: '查看全部',
                    ),
                    preview(editorial.first.value),
                    const SizedBox(height: 24),
                  ],
                  _browseLink(snapshot.books),
                ],
                if (section == '排行') ...[
                  _sectionTitle(
                    '故事的人气榜',
                    '源站首页榜单 · ${ranks.length} 部',
                    snapshot.rankPaths[activeRank] == null
                        ? null
                        : () => openCollection(
                            '$activeRank榜',
                            ranks,
                            path: snapshot.rankPaths[activeRank],
                          ),
                    actionLabel: '完整榜单',
                  ),
                  Wrap(
                    spacing: 8,
                    children: snapshot.ranks.keys
                        .map(
                          (r) => ChoiceChip(
                            label: LocalizedText(r),
                            selected: r == activeRank,
                            onSelected: (_) => setState(() => rank = r),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 18),
                  RetainedSections(
                    index: activeRank,
                    order: snapshot.ranks.keys.toList(),
                    animate: widget.library.motion,
                    builder: (category) {
                      final items = snapshot.ranks[category] ?? [];
                      return Column(
                        children: [
                          for (final entry in items.indexed)
                            _rankRow(entry.$2, entry.$1 + 1),
                          if (items.isEmpty)
                            const EmptyState(
                              icon: Icons.leaderboard_outlined,
                              title: '这个来源暂未提供榜单',
                              message: '可以先去分类找找喜欢的漫画。',
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  _browseLink(snapshot.books),
                ],
                if (section == '更新') ...[
                  _sectionTitle(
                    '收藏追更',
                    checking ? '正在检查收藏…' : '检查收藏是否出现新章节',
                    checking || widget.library.favorites.isEmpty
                        ? null
                        : () => checkUpdates(),
                    actionLabel: '检查更新',
                  ),
                  for (final book in widget.library.favorites.where(
                    (b) => widget.library.updates[b.path]?['changed'] == true,
                  ))
                    BookLink(
                      comic: book,
                      web: widget.web,
                      onOpen: widget.onOpen,
                      builder: (cover, open) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: SizedBox(
                          width: 38,
                          height: 54,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: cover,
                          ),
                        ),
                        title: Text(book.title),
                        subtitle: LocalizedText(
                          '新章 · ${widget.library.updates[book.path]!['latest']}',
                        ),
                        trailing: const Icon(Icons.bookmark_added_outlined),
                        onTap: open,
                      ),
                    ),
                  if (widget.library.favorites.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 28),
                      child: LocalizedText(
                        '收藏喜欢的漫画后，在这里检查新章节。',
                        style: small(context),
                      ),
                    ),
                  _sectionTitle(
                    '追更精选',
                    '来自源站的「万人追更」栏目',
                    () => openCollection(
                      '追更精选',
                      updated,
                      path: snapshot.sectionPaths['万人追更'],
                    ),
                    actionLabel: '查看全部',
                  ),
                  ComicGrid(
                    books: updated,
                    web: widget.web,
                    onOpen: widget.onOpen,
                  ),
                ],
                if (section == '分类')
                  if (widget.library.option<String>('source', 'dm5') == 'dm5')
                    SourceBrowser(
                      source: widget.source,
                      library: widget.library,
                      web: widget.web,
                      onOpen: widget.onOpen,
                    )
                  else
                    ComicGrid(
                      books: snapshot.books,
                      web: widget.web,
                      onOpen: widget.onOpen,
                    ),
                if (section == '书单') ...[
                  for (final group in widget.library.groups.where(
                    (g) => g != '全部',
                  )) ...[
                    _sectionTitle(
                      group,
                      '我的主题书单',
                      () => openCollection(
                        group,
                        widget.library.favorites
                            .where(
                              (b) => widget.library.meta(b)['group'] == group,
                            )
                            .toList(),
                      ),
                      actionLabel: '查看全部',
                    ),
                    preview(
                      widget.library.favorites
                          .where(
                            (b) => widget.library.meta(b)['group'] == group,
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 24),
                  ],
                  for (final entry in editorial) ...[
                    _sectionTitle(
                      entry.key,
                      '${entry.value.length} 部 · 源站栏目',
                      () => openCollection(
                        entry.key,
                        entry.value,
                        path: snapshot.sectionPaths[entry.key],
                      ),
                      actionLabel: '查看全部',
                    ),
                    preview(entry.value),
                    const SizedBox(height: 24),
                  ],
                  if (editorial.isEmpty)
                    const EmptyState(
                      icon: Icons.collections_bookmark_outlined,
                      title: '还没有书单',
                      message: '在书库整理收藏，创建自己的主题书单。',
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionTitle(
    String title,
    String subtitle,
    VoidCallback? more, {
    String actionLabel = '查看全部',
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LocalizedText(title, style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 7),
              LocalizedText(subtitle, style: small(context)),
            ],
          ),
        ),
        if (more != null)
          TextButton(
            key: ValueKey('collection-$title'),
            onPressed: more,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                LocalizedText(
                  actionLabel,
                  style: const TextStyle(fontSize: 11),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_forward, size: 14),
              ],
            ),
          ),
      ],
    ),
  );
  Widget _browseLink(List<Comic> books) => InkWell(
    onTap: () => selectTab('分类'),
    borderRadius: BorderRadius.circular(12),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.explore_outlined, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LocalizedText('还想看更多？', style: TextStyle(fontSize: 18)),
                const SizedBox(height: 6),
                LocalizedText('按题材探索，继续加载更多漫画', style: small(context)),
                TextButton(
                  onPressed: () => openCollection('漫画目录', books),
                  child: LocalizedText(
                    '浏览当前目录 · ${books.length} 部',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward, size: 18),
        ],
      ),
    ),
  );

  Widget _dailyHero(
    Comic comic,
    String day, {
    List<Comic> companions = const [],
  }) => LayoutBuilder(
    builder: (context, box) {
      final wide = box.maxWidth >= 650;
      return BookLink(
        comic: comic,
        web: widget.web,
        onOpen: widget.onOpen,
        builder: (cover, open) => MilkGlass(
          radius: 18,
          high: widget.library.option<String>('quality', 'high') == 'high',
          tintOpacity: .52,
          padding: EdgeInsets.symmetric(
            horizontal: wide ? 30 : 18,
            vertical: 18,
          ),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: open,
                  child: Row(
                    children: [
                      SizedBox(
                        width: wide ? 120 : 88,
                        height: wide ? 178 : 132,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: cover,
                        ),
                      ),
                      SizedBox(width: wide ? 24 : 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: LocalizedText(
                                    '今日主推',
                                    style: TextStyle(
                                      fontSize: 11,
                                      letterSpacing: 2,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                  ),
                                ),
                                LocalizedText(
                                  day.replaceAll(' ', ''),
                                  style: small(context),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              comic.title,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: wide ? 24 : 19,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 10),
                            LocalizedText(
                              comic.latest.isEmpty
                                  ? '给自己一段读漫画的时间。'
                                  : comic.latest,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: small(context),
                            ),
                            const SizedBox(height: 18),
                            LocalizedText(
                              '翻开故事  ↗',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (wide && companions.isNotEmpty) ...[
                const SizedBox(width: 28),
                SizedBox(
                  width: box.maxWidth * .30,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LocalizedText('也可以从这些开始', style: small(context)),
                      const SizedBox(height: 18),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final companion in companions)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: BookLink(
                                  comic: companion,
                                  web: widget.web,
                                  onOpen: widget.onOpen,
                                  builder: (cover, open) => InkWell(
                                    onTap: open,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        AspectRatio(
                                          aspectRatio: .70,
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            child: cover,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          companion.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: small(context),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
  Widget _rankRow(Comic comic, int place) => BookLink(
    comic: comic,
    web: widget.web,
    onOpen: widget.onOpen,
    builder: (cover, open) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: open,
        child: Row(
          children: [
            SizedBox(
              width: 45,
              child: LocalizedText(
                place.toString().padLeft(2, '0'),
                style: TextStyle(
                  fontSize: 28,
                  color: place <= 3
                      ? Theme.of(context).colorScheme.primary
                      : quiet(context),
                ),
              ),
            ),
            SizedBox(
              width: 60,
              height: 80,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: cover,
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Text(comic.title, style: const TextStyle(fontSize: 14)),
            ),
            const Icon(Icons.north_east, size: 18),
          ],
        ),
      ),
    ),
  );
  Future<void> checkUpdates() async {
    if (checking) return;
    setState(() => checking = true);
    var failed = 0;
    final list = widget.library.favorites
        .where((c) => c.sourceId != 'local')
        .toList();
    for (var i = 0; i < list.length; i += 3) {
      if (!mounted) break;
      await Future.wait(
        list.skip(i).take(3).map((book) async {
          try {
            final detail = await widget.source.detail(book);
            final prior = widget.library.updates[book.path];
            final latest = detail.comic.latest.isNotEmpty
                ? detail.comic.latest
                : detail.chapters.firstOrNull?.title ?? '';
            final fingerprint = detail.chapters.firstOrNull?.path ?? latest;
            final changed =
                prior != null &&
                (prior['fingerprint'] ?? prior['latest']) != fingerprint;
            final now = DateTime.now().millisecondsSinceEpoch;
            widget.library.updates[book.path] = {
              'latest': latest,
              'fingerprint': fingerprint,
              'changed': prior?['changed'] == true || changed,
              'checkedAt': now,
              'updatedAt': changed ? now : prior?['updatedAt'] ?? 0,
            };
          } catch (_) {
            failed++;
          }
        }),
      );
    }
    await widget.library.persistFeatures();
    if (mounted) {
      setState(() => checking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText(
            failed > 0 ? '检查完成，$failed 部漫画暂时无法连接' : '追更检查完成',
          ),
        ),
      );
    }
  }
}
