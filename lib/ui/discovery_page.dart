import 'room_design.dart';
import 'materials.dart';
import 'visible_listenable_builder.dart';
import 'localized_text.dart';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/comic.dart';
import '../data/discovery.dart';
import '../data/discovery_explore.dart';
import '../data/dm5_source.dart';
import '../data/library.dart';
import '../data/follow_updates.dart';
import '../data/discovery_preferences.dart';
import 'discovery_preferences_page.dart';
import '../data/source_hub.dart';
import 'app_shell.dart' show ComicGrid, EmptyState, friendlyError, quiet, small;
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
    this.navigationRequest,
    this.onReadUpdate,
    this.scrollable = false,
  });
  final Library library;
  final Dm5Source source;
  final bool web, scrollable;
  final ValueChanged<Comic> onOpen;
  final Future<void> Function(Comic)? onReadUpdate;
  final ValueNotifier<String?>? navigationRequest;
  @override
  State<DiscoveryPage> createState() => _DiscoveryPageState();
}

class _DiscoveryPageState extends State<DiscoveryPage>
    with SingleTickerProviderStateMixin {
  Discovery? shown, pending;
  bool refreshing = false, applying = false;
  bool hasBrowsed = false, catalogVisited = false;
  ScrollPosition? ancestorScroll;
  final viewportScroll = ScrollController(keepScrollOffset: false);
  final sectionOffsets = <String, double>{};
  int sectionRequest = 0;
  ModalRoute<dynamic>? popupRoute;
  void noteBrowse() {
    if ((widget.scrollable && viewportScroll.hasClients
            ? viewportScroll.offset
            : ancestorScroll?.pixels ?? 0) >
        12) {
      hasBrowsed = true;
    }
  }

  final headingKey = GlobalKey();
  late final reveal = AnimationController(
    vsync: this,
    duration: RoomMotion.feedback,
    value: 1,
  );

  String tab = '逛一逛';
  String? topic;
  final tabsKey = GlobalKey();
  void selectTab(String value) {
    final next = value == '更新' ? '收藏更新' : value;
    if (next == tab) return;
    if (widget.scrollable && viewportScroll.hasClients) {
      sectionOffsets[tab] = viewportScroll.offset;
    }
    final generation = ++sectionRequest;
    setState(() {
      tab = next;
      if (tab == '全部漫画') catalogVisited = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != sectionRequest) return;
      final saved = sectionOffsets[next];
      if (widget.scrollable && saved != null && viewportScroll.hasClients) {
        viewportScroll.jumpTo(
          saved.clamp(0, viewportScroll.position.maxScrollExtent),
        );
        return;
      }
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
  String? openingUpdate;
  int openingRequest = 0;
  Future<void> readUpdate(Comic comic) async {
    final action = widget.onReadUpdate;
    if (action == null ||
        widget.library.updates[comic.path]?['changed'] != true) {
      widget.onOpen(comic);
      return;
    }
    if (openingUpdate != null) return;
    final request = ++openingRequest;
    setState(() => openingUpdate = comic.path);
    try {
      await action(comic);
    } finally {
      if (mounted && request == openingRequest) {
        setState(() => openingUpdate = null);
      }
    }
  }

  String updateFilter = '未读更新';
  Iterable<Comic> get followBooks => widget.library.favorites.where((book) {
    if (book.sourceId == 'local') return false;
    final update = widget.library.updates[book.path];
    if (updateFilter == '全部收藏') return true;
    if (updateFilter == '检查失败') return update?['checkError'] != null;
    return update?['changed'] == true;
  });
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
          horizontal: true,
          discoveryActions: true,
          books: books.take(6).toList(),
          library: widget.library,
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
    viewportScroll.addListener(noteBrowse);
    widget.navigationRequest?.addListener(receiveNavigation);
    receiveNavigation();
    initialize();
  }

  void receiveNavigation() {
    final request = widget.navigationRequest?.value;
    if (request == null) return;
    widget.navigationRequest!.value = null;
    selectTab(request);
  }

  @override
  void didUpdateWidget(covariant DiscoveryPage old) {
    super.didUpdateWidget(old);
    if (old.navigationRequest != widget.navigationRequest) {
      old.navigationRequest?.removeListener(receiveNavigation);
      widget.navigationRequest?.addListener(receiveNavigation);
      receiveNavigation();
    }
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
            (!hasBrowsed && tab == '逛一逛') ||
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
    final scroll = Scrollable.maybeOf(context)?.position;
    if (!identical(scroll, ancestorScroll)) {
      ancestorScroll?.removeListener(noteBrowse);
      ancestorScroll = scroll;
      ancestorScroll?.addListener(noteBrowse);
    }
    if (!TickerMode.valuesOf(context).enabled) {
      openingRequest++;
      openingUpdate = null;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      reveal.value = applying ? 0 : 1;
    }
  }

  @override
  void dispose() {
    viewportScroll.dispose();
    ancestorScroll?.removeListener(noteBrowse);
    widget.navigationRequest?.removeListener(receiveNavigation);
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
  Widget build(BuildContext context) => VisibleListenableBuilder(
    listenable: widget.library,
    builder: (context, _) =>
        ContentHandoff(fill: widget.scrollable, child: buildContent(context)),
  );

  Widget layout(List<Widget> header, Widget section, Widget catalog) {
    if (!widget.scrollable) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [...header, section],
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        final inset = box.maxWidth > 1172
            ? (box.maxWidth - 1100) / 2
            : box.maxWidth < 600
            ? 20.0
            : 36.0;
        return CustomScrollView(
          controller: viewportScroll,
          key: const PageStorageKey('discovery-scroll'),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                inset,
                12,
                inset,
                112 + MediaQuery.viewPaddingOf(context).bottom,
              ),
              sliver: SliverMainAxisGroup(
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: header,
                    ),
                  ),
                  SliverOffstage(
                    offstage: tab == '全部漫画',
                    sliver: SliverToBoxAdapter(
                      child: TickerMode(enabled: tab != '全部漫画', child: section),
                    ),
                  ),
                  if (catalogVisited || tab == '全部漫画')
                    SliverOffstage(
                      offstage: tab != '全部漫画',
                      sliver: TickerMode(
                        enabled: tab == '全部漫画',
                        child: catalog,
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget buildContent(BuildContext context) {
    final loaded = shown;
    if (loaded == null) {
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
        children: [
          heading('发现', '正在寻找下一段故事'),
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Container(
                height: 140,
                decoration: BoxDecoration(
                  color: quiet(context).withValues(alpha: .06),
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
        ],
      );
    }
    final snapshot = Discovery(
      books: widget.library.discoveryBooks(loaded.books),
      sections: loaded.sections.map(
        (k, v) => MapEntry(k, widget.library.discoveryBooks(v)),
      ),
      ranks: loaded.ranks.map(
        (k, v) => MapEntry(k, widget.library.discoveryBooks(v)),
      ),
      capturedAt: loaded.capturedAt,
      cached: loaded.cached,
      sectionPaths: loaded.sectionPaths,
      rankPaths: loaded.rankPaths,
    );
    final explore = DiscoveryExplore(snapshot);
    final topics = explore.availableTopics;
    final selectedTopic = topics.contains(topic) ? topic : null;
    final pool = explore.filter(explore.all, selectedTopic);
    final liked = [
      ...widget.library.favorites,
      ...widget.library.history.map((r) => r.comic),
    ];
    final day = DateTime.now().toUtc().add(const Duration(hours: 8));
    final expanded = Discovery(
      books: pool,
      sections: snapshot.sections,
      ranks: snapshot.ranks,
      capturedAt: snapshot.capturedAt,
    );
    final canPersonalize = liked.any(
      (book) =>
          book.tags.isNotEmpty ||
          snapshot.sections.values.any(
            (books) => books.any(
              (b) => b.path == book.path && b.sourceId == book.sourceId,
            ),
          ),
    );
    final picks = !canPersonalize
        ? dailyPicks(expanded, day)
        : expanded.forYou(liked, count: pool.length);
    final rankName = snapshot.ranks.containsKey('人气')
        ? '人气'
        : snapshot.ranks.keys.firstOrNull;
    final niche = explore.outsideCharts;
    final outside = explore.filter(
      niche.values.expand((e) => e),
      selectedTopic,
    );
    final nicheBooks = outside
        .where(
          (b) =>
              !liked.any((c) => c.path == b.path && c.sourceId == b.sourceId),
        )
        .toList();
    final displayed = picks
        .take(6)
        .map((b) => '${b.sourceId}/${b.path}')
        .toSet();
    final nichePreview = nicheBooks
        .where((b) => !displayed.contains('${b.sourceId}/${b.path}'))
        .take(3)
        .toList();
    displayed.addAll(nichePreview.map((b) => '${b.sourceId}/${b.path}'));
    final fresh = explore.filter(
      snapshot.sections['万人追更'] ?? snapshot.books,
      selectedTopic,
    );
    final freshPreview = fresh
        .where((b) => !displayed.contains('${b.sourceId}/${b.path}'))
        .toList();
    return FadeTransition(
      key: const ValueKey('discovery-ready'),
      opacity: reveal,
      child: layout(
        [
          KeyedSubtree(
            key: headingKey,
            child: RoomPageHeading(
              title: '发现',
              actions: [
                PopupMenuButton<String>(
                  key: const ValueKey('discovery-options'),
                  popUpAnimationStyle: RoomMotion.sheet(context),
                  tooltip: translate('发现选项', Localizations.localeOf(context)),
                  icon: const Icon(Icons.more_horiz, size: 21),
                  onSelected: (value) async {
                    await popupRoute?.completed;
                    if (!mounted || !context.mounted) return;
                    if (value == 'preferences') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              DiscoveryPreferencesPage(library: widget.library),
                        ),
                      );
                    }
                    if (value == 'refresh') {
                      if (pending != null) {
                        applyPending();
                      } else {
                        refresh();
                      }
                    }
                    if (value == 'rank' && rankName != null) {
                      showRankings(snapshot);
                    }
                    if (value == 'lists') showBooklists(snapshot);
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'preferences',
                      child: Builder(
                        builder: (c) {
                          popupRoute = ModalRoute.of(c);
                          return const LocalizedText('发现偏好');
                        },
                      ),
                    ),
                    PopupMenuItem(
                      value: 'refresh',
                      child: LocalizedText(pending != null ? '查看新内容' : '刷新发现页'),
                    ),
                    PopupMenuItem(
                      value: 'rank',
                      enabled: rankName != null,
                      child: const LocalizedText('完整榜单'),
                    ),
                    const PopupMenuItem(
                      value: 'lists',
                      child: LocalizedText('主题书单'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          InkWell(
            key: const ValueKey('open-comic-search'),
            borderRadius: BorderRadius.circular(18),
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
            child: MilkGlass(
              role: GlassRole.control,
              radius: 26,
              high: widget.library.option<String>('quality', 'high') == 'high',
              padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 14),
              child: Row(
                children: [
                  Icon(Icons.search, size: 20, color: quiet(context)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: LocalizedText(
                      '搜索漫画、作者或关键词',
                      style: TextStyle(fontSize: 13, color: quiet(context)),
                    ),
                  ),
                  Icon(Icons.arrow_forward, size: 16, color: quiet(context)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            key: tabsKey,
            scrollDirection: Axis.horizontal,
            child: RoomTabs<String>(
              value: tab,
              labels: const {'逛一逛': '逛一逛', '全部漫画': '全部漫画', '收藏更新': '收藏更新'},
              onChanged: selectTab,
            ),
          ),
          if (error != null || pending != null || snapshot.cached)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: LocalizedText(
                      pending != null
                          ? '发现页有新内容，当前列表已保留'
                          : error != null
                          ? '刷新失败，已保留当前目录'
                          : '正在浏览离线目录',
                      style: small(context),
                    ),
                  ),
                  if (pending != null)
                    TextButton(
                      onPressed: applying ? null : applyPending,
                      child: const LocalizedText('查看新内容'),
                    ),
                  if (error != null)
                    TextButton(
                      onPressed: refreshing ? null : refresh,
                      child: const LocalizedText('重试'),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 22),
        ],
        RetainedSections(
          index: tab,
          order: const ['逛一逛', '全部漫画', '收藏更新'],
          animate: widget.library.motion,
          builder: (section) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (section == '逛一逛') ...[
                if (topics.isNotEmpty) ...[
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ChoiceChip(
                          label: const LocalizedText('全部题材'),
                          selected: selectedTopic == null,
                          onSelected: (_) => setState(() => topic = null),
                        ),
                        for (final tag in topics.take(6))
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: ChoiceChip(
                              label: Text(tag),
                              selected: selectedTopic == tag,
                              onSelected: (_) => setState(() => topic = tag),
                            ),
                          ),
                        if (topics.length > 6)
                          IconButton(
                            tooltip: translate(
                              '更多题材',
                              Localizations.localeOf(context),
                            ),
                            onPressed: () => chooseTopic(topics),
                            icon: const Icon(Icons.more_horiz),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                _sectionTitle(
                  !canPersonalize ? '今天想看什么' : '为你挑选',
                  !canPersonalize ? '从这里开始，遇见下一本' : '参考你的收藏与阅读记录',
                  () => openCollection('为你挑选', picks),
                ),
                preview(picks),
                if (!canPersonalize)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => widget.library.setOption(
                        'dailyEdition',
                        widget.library.option<int>('dailyEdition', 0) + 1,
                      ),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const LocalizedText('换一组'),
                    ),
                  ),
                if (nichePreview.isNotEmpty) ...[
                  const SizedBox(height: 26),
                  _sectionTitle(
                    '小众精选',
                    '来自书源推荐栏目 · 当前榜单之外',
                    () => openCollection('小众精选', nicheBooks),
                  ),
                  for (final book in nichePreview)
                    nicheRow(
                      book,
                      niche.entries
                          .firstWhere(
                            (e) => e.value.any(
                              (b) =>
                                  b.path == book.path &&
                                  b.sourceId == book.sourceId,
                            ),
                          )
                          .key,
                    ),
                ],
                if (freshPreview.isNotEmpty) ...[
                  const SizedBox(height: 26),
                  _sectionTitle(
                    '最近值得看看',
                    '从书源更新与当前目录继续发现',
                    () => openCollection(
                      '最近值得看看',
                      fresh,
                      path: selectedTopic == null
                          ? snapshot.sectionPaths['万人追更']
                          : null,
                    ),
                  ),
                  preview(freshPreview),
                ],
                const SizedBox(height: 18),
                TextButton.icon(
                  onPressed: () => selectTab('全部漫画'),
                  icon: const Icon(Icons.explore_outlined, size: 18),
                  label: LocalizedText(
                    '继续探索 · {count} 部',
                    arguments: {'count': explore.all.length},
                  ),
                ),
              ],
              if (section == '全部漫画' && !widget.scrollable)
                if (widget.library.option<String>('source', 'dm5') == 'dm5')
                  SourceBrowser(
                    source: widget.source,
                    library: widget.library,
                    web: widget.web,
                    onOpen: widget.onOpen,
                  )
                else
                  ComicGrid(
                    discoveryActions: true,
                    books: explore.all,
                    library: widget.library,
                    web: widget.web,
                    onOpen: widget.onOpen,
                  ),
              if (section == '收藏更新') ...[
                _sectionTitle(
                  '收藏追更',
                  checking ? '正在检查收藏…' : '检查收藏是否出现新章节',
                  checking || widget.library.favorites.isEmpty
                      ? null
                      : () => checkUpdates(),
                  actionLabel: '检查更新',
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final filter in [
                      '未读更新',
                      '全部收藏',
                      if (widget.library.updates.values.any(
                        (u) => u['checkError'] != null,
                      ))
                        '检查失败',
                    ])
                      ChoiceChip(
                        label: LocalizedText(filter),
                        selected: updateFilter == filter,
                        onSelected: (_) =>
                            setState(() => updateFilter = filter),
                      ),
                    if (widget.library.updates.values.any(
                      (u) => u['changed'] == true,
                    ))
                      TextButton(
                        onPressed: () => widget.library.markUpdatesRead(
                          widget.library.favorites.map((b) => b.path),
                        ),
                        child: const LocalizedText('全部标为已读'),
                      ),
                    if (widget.library.updates.values.any(
                      (u) => u['checkError'] != null,
                    ))
                      TextButton(
                        onPressed: checking
                            ? null
                            : () => checkUpdates(failedOnly: true),
                        child: const LocalizedText('重试检查失败'),
                      ),
                  ],
                ),
                if (followBooks.isEmpty && widget.library.favorites.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: LocalizedText('当前分组没有作品'),
                  ),
                for (final book in followBooks)
                  BookLink(
                    comic: book,
                    web: widget.web,
                    onOpen: readUpdate,
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
                        widget.library.updates[book.path]?['checkError']
                                as String? ??
                            widget.library.updates[book.path]?['latest']
                                as String? ??
                            '尚未检查更新',
                      ),
                      trailing: openingUpdate == book.path
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : IconButton(
                              tooltip: translate(
                                '标为已读',
                                Localizations.localeOf(context),
                              ),
                              onPressed: () =>
                                  widget.library.markUpdatesRead([book.path]),
                              icon: Icon(
                                widget.library.updates[book.path]?['changed'] ==
                                        true
                                    ? Icons.bookmark_added_outlined
                                    : Icons.done,
                              ),
                            ),
                      onTap: open,
                      onLongPress: () =>
                          showDiscoveryInterest(context, widget.library, book),
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
              ],
            ],
          ),
        ),
        (widget.library.option<String>('source', 'dm5') == 'dm5' ||
                widget.source is SourceHub &&
                    (widget.source as SourceHub).selected?.json['pagination'] ==
                        true)
            ? SourceBrowser(
                source: widget.source,
                library: widget.library,
                web: widget.web,
                onOpen: widget.onOpen,
                sliver: true,
              )
            : ComicGrid(
                discoveryActions: true,
                books: explore.all,
                library: widget.library,
                web: widget.web,
                onOpen: widget.onOpen,
                sliver: true,
              ),
      ),
    );
  }

  void showRankings(Discovery snapshot) {
    if (snapshot.ranks.length == 1) {
      final entry = snapshot.ranks.entries.single;
      openCollection(
        entry.key,
        entry.value,
        path: snapshot.rankPaths[entry.key],
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const LocalizedText('完整榜单')),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              for (final entry in snapshot.ranks.entries)
                ListTile(
                  title: Text(entry.key),
                  subtitle: LocalizedText(
                    '{count} 部漫画',
                    arguments: {'count': entry.value.length},
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openCollection(
                    entry.key,
                    entry.value,
                    path: snapshot.rankPaths[entry.key],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void showBooklists(Discovery snapshot) {
    final editorials = snapshot.sections.entries
        .where((e) => !e.key.contains('VIP'))
        .toList();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const LocalizedText('主题书单')),
          body: VisibleListenableBuilder(
            listenable: widget.library,
            builder: (c, _) => ListView(
              padding: const EdgeInsets.all(20),
              children: [
                for (final group in widget.library.groups.where(
                  (g) => g != '全部',
                ))
                  ListTile(
                    title: Text(group),
                    subtitle: const LocalizedText('我的主题书单'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => openCollection(
                      group,
                      widget.library.favorites
                          .where(
                            (b) => widget.library.meta(b)['group'] == group,
                          )
                          .toList(),
                    ),
                  ),
                for (final entry in editorials)
                  ListTile(
                    title: Text(entry.key),
                    subtitle: LocalizedText(
                      '{count} 部漫画',
                      arguments: {'count': entry.value.length},
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => openCollection(
                      entry.key,
                      entry.value,
                      path: snapshot.sectionPaths[entry.key],
                    ),
                  ),
                if (editorials.isEmpty && widget.library.groups.length <= 1)
                  const EmptyState(
                    icon: Icons.collections_bookmark_outlined,
                    title: '还没有书单',
                    message: '在书库整理收藏，创建自己的主题书单。',
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> chooseTopic(List<String> topics) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      sheetAnimationStyle: RoomMotion.sheet(context),
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in topics)
                ActionChip(
                  label: Text(tag),
                  onPressed: () => Navigator.pop(c, tag),
                ),
            ],
          ),
        ),
      ),
    );
    if (mounted && result != null) setState(() => topic = result);
  }

  Widget nicheRow(Comic book, String origin) => BookLink(
    comic: book,
    web: widget.web,
    onOpen: widget.onOpen,
    builder: (cover, open) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        onTap: open,
        onLongPress: () => showDiscoveryInterest(context, widget.library, book),
        borderRadius: BorderRadius.circular(14),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(width: 62, height: 84, child: cover),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    book.tags.isNotEmpty
                        ? book.tags.take(2).join(' · ')
                        : origin,
                    style: small(context),
                  ),
                  const SizedBox(height: 4),
                  LocalizedText('当前榜单之外，换个口味', style: small(context)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    ),
  );

  Widget _sectionTitle(
    String title,
    String subtitle,
    VoidCallback? more, {
    String actionLabel = '查看全部',
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LocalizedText(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              LocalizedText(subtitle, style: small(context)),
            ],
          ),
        ),
        if (more != null)
          TextButton(
            key: ValueKey('collection-$title'),
            onPressed: more,
            child: LocalizedText(
              actionLabel,
              style: const TextStyle(fontSize: 11),
            ),
          ),
      ],
    ),
  );
  Future<void> checkUpdates({bool failedOnly = false}) async {
    if (checking) return;
    setState(() => checking = true);
    final failed = await FollowChecker.check(
      widget.library,
      widget.source,
      failedOnly: failedOnly,
      active: () => mounted,
    );
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
