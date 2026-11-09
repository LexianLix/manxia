import 'room_design.dart';
import 'companion.dart';
import 'browse_chrome.dart';
import 'character_settings_page.dart';
import 'visible_listenable_builder.dart';
import 'localized_text.dart';
import 'room_motion.dart';
import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import '../data/comic.dart';
import '../data/dm5_source.dart';
import '../data/source_hub.dart';
import 'settings_page.dart';
import 'search_page.dart';
import 'scroll_arrival.dart';
import 'history_page.dart';
import '../data/follow_updates.dart';
import '../data/library.dart';
import '../data/reading_progress.dart';
import 'reader_page.dart';
import 'living_shelf.dart';
import 'discovery_page.dart';
import 'discovery_preferences_page.dart';
import 'glass_navigation.dart';
import 'retained_pages.dart';
import 'offline_page.dart';
import 'library_manager.dart';
import 'plugins_page.dart';
import 'personalization_settings.dart';
import 'book_link.dart';
import 'book_navigation.dart';
import 'collection_target.dart';
import 'content_handoff.dart';
import 'package:package_info_plus/package_info_plus.dart';

const green = Color(0xff535964);
Color quiet(BuildContext c) =>
    Theme.of(c).colorScheme.onSurface.withValues(alpha: .65);
TextStyle small(BuildContext c) =>
    TextStyle(fontSize: 11, color: quiet(c), letterSpacing: .5);

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.library, required this.web});
  final Library library;
  final bool web;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  late int tab = widget.library.option<int>('startTab', 0).clamp(0, 5);
  final browseChrome = BrowseChrome();
  bool opening = false;
  bool openingLicenses = false;
  ModalRoute<dynamic>? shelfPopupRoute;
  Timer? followTimer;
  bool foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  bool get canCheckUpdates =>
      mounted && foreground && (ModalRoute.of(context)?.isCurrent ?? true);
  void queueUpdates() {
    followTimer?.cancel();
    if (!canCheckUpdates ||
        widget.library.favorites.every((b) => b.sourceId == 'local')) {
      return;
    }
    followTimer = Timer(const Duration(milliseconds: 700), () {
      if (!canCheckUpdates) return;
      unawaited(
        FollowChecker.check(
          widget.library,
          source,
          onlyDue: true,
          active: () => canCheckUpdates,
        ).catchError((Object _) => 0),
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    queueUpdates();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    queueUpdates();
  }

  Future<void> licenses() async {
    if (openingLicenses) return;
    openingLicenses = true;
    String? version;
    try {
      version = (await PackageInfo.fromPlatform().timeout(
        const Duration(seconds: 2),
      )).version;
    } catch (_) {
      // An unavailable metadata plugin must not prevent access to licenses.
    } finally {
      openingLicenses = false;
    }
    if (!mounted) return;
    showLicensePage(
      context: context,
      applicationName: '漫匣',
      applicationVersion: version,
    );
  }

  (String, Rect)? openingOrigin;
  final discoveryRequest = ValueNotifier<String?>(null);
  final atmosphere = ValueNotifier<Color>(const Color(0xffa9acb4));
  late final source = SourceHub(
    widget.library,
    gateway: widget.web ? Uri.base : null,
  );
  @override
  void dispose() {
    followTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    browseChrome.dispose();
    atmosphere.dispose();
    discoveryRequest.dispose();
    source.close();
    super.dispose();
  }

  void navigate(int i) {
    if (tab == i) return;
    updateRequest++;
    browseChrome.expand();
    setState(() {
      tab = i;
    });
  }

  void showUpdates() {
    discoveryRequest.value = '更新';
    navigate(1);
  }

  Future<void> companionActions() async {
    ModalRoute<dynamic>? sheetRoute;
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      sheetAnimationStyle: RoomMotion.sheet(context),
      builder: (c) {
        sheetRoute = ModalRoute.of(c);
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(c).height * .9,
          ),
          child: SingleChildScrollView(
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 16),
                  const CompanionPortrait(size: 88, expression: 'happy'),
                  for (final item in [
                    if (continueRecord != null)
                      ('continue', '继续阅读', Icons.menu_book_outlined),
                    ('discover', '去发现漫画', Icons.explore_outlined),
                    ('updates', '查看更新', Icons.notifications_none),
                    ('settings', '小夏与阅读伙伴', Icons.tune),
                  ])
                    ListTile(
                      leading: Icon(item.$3),
                      title: LocalizedText(item.$2),
                      onTap: () => Navigator.pop(c, item.$1),
                    ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        );
      },
    );
    // Wait for the sheet's reverse transition before opening another route.
    await sheetRoute?.completed;
    if (!mounted || action == null) return;
    switch (action) {
      case 'discover':
        navigate(1);
      case 'updates':
        showUpdates();
      case 'history':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              appBar: AppBar(),
              body: BrowseEdges(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: _history(),
                ),
              ),
            ),
          ),
        );
      case 'settings':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CharacterSettingsPage(library: widget.library),
          ),
        );
      case 'continue':
        final record = continueRecord;
        if (record != null) {
          await continueBook(record.comic);
        }
    }
  }

  Future<void> open(Comic c) async {
    final flightTag = BookLink.takeTag(context, c);
    if (opening) return;
    updateRequest++;
    opening = true;
    final origin = openingOrigin?.$1 == c.path ? openingOrigin?.$2 : null;
    openingOrigin = null;
    try {
      await Navigator.of(context).push(
        comicDetailRoute(
          context,
          comic: c,
          library: widget.library,
          source: source,
          web: widget.web,
          flightTag: flightTag,
          origin: origin,
        ),
      );
    } finally {
      opening = false;
    }
  }

  Future<void> continueBook(Comic comic) async {
    if (opening) return;
    updateRequest++;
    final record = widget.library.record(comic);
    if (record == null) return open(comic);
    opening = true;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ReaderPage(
            comic: comic,
            chapter: Chapter(record.chapterPath, record.chapterTitle),
            library: widget.library,
            source: source,
            web: widget.web,
          ),
        ),
      );
    } finally {
      opening = false;
    }
  }

  int updateRequest = 0;
  Future<void> readUpdates(Comic comic) async {
    if (opening) return;
    final request = ++updateRequest;
    try {
      final detail = await source.detail(comic);
      if (!mounted || tab != 1 || request != updateRequest || opening) return;
      final unread = widget.library.unreadFollowChapters(detail);
      if (unread.isEmpty) {
        await open(comic);
        return;
      }
      opening = true;
      try {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => ReaderPage(
              comic: detail.comic,
              chapter: unread.first,
              chapters: detail.chapters.reversed.toList(),
              initialPage: 0,
              library: widget.library,
              source: source,
              web: widget.web,
            ),
          ),
        );
      } finally {
        opening = false;
      }
    } catch (error) {
      if (mounted && tab == 1 && request == updateRequest && !opening) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: LocalizedText(friendlyError(error))));
        await open(comic);
      }
    }
  }

  @override
  Widget build(BuildContext context) => VisibleListenableBuilder(
    listenable: widget.library,
    builder: (context, _) => LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 1000;
        final compact = box.maxWidth < 600;
        final ids = navigationIds(widget.library);
        // Retain legacy/plugin start destinations without changing saved
        // navigation preferences. They leave the dock when the user switches.
        if (!ids.contains(tab)) ids.add(tab);
        return Scaffold(
          extendBody: true,
          body: Stack(
            children: [
              SafeArea(
                bottom: false,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1600),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (wide) _sidebar(),
                        Expanded(
                          child: Column(
                            children: [
                              if (wide)
                                Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    compact ? 18 : 36,
                                    compact ? 6 : 16,
                                    compact ? 18 : 44,
                                    0,
                                  ),
                                  child: _topbar(wide),
                                ),
                              Expanded(
                                child: NotificationListener<ScrollNotification>(
                                  onNotification: browseChrome.observe,
                                  child: RetainedPages(
                                    index: tab,
                                    order: wide
                                        ? roomDestinations
                                              .map((d) => d.id)
                                              .toList()
                                        : ids,
                                    onSelected: navigate,
                                    animate: widget.library.motion,
                                    builder: (page) => page == 5
                                        ? PluginsPage(library: widget.library)
                                        : page == 4
                                        ? OfflinePage(
                                            library: widget.library,
                                            source: source,
                                            web: widget.web,
                                          )
                                        : page == 3
                                        ? SettingsPage(
                                            library: widget.library,
                                            source: source,
                                            web: widget.web,
                                          )
                                        : page == 1
                                        ? BrowseEdges(
                                            child: DiscoveryPage(
                                              key: ValueKey(
                                                widget.library.option<String>(
                                                  'source',
                                                  'dm5',
                                                ),
                                              ),
                                              library: widget.library,
                                              source: source,
                                              web: widget.web,
                                              scrollable: true,
                                              navigationRequest:
                                                  discoveryRequest,
                                              onOpen: open,
                                              onReadUpdate: readUpdates,
                                            ),
                                          )
                                        : BrowseEdges(
                                            child: SingleChildScrollView(
                                              key: PageStorageKey(
                                                'reading-room-$page',
                                              ),
                                              padding: EdgeInsets.fromLTRB(
                                                compact ? 20 : 36,
                                                compact ? 12 : 24,
                                                compact ? 18 : 36,
                                                wide
                                                    ? 32
                                                    : 112 +
                                                          MediaQuery.viewPaddingOf(
                                                            context,
                                                          ).bottom,
                                              ),
                                              child: Center(
                                                child: ConstrainedBox(
                                                  constraints:
                                                      const BoxConstraints(
                                                        maxWidth: 1100,
                                                      ),
                                                  child: switch (page) {
                                                    0 => _shelf(compact),
                                                    2 => _history(),
                                                    _ =>
                                                      const SizedBox.shrink(),
                                                  },
                                                ),
                                              ),
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 380),
                    child: CompanionFeedback(
                      library: widget.library,
                      onShelf: () => navigate(0),
                      onUpdates: showUpdates,
                    ),
                  ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: wide
              ? null
              : BrowseNavigation(
                  chrome: browseChrome,
                  anchors: {0: shelfAnchor(widget.library)},
                  selectedIndex: math.max(0, ids.indexOf(tab)),
                  destinations: ids.map((id) => roomDestinations[id]).toList(),
                  onSelected: (index) => navigate(ids[index]),
                  liquid: widget.library.option<bool>('liquidNavigation', true),
                  highQuality:
                      widget.library.option<String>('quality', 'high') ==
                      'high',
                  haptics: widget.library.option<bool>('haptics', true),
                ),
        );
      },
    ),
  );
  Widget _brand() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 34,
        height: 38,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurface,
          borderRadius: BorderRadius.circular(2),
        ),
        child: Center(
          child: LocalizedText(
            '匣',
            style: TextStyle(
              color: Theme.of(context).colorScheme.surface,
              fontFamily: 'ArchiveSerif',
              fontSize: 23,
            ),
          ),
        ),
      ),
      const SizedBox(width: 11),
      const LocalizedText(
        '漫匣',
        style: TextStyle(
          fontSize: 25,
          fontFamily: 'ArchiveSerif',
          letterSpacing: 3,
        ),
      ),
    ],
  );
  Widget _sidebar() => Container(
    width: 215,
    decoration: BoxDecoration(
      border: Border(right: BorderSide(color: Theme.of(context).dividerColor)),
    ),
    padding: const EdgeInsets.fromLTRB(30, 38, 22, 26),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _brand(),
        const SizedBox(height: 10),
        LocalizedText(
          'M A N X I A  /  漫画阅读',
          style: small(context).copyWith(fontSize: 9),
        ),
        const SizedBox(height: 24),
        Expanded(
          child: ListView(
            children: [
              for (final item in roomDestinations)
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Material(
                    key: item.id == 0 ? shelfAnchor(widget.library) : null,
                    color: tab == item.id
                        ? green.withValues(alpha: .06)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => navigate(item.id),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 13,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              item.icon,
                              size: 19,
                              color: tab == item.id
                                  ? Theme.of(context).colorScheme.primary
                                  : quiet(context),
                            ),
                            const SizedBox(width: 13),
                            LocalizedText(
                              switch (item.id) {
                                0 => '我的书架',
                                1 => '发现漫画',
                                2 => '阅读足迹',
                                3 => '偏好设置',
                                4 => '下载书库',
                                _ => '插件商城',
                              },
                              style: TextStyle(
                                fontSize: 14,
                                color: tab == item.id
                                    ? Theme.of(context).colorScheme.primary
                                    : quiet(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Container(width: 25, height: 1, color: Theme.of(context).dividerColor),
        const SizedBox(height: 18),
        LocalizedText(
          '一册漫画，\n一段自己的时间。',
          style: TextStyle(fontSize: 12, height: 1.9, color: quiet(context)),
        ),
        const SizedBox(height: 22),
        LocalizedText(
          'MANXIA · YOUR READING ROOM',
          style: small(context).copyWith(fontSize: 8, letterSpacing: .4),
        ),
      ],
    ),
  );
  Widget _topbar(bool wide) => Row(
    children: [
      Expanded(
        child: LocalizedText(
          '私人阅读室',
          style: small(context),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      Semantics(
        label: '默认漫画源 ${source.selected?.name ?? '动漫屋'}',
        child: Container(
          constraints: const BoxConstraints(maxWidth: 100),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.public, size: 13, color: quiet(context)),
              const SizedBox(width: 6),
              Flexible(
                child: LocalizedText(
                  source.selected?.name ?? '动漫屋',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: quiet(context)),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(width: 8),
      IconButton(
        tooltip: translate('下载与本地书库', Localizations.localeOf(context)),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OfflinePage(
              library: widget.library,
              source: source,
              web: widget.web,
            ),
          ),
        ),
        icon: const Icon(Icons.download_outlined, size: 21),
      ),
      IconButton(
        tooltip: translate('搜索漫画', Localizations.localeOf(context)),
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ComicSearchPage(
                library: widget.library,
                source: source,
                web: widget.web,
                onOpen: open,
              ),
            ),
          );
        },
        icon: const Icon(Icons.search, size: 22),
      ),
    ],
  );
  Future<void> manageShelf([Comic? selected]) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => LibraryManager(
            library: widget.library,
            web: widget.web,
            onOpen: open,
            initialSelection: selected?.path,
          ),
        ),
      );

  Widget _shelf(bool compact) {
    final archived = widget.library.option<bool>('showArchived', false);
    final books = widget.library.books
        .where((b) => widget.library.archived(b) == archived)
        .toList();
    return Column(
      key: const ValueKey('shelf-home'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RoomPageHeading(
          title: archived ? '归档书架' : '书架',
          actions: [
            IconButton(
              tooltip: translate('搜索漫画', Localizations.localeOf(context)),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ComicSearchPage(
                    library: widget.library,
                    source: source,
                    web: widget.web,
                    onOpen: open,
                  ),
                ),
              ),
              icon: const Icon(Icons.search, size: 21),
            ),
            PopupMenuButton<String>(
              popUpAnimationStyle: RoomMotion.sheet(context),
              tooltip: translate('整理书架', Localizations.localeOf(context)),
              icon: const Icon(Icons.more_horiz, size: 21),
              onSelected: (value) async {
                await shelfPopupRoute?.completed;
                if (!mounted) return;
                switch (value) {
                  case 'manage':
                    manageShelf();
                  case 'grid':
                    widget.library.setting('grid', !widget.library.grid);
                  case 'archive':
                    widget.library.setOption('showArchived', !archived);
                  case 'updates':
                    showUpdates();
                  case 'history':
                    Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => Scaffold(
                          appBar: const RoomGlassBar(title: '阅读足迹'),
                          body: BrowseEdges(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(20),
                              child: _history(),
                            ),
                          ),
                        ),
                      ),
                    );
                  case 'companion':
                    companionActions();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'manage',
                  child: Builder(
                    builder: (c) {
                      shelfPopupRoute = ModalRoute.of(c);
                      return const LocalizedText('整理收藏');
                    },
                  ),
                ),
                PopupMenuItem(
                  value: 'grid',
                  child: LocalizedText(
                    widget.library.grid ? '切换立体书架' : '切换封面网格',
                  ),
                ),
                PopupMenuItem(
                  value: 'archive',
                  child: LocalizedText(archived ? '返回未归档收藏' : '查看已归档'),
                ),
                const PopupMenuItem(
                  value: 'updates',
                  child: LocalizedText('查看更新'),
                ),
                const PopupMenuItem(
                  value: 'history',
                  child: LocalizedText('阅读足迹'),
                ),
                if (CompanionScope.maybeOf(context)?.active == true)
                  const PopupMenuItem(
                    value: 'companion',
                    child: LocalizedText('小夏与阅读伙伴'),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        ContentHandoff(
          child: books.isEmpty
              ? Padding(
                  key: const ValueKey('empty-shelf'),
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: EmptyState(
                    icon: Icons.auto_stories_outlined,
                    title: archived
                        ? '归档书架暂时没有漫画'
                        : widget.library.favorites.isNotEmpty
                        ? '故事已收进归档书架'
                        : '书架，等你放上第一本漫画',
                    message: archived || widget.library.favorites.isNotEmpty
                        ? '在整理菜单切换书架，或恢复已归档收藏。'
                        : '搜索喜欢的漫画，加入收藏后在这里继续阅读。',
                    action: archived || widget.library.favorites.isNotEmpty
                        ? () => widget.library.setOption(
                            'showArchived',
                            !archived,
                          )
                        : () => navigate(1),
                    actionLabel: archived || widget.library.favorites.isNotEmpty
                        ? '切换书架'
                        : '发现漫画',
                  ),
                )
              : widget.library.grid
              ? ComicGrid(
                  key: const ValueKey('grid-shelf'),
                  books: books,
                  library: widget.library,
                  web: widget.web,
                  onOpen: open,
                  onManage: manageShelf,
                )
              : LivingShelf(
                  key: const ValueKey('living-shelf'),
                  books: books,
                  library: widget.library,
                  web: widget.web,
                  onOpen: open,
                  onContinue: continueBook,
                  onManage: manageShelf,
                  showCollectionAction: false,
                  onAmbientColor: (color) {
                    if (mounted) atmosphere.value = color;
                  },
                  onBookOrigin: (comic, rect) =>
                      openingOrigin = (comic.path, rect),
                ),
        ),
        if (books.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Row(
              children: [
                Expanded(
                  child: LocalizedText(
                    '{count} 册收藏 · 长按书本整理',
                    arguments: {'count': books.length},
                    style: small(context),
                  ),
                ),
                if (books.any(
                  (b) => widget.library.updates[b.path]?['changed'] == true,
                ))
                  TextButton(
                    onPressed: showUpdates,
                    child: LocalizedText(
                      '有更新 {count}',
                      arguments: {
                        'count': books
                            .where(
                              (b) =>
                                  widget.library.updates[b.path]?['changed'] ==
                                  true,
                            )
                            .length,
                      },
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  ReadingRecord? get continueRecord => widget.library.history
      .where(
        (r) =>
            !widget.library.archived(r.comic) &&
            widget.library.meta(r.comic)['status'] != '已读',
      )
      .firstOrNull;
  Widget _history() =>
      HistoryPage(library: widget.library, source: source, web: widget.web);
}

String friendlyError(Object? error) {
  if (error is SourceException) return error.message;
  return '网络连接暂时不可用，请检查网络后重试。';
}

class ComicGrid extends StatelessWidget {
  const ComicGrid({
    super.key,
    required this.books,
    required this.web,
    required this.onOpen,
    this.minItemWidth = 104,
    this.sliver = false,
    this.itemArrival,
    this.arrivingFrom = 0,
    this.library,
    this.discoveryActions = false,
    this.sourceLabels = const {},
    this.onManage,
    this.horizontal = false,
  });
  final Map<String, String> sourceLabels;
  final bool discoveryActions;
  final List<Comic> books;
  final Library? library;
  final bool web, sliver, horizontal;
  final double minItemWidth;
  final Animation<double>? itemArrival;
  final int arrivingFrom;
  final ValueChanged<Comic> onOpen;
  final ValueChanged<Comic>? onManage;
  SliverGridDelegateWithFixedCrossAxisCount delegate(double width) =>
      SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: math.max(2, (width / minItemWidth).floor()),
        mainAxisSpacing: 18,
        crossAxisSpacing: 12,
        childAspectRatio: .56,
      );
  @override
  Widget build(BuildContext context) => horizontal
      ? LayoutBuilder(
          builder: (context, box) {
            final width = (box.maxWidth * .41).clamp(124.0, 176.0);
            final labels =
                MediaQuery.textScalerOf(context).scale(13) * 2.8 + 25;
            return SizedBox(
              height: width * 1.4 + labels,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(bottom: 5),
                itemCount: books.length,
                separatorBuilder: (_, _) => const SizedBox(width: 16),
                itemBuilder: (context, i) =>
                    SizedBox(width: width, child: item(context, i)),
              ),
            );
          },
        )
      : sliver
      ? SliverLayoutBuilder(
          builder: (context, constraints) => SliverGrid(
            delegate: SliverChildBuilderDelegate(
              item,
              childCount: books.length,
            ),
            gridDelegate: delegate(constraints.crossAxisExtent),
          ),
        )
      : LayoutBuilder(
          builder: (context, box) => GridView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: books.length,
            gridDelegate: delegate(box.maxWidth),
            itemBuilder: item,
          ),
        );
  Widget item(BuildContext context, int i) {
    final comic = books[i];
    final child = BookLink(
      key: ValueKey('${comic.sourceId}/${comic.path}/$i'),
      comic: comic,
      web: web,
      onOpen: onOpen,
      builder: (cover, open) => InkWell(
        onTap: open,
        onLongPress: onManage != null
            ? () => onManage!(comic)
            : discoveryActions && library != null
            ? () => showDiscoveryInterest(context, library!, comic)
            : null,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .06),
                      blurRadius: 5,
                      offset: const Offset(1, 3),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(width: double.infinity, child: cover),
                ),
              ),
            ),
            const SizedBox(height: 8),
            LocalizedText(
              comic.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 5),
            LocalizedText(
              sourceLabels[comic.sourceId] ??
                  (library?.sourceStatus(comic)?['kind'] == 'copyright'
                      ? '当前源无版权'
                      : library?.sourceStatus(comic)?['kind'] == 'missing'
                      ? '入口已失效'
                      : library?.updates[comic.path]?['changed'] == true
                      ? '有更新 · {chapter}'
                      : library?.chapterCount(comic) != null
                      ? '{read} / {count} 章已读'
                      : comic.latest.isEmpty && comic.author.isNotEmpty
                      ? comic.author
                      : comic.latest.isEmpty
                      ? comic.sourceId == 'dm5'
                            ? '动漫屋'
                            : comic.sourceId == 'local'
                            ? '本地漫画'
                            : '漫画'
                      : comic.latest),
              arguments: {
                'read': library?.readChapterCount(comic) ?? 0,
                'count': library?.chapterCount(comic) ?? 0,
                'chapter':
                    library?.updates[comic.path]?['latest'] as String? ??
                    comic.latest,
              },
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: small(context),
            ),
          ],
        ),
      ),
    );
    final arrival = itemArrival;
    if (arrival == null) {
      return ScrollArrival(
        identity: '${comic.sourceId}/${comic.path}',
        child: child,
      );
    }
    return AnimatedBuilder(
      animation: arrival,
      child: child,
      builder: (context, child) {
        final t = i < arrivingFrom || MediaQuery.disableAnimationsOf(context)
            ? 1.0
            : Interval(
                ((i - arrivingFrom) % 4) * .055,
                1,
                curve: RoomMotion.ease,
              ).transform(arrival.value);
        return IgnorePointer(
          ignoring: t < .5,
          child: ExcludeSemantics(
            excluding: t < .5,
            child: Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, 10 * (1 - t)),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.actionLabel = '重试',
    this.expression = 'idle',
  });
  final IconData icon;
  final String title, message, actionLabel, expression;
  final VoidCallback? action;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        children: [
          if (CompanionScope.maybeOf(context)?.active == true)
            CompanionPortrait(
              expression: expression,
              size: CompanionScope.maybeOf(context)!.preferences.portraitSize,
            )
          else
            Icon(icon, size: 30, color: quiet(context)),
          const SizedBox(height: 16),
          LocalizedText(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: LocalizedText(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.8,
                color: quiet(context),
              ),
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: action,
              child: LocalizedText(actionLabel),
            ),
          ],
        ],
      ),
    ),
  );
}
