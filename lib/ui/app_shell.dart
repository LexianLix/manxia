import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/comic.dart';
import '../data/dm5_source.dart';
import '../data/library.dart';
import 'book_object.dart';
import 'detail_page.dart';
import 'reader_page.dart';

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
  late final source = Dm5Source(gateway: widget.web ? Uri.base : null);
  final search = TextEditingController();
  Future<List<Comic>>? results;
  String query = '';
  int visibleResults = 24;
  @override
  void dispose() {
    search.dispose();
    source.close();
    super.dispose();
  }

  void navigate(int i) {
    setState(() {
      tab = i;
      if (i == 1) results ??= source.home();
    });
  }

  void open(Comic c) => Navigator.of(context).push(
    PageRouteBuilder(
      transitionDuration: Duration(
        milliseconds:
            widget.library.motion && !MediaQuery.disableAnimationsOf(context)
            ? 440
            : 0,
      ),
      reverseTransitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, _, _) => DetailPage(
        comic: c,
        library: widget.library,
        source: source,
        web: widget.web,
      ),
      transitionsBuilder: (_, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        child: child,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.library,
    builder: (context, _) => LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 1000;
        final compact = box.maxWidth < 600;
        return Scaffold(
          body: SafeArea(
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
                            child: SingleChildScrollView(
                              key: ValueKey(tab),
                              padding: EdgeInsets.fromLTRB(
                                compact ? 22 : 44,
                                compact ? 28 : 34,
                                compact ? 22 : 44,
                                36,
                              ),
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 1100,
                                  ),
                                  child: switch (tab) {
                                    0 => _shelf(compact),
                                    1 => _discover(compact),
                                    2 => _history(),
                                    _ => _settings(),
                                  },
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
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  height: 70,
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  selectedIndex: tab,
                  onDestinationSelected: navigate,
                  indicatorColor: green.withValues(alpha: .12),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.auto_stories_outlined),
                      selectedIcon: Icon(Icons.auto_stories),
                      label: '书架',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.explore_outlined),
                      selectedIcon: Icon(Icons.explore),
                      label: '发现',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.history),
                      label: '足迹',
                    ),
                    NavigationDestination(icon: Icon(Icons.tune), label: '设置'),
                  ],
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
          child: Text(
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
      const Text(
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
        Text(
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
                      Text(
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
        Text(
          '一册漫画，\n一段自己的时间。',
          style: TextStyle(fontSize: 12, height: 1.9, color: quiet(context)),
        ),
        const SizedBox(height: 22),
        Text(
          'MANXIA · YOUR READING ROOM',
          style: small(context).copyWith(fontSize: 8, letterSpacing: .4),
        ),
      ],
    ),
  );
  Widget _topbar(bool wide) => Row(
    children: [
      if (!wide) _brand() else Text('私人阅读室', style: small(context)),
      const Spacer(),
      Semantics(
        label: '默认漫画源动漫屋',
        child: Container(
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
              Text(
                '动漫屋',
                style: TextStyle(fontSize: 11, color: quiet(context)),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(width: 8),
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
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 34,
                      letterSpacing: 2,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
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
            Text(
              '全部收藏',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${books.length.toString().padLeft(2, '0')} 册',
              style: small(context),
            ),
            const Spacer(),
            if (widget.library.demo) Text('演示书架', style: small(context)),
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
          ShelfScene(
            books: books,
            library: widget.library,
            web: widget.web,
            onOpen: open,
          ),
        const SizedBox(height: 34),
        Row(
          children: [
            const Text('留一枚书签', style: TextStyle(fontSize: 21)),
            const Spacer(),
            TextButton(
              onPressed: () => navigate(2),
              child: const Text('阅读足迹  ↗', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _continueCard(),
        const SizedBox(height: 32),
        Row(
          children: [
            const Text('下一段故事', style: TextStyle(fontSize: 21)),
            const Spacer(),
            TextButton(
              onPressed: () => navigate(1),
              child: const Text('去发现  ↗', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 100,
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
                            Text(
                              c.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14),
                            ),
                            const SizedBox(height: 10),
                            Text('查看漫画  ↗', style: small(context)),
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
        Center(child: Text('故事很长，慢慢读。', style: small(context))),
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
                Text(
                  record?.comic.title ?? '还没有翻开的故事',
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
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

  Widget _discover(bool compact) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading('发现漫画', '从动漫屋，遇见下一段故事。'),
      TextField(
        controller: search,
        textInputAction: TextInputAction.search,
        onSubmitted: _search,
        decoration: InputDecoration(
          hintText: '搜索漫画名称或作者',
          prefixIcon: const Icon(Icons.search, size: 21),
          suffixIcon: IconButton(
            tooltip: '开始搜索',
            onPressed: () => _search(search.text),
            icon: const Icon(Icons.arrow_forward, size: 20),
          ),
        ),
      ),
      const SizedBox(height: 20),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final label in ['海贼王', '冰之城壁', '青之芦苇', '蓝箱'])
            ActionChip(
              label: Text(label, style: const TextStyle(fontSize: 11)),
              side: BorderSide(color: Theme.of(context).dividerColor),
              onPressed: () {
                search.text = label;
                _search(label);
              },
            ),
        ],
      ),
      const SizedBox(height: 30),
      Row(
        children: [
          Text(
            query.isEmpty ? '来自动漫屋' : '“$query”的搜索结果',
            style: const TextStyle(fontSize: 20),
          ),
          const Spacer(),
          IconButton(
            tooltip: '刷新列表',
            onPressed: () => _search(query),
            icon: const Icon(Icons.refresh, size: 19),
          ),
        ],
      ),
      const SizedBox(height: 18),
      FutureBuilder<List<Comic>>(
        future: results,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.all(70),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          if (snapshot.hasError) {
            return EmptyState(
              icon: Icons.cloud_off_outlined,
              title: '暂时没能打开动漫屋',
              message: friendlyError(snapshot.error),
              action: () => _search(query),
              actionLabel: '重新加载',
            );
          }
          if (snapshot.data?.isEmpty ?? true) {
            return const EmptyState(
              icon: Icons.search_off,
              title: '没有找到这部漫画',
              message: '试试更短的名称，或换一个关键词。',
            );
          }
          return Column(
            children: [
              ComicGrid(
                books: snapshot.data!.take(visibleResults).toList(),
                web: widget.web,
                onOpen: open,
              ),
              if (snapshot.data!.length > visibleResults)
                Padding(
                  padding: const EdgeInsets.only(top: 28),
                  child: OutlinedButton(
                    onPressed: () => setState(() => visibleResults += 24),
                    child: Text(
                      '显示更多 · 还有 ${snapshot.data!.length - visibleResults} 部漫画',
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ],
  );
  void _search(String value) {
    setState(() {
      query = value.trim();
      visibleResults = 24;
      results = query.isEmpty ? source.home() : source.search(query);
    });
  }

  Widget _history() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading('阅读足迹', '书签记得，你曾在哪一页停留。'),
      if (widget.library.history.isEmpty)
        EmptyState(
          icon: Icons.bookmark_border,
          title: '第一枚书签，等你翻开',
          message: '阅读过的漫画会显示在这里。',
          action: () => navigate(1),
          actionLabel: '去发现',
        )
      else
        for (final record in widget.library.history)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                vertical: 8,
                horizontal: 0,
              ),
              leading: SizedBox(
                width: 46,
                height: 64,
                child: ComicCover(record.comic, web: widget.web),
              ),
              title: Text(record.comic.title),
              subtitle: Text(
                '${record.chapterTitle} · 第 ${record.page + 1} / ${record.total} 页',
                style: small(context),
              ),
              trailing: const Icon(Icons.arrow_forward, size: 19),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ReaderPage(
                    comic: record.comic,
                    chapter: Chapter(record.chapterPath, record.chapterTitle),
                    library: widget.library,
                    source: source,
                    web: widget.web,
                  ),
                ),
              ),
            ),
          ),
    ],
  );
  Widget _settings() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading('偏好设置', '让阅读室，成为你喜欢的样子。'),
      _settingGroup('外观与交互', [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('夜间阅读室', style: TextStyle(fontSize: 15)),
          subtitle: Text('柔和深色背景，适合夜晚阅读', style: small(context)),
          value: widget.library.dark,
          onChanged: (v) => widget.library.setting('dark', v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('书架动效', style: TextStyle(fontSize: 15)),
          subtitle: Text('抽书与页面转场；跟随系统减少动画偏好', style: small(context)),
          value: widget.library.motion,
          onChanged: (v) => widget.library.setting('motion', v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('封面网格', style: TextStyle(fontSize: 15)),
          subtitle: Text('使用平面书架浏览收藏', style: small(context)),
          value: widget.library.grid,
          onChanged: (v) => widget.library.setting('grid', v),
        ),
      ]),
      const SizedBox(height: 30),
      _settingGroup('阅读与数据', [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('默认漫画源', style: TextStyle(fontSize: 15)),
          subtitle: Text('动漫屋 · m.dm5.com', style: small(context)),
          trailing: const Icon(Icons.public, size: 20),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('显示演示书架', style: TextStyle(fontSize: 15)),
          subtitle: Text('个人收藏为空时，展示示例漫画', style: small(context)),
          value: widget.library.demo,
          onChanged: (v) => widget.library.setting('demo', v),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('清空阅读足迹', style: TextStyle(fontSize: 15)),
          subtitle: Text('仅清除本机页码记录，保留收藏', style: small(context)),
          trailing: const Icon(Icons.delete_outline, size: 20),
          onTap: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('清空阅读足迹？'),
                content: const Text('已保存的章节和页码记录将被清除。'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('取消'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('清空'),
                  ),
                ],
              ),
            );
            if (ok == true) await widget.library.clearHistory();
          },
        ),
      ]),
      const SizedBox(height: 35),
      const Text('漫匣 MANXIA', style: TextStyle(fontSize: 23, letterSpacing: 2)),
      const SizedBox(height: 10),
      Text('为每一段故事，留一个位置。', style: small(context)),
      const SizedBox(height: 22),
      TextButton(
        onPressed: () => showLicensePage(
          context: context,
          applicationName: '漫匣',
          applicationVersion: '0.1.0',
        ),
        child: const Text('开源许可与字体声明', style: TextStyle(fontSize: 12)),
      ),
    ],
  );
  Widget _settingGroup(String label, List<Widget> children) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
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

class ShelfScene extends StatefulWidget {
  const ShelfScene({
    super.key,
    required this.books,
    required this.library,
    required this.web,
    required this.onOpen,
  });
  final List<Comic> books;
  final Library library;
  final bool web;
  final ValueChanged<Comic> onOpen;
  @override
  State<ShelfScene> createState() => _ShelfSceneState();
}

class _ShelfSceneState extends State<ShelfScene> {
  int selected = 3;
  void choose(int value) {
    if (value < 0 || value >= widget.books.length) return;
    setState(() => selected = value);
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    selected = selected.clamp(0, widget.books.length - 1);
    final comic = widget.books[selected];
    final duration = Duration(
      milliseconds:
          widget.library.motion && !MediaQuery.disableAnimationsOf(context)
          ? 480
          : 0,
    );
    return Column(
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).width < 600 ? 325 : 360,
          child: LayoutBuilder(
            builder: (context, box) {
              final scale = (box.maxWidth / 700).clamp(.73, 1.03);
              final gap = box.maxWidth < 500 ? 36.0 : 59.0;
              final center = box.maxWidth / 2 - 91 * scale;
              final order = List<int>.generate(widget.books.length, (i) => i)
                ..sort(
                  (a, b) =>
                      (b - selected).abs().compareTo((a - selected).abs()),
                );
              return GestureDetector(
                onHorizontalDragEnd: (d) {
                  if ((d.primaryVelocity ?? 0).abs() > 50) {
                    choose(selected + ((d.primaryVelocity ?? 0) < 0 ? 1 : -1));
                  }
                },
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 40,
                      child: Container(
                        height: 1,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              Theme.of(context).dividerColor,
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                    for (final i in order) ...[
                      AnimatedPositioned(
                        key: ValueKey('volume-${widget.books[i].path}'),
                        duration: duration,
                        curve: Curves.easeOutCubic,
                        left:
                            center +
                            (i - selected) * gap +
                            (i > selected ? 105 * scale : 0),
                        top: i == selected ? 13 : 70 + (i - selected).abs() * 3,
                        width: 200 * scale,
                        height: 280 * scale,
                        child: IgnorePointer(
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: i == selected ? 1 : 0),
                            duration: duration,
                            curve: Curves.easeOutCubic,
                            builder: (context, exposure, _) => Hero(
                              tag: 'book-${widget.books[i].path}',
                              child: BookObject(
                                widget.books[i],
                                web: widget.web,
                                exposure: exposure,
                                number: i + 1,
                                bookmark:
                                    widget.library.record(widget.books[i]) !=
                                    null,
                              ),
                            ),
                          ),
                        ),
                      ),
                      AnimatedPositioned(
                        key: ValueKey('hit-${widget.books[i].path}'),
                        duration: duration,
                        curve: Curves.easeOutCubic,
                        left:
                            center +
                            (i - selected) * gap +
                            (i > selected ? 105 * scale : 0) +
                            17 * scale,
                        top: i == selected
                            ? 50
                            : 105 + (i - selected).abs() * 3,
                        width: (i == selected ? 163 : 34) * scale,
                        height: 208 * scale,
                        child: Semantics(
                          button: true,
                          label: i == selected
                              ? '查看${widget.books[i].title}'
                              : '选择${widget.books[i].title}',
                          child: Tooltip(
                            message: widget.books[i].title,
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => i == selected
                                    ? widget.onOpen(comic)
                                    : choose(i),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
        Row(
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: duration,
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.centerLeft,
                  children: [...previous, ?current],
                ),
                child: Column(
                  key: ValueKey(comic.path),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      comic.title,
                      style: const TextStyle(fontSize: 26, letterSpacing: 1),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.library.record(comic) == null
                          ? '动漫屋 · 轻触封面，翻开故事'
                          : '书签已停在 ${widget.library.record(comic)!.chapterTitle}',
                      style: small(context),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: '上一本',
              onPressed: selected > 0 ? () => choose(selected - 1) : null,
              icon: const Icon(Icons.chevron_left, size: 21),
            ),
            Text(
              '${(selected + 1).toString().padLeft(2, '0')} / ${widget.books.length.toString().padLeft(2, '0')}',
              style: small(context),
            ),
            IconButton(
              tooltip: '下一本',
              onPressed: selected < widget.books.length - 1
                  ? () => choose(selected + 1)
                  : null,
              icon: const Icon(Icons.chevron_right, size: 21),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            FilledButton.icon(
              onPressed: () => widget.onOpen(comic),
              icon: const Icon(Icons.menu_book_outlined, size: 17),
              label: const Text('翻开这本漫画', style: TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 12),
            Tooltip(
              message: widget.library.contains(comic) ? '移出收藏' : '加入收藏',
              child: OutlinedButton(
                onPressed: () => widget.library.toggle(comic),
                child: Icon(
                  widget.library.contains(comic)
                      ? Icons.bookmark
                      : Icons.bookmark_border,
                  size: 19,
                ),
              ),
            ),
            const Spacer(),
            if (MediaQuery.sizeOf(context).width > 700)
              Text('左右滑动，挑选一本', style: small(context)),
          ],
        ),
      ],
    );
  }
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
                Text(
                  comic.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 5),
                Text(
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
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 19),
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Text(
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
            OutlinedButton(onPressed: action, child: Text(actionLabel)),
          ],
        ],
      ),
    ),
  );
}
