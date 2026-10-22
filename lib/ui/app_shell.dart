import 'localized_text.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import '../data/comic.dart';
import '../data/dm5_source.dart';
import '../data/source_hub.dart';
import 'advanced_settings.dart';
import 'history_page.dart';
import '../data/library.dart';
import 'book_object.dart';
import 'detail_page.dart';
import 'reader_page.dart';
import 'living_shelf.dart';
import 'discovery_page.dart';
import 'glass_navigation.dart';
import 'retained_pages.dart';
import 'offline_page.dart';
import 'library_manager.dart';
import 'room_motion.dart';

const green = Color(0xff47775e);
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

class _AppShellState extends State<AppShell> {
  int tab = 0;
  bool opening = false;
  (String, Rect)? openingOrigin;
  final atmosphere = ValueNotifier<Color>(const Color(0xff8baf99));
  late final source = SourceHub(
    widget.library,
    gateway: widget.web ? Uri.base : null,
  );
  @override
  void dispose() {
    atmosphere.dispose();
    source.close();
    super.dispose();
  }

  void navigate(int i) {
    if (tab == i) return;
    setState(() {
      tab = i;
    });
  }

  Future<void> open(Comic c) async {
    if (opening) return;
    opening = true;
    final origin = openingOrigin?.$1 == c.path ? openingOrigin?.$2 : null;
    openingOrigin = null;
    try {
      await Navigator.of(context).push(
        PageRouteBuilder(
          opaque: false,
          transitionDuration: Duration(
            milliseconds:
                widget.library.motion &&
                    !MediaQuery.disableAnimationsOf(context)
                ? RoomMotion.book.inMilliseconds
                : 0,
          ),
          reverseTransitionDuration: Duration(
            milliseconds:
                widget.library.motion &&
                    !MediaQuery.disableAnimationsOf(context)
                ? RoomMotion.bookReturn.inMilliseconds
                : 0,
          ),
          pageBuilder: (_, _, _) => DetailPage(
            comic: c,
            library: widget.library,
            source: source,
            web: widget.web,
            bookNumber: math.max(
              1,
              widget.library.books.indexWhere((b) => b.path == c.path) + 1,
            ),
          ),
          transitionsBuilder: (_, animation, _, child) => OpenBookTransition(
            animation: animation,
            comic: c,
            web: widget.web,
            origin: origin,
            child: child,
          ),
        ),
      );
    } finally {
      opening = false;
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.library,
    builder: (context, _) => LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 1000;
        final compact = box.maxWidth < 600;
        return Scaffold(
          extendBody: true,
          body: Stack(
            children: [
              Positioned.fill(
                child: ValueListenableBuilder<Color>(
                  valueListenable: atmosphere,
                  builder: (_, color, _) => ReadingAtmosphere(
                    color: color,
                    highQuality:
                        widget.library.option<String>('quality', 'high') ==
                        'high',
                  ),
                ),
              ),
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
                              Padding(
                                padding: EdgeInsets.fromLTRB(
                                  compact ? 22 : 44,
                                  compact ? 16 : 26,
                                  compact ? 18 : 44,
                                  0,
                                ),
                                child: _topbar(wide),
                              ),
                              Expanded(
                                child: RetainedPages(
                                  index: tab,
                                  animate: widget.library.motion,
                                  builder: (page) => page == 3
                                      ? CustomScrollView(
                                          key: const PageStorageKey(
                                            'reading-room-3',
                                          ),
                                          scrollCacheExtent:
                                              const ScrollCacheExtent.pixels(0),
                                          slivers: [
                                            SliverLayoutBuilder(
                                              builder: (context, constraints) =>
                                                  SliverPadding(
                                                    padding: EdgeInsets.fromLTRB(
                                                      math.max(
                                                        compact ? 22.0 : 44.0,
                                                        (constraints.crossAxisExtent -
                                                                1100) /
                                                            2,
                                                      ),
                                                      compact ? 28 : 34,
                                                      math.max(
                                                        compact ? 22.0 : 44.0,
                                                        (constraints.crossAxisExtent -
                                                                1100) /
                                                            2,
                                                      ),
                                                      140,
                                                    ),
                                                    sliver: SliverMainAxisGroup(
                                                      slivers:
                                                          _settingsSlivers(),
                                                    ),
                                                  ),
                                            ),
                                          ],
                                        )
                                      : SingleChildScrollView(
                                          key: PageStorageKey(
                                            'reading-room-$page',
                                          ),
                                          padding: EdgeInsets.fromLTRB(
                                            compact ? 22 : 44,
                                            compact ? 28 : 34,
                                            compact ? 22 : 44,
                                            140,
                                          ),
                                          child: Center(
                                            child: ConstrainedBox(
                                              constraints: const BoxConstraints(
                                                maxWidth: 1100,
                                              ),
                                              child: switch (page) {
                                                0 => _shelf(compact),
                                                1 => DiscoveryPage(
                                                  key: ValueKey(
                                                    widget.library
                                                        .option<String>(
                                                          'source',
                                                          'dm5',
                                                        ),
                                                  ),
                                                  library: widget.library,
                                                  source: source,
                                                  web: widget.web,
                                                  onOpen: open,
                                                ),
                                                2 => _history(),
                                                _ => const SizedBox.shrink(),
                                              },
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
            ],
          ),
          bottomNavigationBar: wide
              ? null
              : FrostedNavigation(
                  selectedIndex: tab,
                  onSelected: navigate,
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
        const SizedBox(height: 62),
        for (final item in [
          (Icons.auto_stories_outlined, '我的书架'),
          (Icons.explore_outlined, '发现漫画'),
          (Icons.history, '阅读足迹'),
          (Icons.tune, '偏好设置'),
        ].indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Material(
              color: tab == item.$1
                  ? green.withValues(alpha: .1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => navigate(item.$1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 13,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        item.$2.$1,
                        size: 19,
                        color: tab == item.$1
                            ? Theme.of(context).colorScheme.primary
                            : quiet(context),
                      ),
                      const SizedBox(width: 13),
                      LocalizedText(
                        item.$2.$2,
                        style: TextStyle(
                          fontSize: 14,
                          color: tab == item.$1
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
        const Spacer(),
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
      if (!wide) _brand() else LocalizedText('私人阅读室', style: small(context)),
      const Spacer(),
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
        tooltip: '下载与本地书库',
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
        tooltip: '搜索漫画',
        onPressed: () {
          navigate(1);
        },
        icon: const Icon(Icons.search, size: 22),
      ),
    ],
  );
  Widget _heading(String title, String description, {Widget? trailing}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 28),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LocalizedText(
                    title,
                    style: const TextStyle(
                      fontSize: 34,
                      letterSpacing: 2,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  LocalizedText(
                    description,
                    style: TextStyle(
                      fontSize: 12,
                      color: quiet(context),
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      );
  Widget _shelf(bool compact) {
    final books = widget.library.books;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(
          '我的书架',
          '把喜欢的故事，留在手边。',
          trailing: IconButton(
            tooltip: widget.library.grid ? '切换立体书架' : '切换封面网格',
            onPressed: () =>
                widget.library.setting('grid', !widget.library.grid),
            icon: Icon(
              widget.library.grid
                  ? Icons.view_carousel_outlined
                  : Icons.grid_view_outlined,
              size: 20,
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  LocalizedText(
                    '全部收藏',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  LocalizedText(
                    '${books.length.toString().padLeft(2, '0')} 册',
                    style: small(context),
                  ),
                  if (widget.library.demo)
                    LocalizedText('演示书架', style: small(context)),
                ],
              ),
            ),
            IconButton(
              tooltip: '整理收藏',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LibraryManager(
                    library: widget.library,
                    web: widget.web,
                    onOpen: open,
                  ),
                ),
              ),
              icon: const Icon(Icons.tune, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Divider(color: Theme.of(context).dividerColor, height: 1),
        if (books.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 80),
            child: EmptyState(
              icon: Icons.auto_stories_outlined,
              title: '书架，等你放上第一本漫画',
              message: '去发现页搜索喜欢的漫画，加入收藏。',
              action: () => navigate(1),
              actionLabel: '发现漫画',
            ),
          )
        else if (widget.library.grid)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: ComicGrid(books: books, web: widget.web, onOpen: open),
          )
        else
          LivingShelf(
            books: books,
            library: widget.library,
            web: widget.web,
            onOpen: open,
            onAmbientColor: (color) {
              if (mounted) atmosphere.value = color;
            },
            onBookOrigin: (comic, rect) => openingOrigin = (comic.path, rect),
          ),
        const SizedBox(height: 34),
        Row(
          children: [
            const Expanded(
              child: LocalizedText('留一枚书签', style: TextStyle(fontSize: 21)),
            ),
            TextButton(
              onPressed: () => navigate(2),
              child: const LocalizedText(
                '阅读足迹  ↗',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _continueCard(),
        const SizedBox(height: 32),
        Row(
          children: [
            const Expanded(
              child: LocalizedText('下一段故事', style: TextStyle(fontSize: 21)),
            ),
            TextButton(
              onPressed: () => navigate(1),
              child: const LocalizedText(
                '去发现  ↗',
                style: TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 100 * MediaQuery.textScalerOf(context).scale(1).clamp(1, 1.5),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: widget.library.samples.length,
            itemBuilder: (_, i) {
              final c = widget.library.samples[i];
              return SizedBox(
                width: compact ? 205 : 235,
                child: InkWell(
                  onTap: () => open(c),
                  borderRadius: BorderRadius.circular(6),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: SizedBox(
                          width: 62,
                          height: 88,
                          child: ComicCover(c, web: widget.web),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            LocalizedText(
                              c.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14),
                            ),
                            const SizedBox(height: 10),
                            LocalizedText(
                              '查看漫画  ↗',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: small(context),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
            separatorBuilder: (_, _) => const SizedBox(width: 22),
          ),
        ),
        const SizedBox(height: 32),
        Center(child: LocalizedText('故事很长，慢慢读。', style: small(context))),
      ],
    );
  }

  Widget _continueCard() {
    final record = widget.library.history.firstOrNull;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: green.withValues(alpha: .055),
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 35,
            height: 56,
            alignment: Alignment.topCenter,
            child: Icon(
              Icons.bookmark,
              size: 38,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LocalizedText(
                  record?.comic.title ?? '还没有翻开的故事',
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 8),
                LocalizedText(
                  record == null
                      ? '开始阅读后，书签会替你记住这一页。'
                      : '${record.chapterTitle} · 第 ${record.page + 1} / ${record.total} 页',
                  style: small(context),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: record == null ? '去选一本漫画' : '继续阅读',
            onPressed: () {
              if (record == null) {
                navigate(1);
              } else {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ReaderPage(
                      comic: record.comic,
                      chapter: Chapter(record.chapterPath, record.chapterTitle),
                      library: widget.library,
                      source: source,
                      web: widget.web,
                    ),
                  ),
                );
              }
            },
            icon: const Icon(Icons.arrow_forward, size: 21),
          ),
        ],
      ),
    );
  }

  Widget _history() =>
      HistoryPage(library: widget.library, source: source, web: widget.web);
  List<Widget> _settingsSlivers() => [
    SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading('偏好设置', '让阅读室，成为你喜欢的样子。'),
          _settingGroup('外观与交互', [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const LocalizedText(
                '夜间阅读室',
                style: TextStyle(fontSize: 15),
              ),
              subtitle: LocalizedText('柔和深色背景，适合夜晚阅读', style: small(context)),
              value: widget.library.dark,
              onChanged: (v) => widget.library.setting('dark', v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const LocalizedText(
                '书架动效',
                style: TextStyle(fontSize: 15),
              ),
              subtitle: LocalizedText(
                '抽书与页面转场；跟随系统减少动画偏好',
                style: small(context),
              ),
              value: widget.library.motion,
              onChanged: (v) => widget.library.setting('motion', v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const LocalizedText(
                '封面网格',
                style: TextStyle(fontSize: 15),
              ),
              subtitle: LocalizedText('使用平面书架浏览收藏', style: small(context)),
              value: widget.library.grid,
              onChanged: (v) => widget.library.setting('grid', v),
            ),
          ]),
          const SizedBox(height: 30),
          _settingGroup('阅读与数据', [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const LocalizedText(
                '默认漫画源',
                style: TextStyle(fontSize: 15),
              ),
              subtitle: LocalizedText('动漫屋 · m.dm5.com', style: small(context)),
              trailing: const Icon(Icons.public, size: 20),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const LocalizedText(
                '显示演示书架',
                style: TextStyle(fontSize: 15),
              ),
              subtitle: LocalizedText('个人收藏为空时，展示示例漫画', style: small(context)),
              value: widget.library.demo,
              onChanged: (v) => widget.library.setting('demo', v),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const LocalizedText(
                '清空阅读足迹',
                style: TextStyle(fontSize: 15),
              ),
              subtitle: LocalizedText('仅清除本机页码记录，保留收藏', style: small(context)),
              trailing: const Icon(Icons.delete_outline, size: 20),
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const LocalizedText('清空阅读足迹？'),
                    content: const LocalizedText('已保存的章节和页码记录将被清除。'),
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
                if (ok == true) await widget.library.clearHistory();
              },
            ),
          ]),
        ],
      ),
    ),
    AdvancedSettings(
      sliver: true,
      library: widget.library,
      source: source,
      web: widget.web,
    ),
    SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 35),
          const LocalizedText(
            '漫匣 MANXIA',
            style: TextStyle(fontSize: 23, letterSpacing: 2),
          ),
          const SizedBox(height: 10),
          LocalizedText('为每一段故事，留一个位置。', style: small(context)),
          const SizedBox(height: 22),
          TextButton(
            onPressed: () => showLicensePage(
              context: context,
              applicationName: '漫匣',
              applicationVersion: '0.2.4',
            ),
            child: const LocalizedText(
              '开源许可与字体声明',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    ),
  ];
  Widget _settingGroup(String label, List<Widget> children) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      LocalizedText(
        label,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      const SizedBox(height: 10),
      const Divider(),
      ...children,
    ],
  );
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
  });
  final List<Comic> books;
  final bool web;
  final ValueChanged<Comic> onOpen;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final columns = math.max(2, (box.maxWidth / 170).floor());
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: books.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: 24,
          crossAxisSpacing: 20,
          childAspectRatio: .59,
        ),
        itemBuilder: (context, i) {
          final comic = books[i];
          return InkWell(
            onTap: () => onOpen(comic),
            borderRadius: BorderRadius.circular(5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: .1),
                          blurRadius: 12,
                          offset: const Offset(3, 7),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: SizedBox(
                        width: double.infinity,
                        child: ComicCover(comic, web: web),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 13),
                LocalizedText(
                  comic.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 5),
                LocalizedText(
                  comic.latest.isEmpty ? '动漫屋' : comic.latest,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: small(context),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.actionLabel = '重试',
  });
  final IconData icon;
  final String title, message, actionLabel;
  final VoidCallback? action;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
      child: Column(
        children: [
          Icon(icon, size: 38, color: quiet(context)),
          const SizedBox(height: 22),
          LocalizedText(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 19),
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
            const SizedBox(height: 24),
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
