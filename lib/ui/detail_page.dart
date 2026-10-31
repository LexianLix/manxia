import 'localized_text.dart';
import 'dart:math' as math;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/comic.dart';
import '../data/dm5_source.dart';
import '../data/library.dart';
import '../data/reading_progress.dart';
import '../data/source_hub.dart';
import 'app_shell.dart';
import 'book_object.dart';
import 'collection_motion.dart';
import 'reader_page.dart';
import 'offline_page.dart';
import 'library_manager.dart';
import 'content_handoff.dart';
import 'book_link.dart';
import 'book_navigation.dart';
import 'source_search_page.dart';
import 'sliver_handoff.dart';
import 'room_motion.dart';

class DetailPage extends StatefulWidget {
  const DetailPage({
    super.key,
    required this.comic,
    required this.library,
    required this.source,
    required this.web,
    this.bookNumber = 1,
    this.flightTag,
  });
  final Comic comic;
  final Library library;
  final Dm5Source source;
  final bool web;
  final int bookNumber;
  final Object? flightTag;
  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  Future<ComicDetail> fetchDetail() async {
    final result = await widget.source.detail(widget.comic);
    try {
      await widget.library.rememberChapters(result.comic, result.chapters);
    } catch (_) {
      /* Local metadata must not block a readable catalog. */
    }
    return result;
  }

  late Future<ComicDetail> detail = fetchDetail();
  String group = '连载';
  bool ascending = true;
  bool enteringReader = false;
  bool findingSource = false;
  Future<void> findAnotherSource() async {
    if (findingSource || widget.source is! SourceHub) return;
    findingSource = true;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SourceSearchPage(
            comic: widget.comic,
            library: widget.library,
            source: widget.source as SourceHub,
            web: widget.web,
            onOpen: (comic) async {
              await Navigator.of(context).push(
                comicDetailRoute(
                  context,
                  comic: comic,
                  library: widget.library,
                  source: widget.source,
                  web: widget.web,
                  flightTag: BookLink.takeTag(context, comic),
                ),
              );
            },
          ),
        ),
      );
    } finally {
      findingSource = false;
    }
  }

  final coverKey = GlobalKey();
  void retry() => setState(() {
    detail = fetchDetail();
  });

  Future<void> copyDiagnostics(String path) async {
    final data = widget.source.detailDiagnostics[path];
    await Clipboard.setData(
      ClipboardData(text: const JsonEncoder.withIndent('  ').convert(data)),
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: LocalizedText('已复制目录诊断信息')));
    }
  }

  Rect? coverBounds() {
    final object = coverKey.currentContext?.findRenderObject();
    return object is RenderBox && object.hasSize
        ? object.localToGlobal(Offset.zero) & object.size
        : null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final update = widget.library.updates[widget.comic.path];
      if (mounted && update?['changed'] == true) {
        update!['changed'] = false;
        widget.library.persistFeatures();
      }
    });
  }

  Future<void> read(
    Comic comic,
    Chapter chapter,
    List<Chapter> chapters,
  ) async {
    if (enteringReader) return;
    enteringReader = true;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ReaderPage(
            comic: comic,
            chapter: chapter,
            chapters: chapters,
            library: widget.library,
            source: widget.source,
            web: widget.web,
          ),
        ),
      );
    } finally {
      enteringReader = false;
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: FutureBuilder<ComicDetail>(
        future: detail,
        builder: (context, snapshot) {
          SourceCopyrightException? copyrightFailure =
              snapshot.error is SourceCopyrightException
              ? snapshot.error as SourceCopyrightException
              : null;
          final comic =
              snapshot.data?.comic ?? copyrightFailure?.comic ?? widget.comic;
          final attempts =
              widget.source.detailDiagnostics[comic.path]?['attempts'];
          if (snapshot.connectionState == ConnectionState.done &&
              attempts is List) {
            for (final attempt in attempts.whereType<Map>()) {
              if (attempt['availability'] == 'copyright' &&
                  attempt['notice'] is String) {
                copyrightFailure = SourceCopyrightException(
                  attempt['notice'] as String,
                );
              }
            }
          }
          final noCopyright = copyrightFailure != null;
          final sourceName = comic.sourceId == 'local'
              ? '本地书库'
              : comic.sourceId == 'dm5'
              ? '动漫屋'
              : widget.source is SourceHub
              ? (widget.source as SourceHub).profiles
                        .where((p) => p['id'] == comic.sourceId)
                        .map((p) => p['name'] as String)
                        .firstOrNull ??
                    '自定义书源'
              : '自定义书源';
          final chapters = snapshot.data?.chapters ?? <Chapter>[];
          final groups = chapters.map((c) => c.group).toSet().toList();
          if (groups.isNotEmpty && !groups.contains(group)) {
            group = groups.first;
          }
          final visible = chapters.where((c) => c.group == group).toList();
          final ordered = ascending ? visible.reversed.toList() : visible;
          final history = widget.library.record(comic);
          final compact = MediaQuery.sizeOf(context).width < 650;
          final mainChapters = chapters
              .where((c) => c.group == (groups.firstOrNull ?? '连载'))
              .toList()
              .reversed
              .toList();
          void start() {
            if (history != null) {
              read(
                comic,
                Chapter(history.chapterPath, history.chapterTitle),
                mainChapters,
              );
            } else if (mainChapters.isNotEmpty) {
              read(comic, mainChapters.first, mainChapters);
            }
          }

          Widget info() => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LocalizedText(
                'MANGA / $sourceName',
                style: small(context).copyWith(letterSpacing: 2, fontSize: 10),
              ),
              const SizedBox(height: 16),
              LocalizedText(
                comic.title,
                style: TextStyle(
                  fontSize: compact ? 31 : 40,
                  letterSpacing: 2,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 13),
              LocalizedText(
                comic.author.isEmpty ? '漫画详情' : comic.author,
                style: TextStyle(fontSize: 13, color: quiet(context)),
              ),
              const SizedBox(height: 16),
              if (comic.tags.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: comic.tags
                      .map(
                        (t) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Theme.of(context).dividerColor,
                            ),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: LocalizedText(t, style: small(context)),
                        ),
                      )
                      .toList(),
                ),
              if (comic.latest.isNotEmpty) ...[
                const SizedBox(height: 18),
                LocalizedText('最新章节 · ${comic.latest}', style: small(context)),
              ],
              if (comic.description.isNotEmpty) ...[
                const SizedBox(height: 18),
                LocalizedText(
                  comic.description,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.9,
                    color: quiet(context),
                  ),
                ),
              ],
              const SizedBox(height: 25),
              Wrap(
                spacing: 10,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: history != null || mainChapters.isNotEmpty
                        ? start
                        : null,
                    icon: const Icon(Icons.menu_book_outlined, size: 17),
                    label: LocalizedText(
                      history != null
                          ? '继续阅读'
                          : mainChapters.isNotEmpty
                          ? noCopyright
                                ? '阅读已下载章节'
                                : '开始阅读'
                          : snapshot.connectionState != ConnectionState.done
                          ? '正在读取目录'
                          : noCopyright
                          ? '书源没有版权'
                          : '章节暂不可用',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  if (comic.sourceId != 'local')
                    OutlinedButton.icon(
                      onPressed: chapters.isEmpty
                          ? null
                          : () => selectDownloads(
                              context,
                              comic,
                              chapters.reversed.toList(),
                            ),
                      icon: const Icon(Icons.download_outlined, size: 17),
                      label: const LocalizedText(
                        '下载章节',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  IconButton(
                    tooltip: '分组、标签与系列',
                    onPressed: () => editBook(context, widget.library, comic),
                    icon: const Icon(Icons.more_horiz, size: 20),
                  ),
                  ListenableBuilder(
                    listenable: widget.library,
                    builder: (context, _) => OutlinedButton.icon(
                      onPressed: () => collectWithMotion(
                        context,
                        comic,
                        widget.library,
                        widget.web,
                        origin: coverBounds(),
                      ),
                      icon: Icon(
                        widget.library.contains(comic)
                            ? Icons.bookmark
                            : Icons.bookmark_border,
                        size: 17,
                      ),
                      label: LocalizedText(
                        widget.library.contains(comic) ? '已收藏' : '加入书架',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
              ContentHandoff(
                child: snapshot.connectionState != ConnectionState.done
                    ? Padding(
                        key: const ValueKey('directory-loading'),
                        padding: const EdgeInsets.only(top: 14),
                        child: Row(
                          children: [
                            const SizedBox.square(
                              dimension: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                              ),
                            ),
                            const SizedBox(width: 10),
                            LocalizedText('正在读取章节目录…', style: small(context)),
                          ],
                        ),
                      )
                    : chapters.isEmpty || noCopyright
                    ? Container(
                        key: const ValueKey('directory-retry'),
                        margin: const EdgeInsets.only(top: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            LocalizedText(
                              noCopyright
                                  ? '${copyrightFailure!.message}${chapters.isNotEmpty ? '\n已下载章节仍可离线阅读。' : ''}'
                                  : snapshot.hasError
                                  ? friendlyError(snapshot.error)
                                  : '尚未识别到章节目录，请重新加载。',
                              style: small(context),
                            ),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                TextButton.icon(
                                  onPressed: retry,
                                  icon: const Icon(Icons.refresh, size: 16),
                                  label: const LocalizedText('重试读取目录'),
                                ),
                                if (widget.source is SourceHub)
                                  OutlinedButton.icon(
                                    onPressed: findAnotherSource,
                                    icon: const Icon(
                                      Icons.travel_explore,
                                      size: 17,
                                    ),
                                    label: const LocalizedText('换源查找'),
                                  ),
                                if (widget.source.detailDiagnostics.containsKey(
                                  comic.path,
                                ))
                                  PopupMenuButton<String>(
                                    popUpAnimationStyle: RoomMotion.sheet(
                                      context,
                                    ),
                                    tooltip: translate(
                                      '更多操作',
                                      Localizations.localeOf(context),
                                    ),
                                    icon: const Icon(
                                      Icons.more_horiz,
                                      size: 18,
                                    ),
                                    itemBuilder: (_) => [
                                      const PopupMenuItem(
                                        value: 'copy',
                                        child: LocalizedText('复制目录诊断'),
                                      ),
                                    ],
                                    onSelected: (_) =>
                                        copyDiagnostics(comic.path),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(key: ValueKey('directory-ready')),
              ),
              if (history != null) ...[
                const SizedBox(height: 14),
                LocalizedText(
                  '上次读到 ${history.chapterTitle} · 第 ${history.page + 1} 页',
                  style: small(context),
                ),
              ],
            ],
          );
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        compact ? 18 : 40,
                        20,
                        compact ? 18 : 40,
                        0,
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: '返回书架',
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.arrow_back, size: 21),
                          ),
                          const SizedBox(width: 8),
                          LocalizedText('回到阅读室', style: small(context)),
                          const Spacer(),
                          if (comic.sourceId != 'local')
                            IconButton(
                              tooltip: '在原站打开',
                              onPressed: () => launchUrl(
                                comic.path.startsWith('custom:') &&
                                        widget.source is SourceHub
                                    ? (widget.source as SourceHub)
                                          .profile(comic.path)
                                          .decode(comic.path)
                                    : Uri.parse(
                                        '${Dm5Source.origin}${comic.path}',
                                      ),
                                mode: LaunchMode.externalApplication,
                              ),
                              icon: const Icon(Icons.open_in_new, size: 19),
                            ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        compact ? 26 : 60,
                        compact ? 5 : 35,
                        compact ? 26 : 60,
                        35,
                      ),
                      child: compact
                          ? Column(
                              children: [
                                SizedBox(
                                  height: 280,
                                  width: 200,
                                  child: DetailCover(
                                    comic,
                                    web: widget.web,
                                    opening: widget.library.option<bool>(
                                      'bookOpening',
                                      true,
                                    ),
                                    tag: widget.flightTag,
                                    key: coverKey,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                info(),
                              ],
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 300,
                                  height: 350,
                                  child: Center(
                                    child: SizedBox(
                                      width: 240,
                                      height: 336,
                                      child: DetailCover(
                                        comic,
                                        web: widget.web,
                                        opening: widget.library.option<bool>(
                                          'bookOpening',
                                          true,
                                        ),
                                        tag: widget.flightTag,
                                        key: coverKey,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 45),
                                Expanded(child: info()),
                              ],
                            ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 26 : 60,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Divider(),
                          const SizedBox(height: 26),
                          Row(
                            children: [
                              const LocalizedText(
                                '章节目录',
                                style: TextStyle(fontSize: 24),
                              ),
                              const SizedBox(width: 12),
                              if (chapters.isNotEmpty)
                                LocalizedText(
                                  '${chapters.length} 章',
                                  style: small(context),
                                ),
                              const Spacer(),
                              if (chapters.isNotEmpty)
                                IconButton(
                                  tooltip: ascending ? '切换倒序' : '切换正序',
                                  onPressed: () =>
                                      setState(() => ascending = !ascending),
                                  icon: const Icon(Icons.swap_vert, size: 20),
                                ),
                            ],
                          ),
                          if (groups.length > 1)
                            Padding(
                              padding: const EdgeInsets.only(
                                top: 15,
                                bottom: 12,
                              ),
                              child: Wrap(
                                spacing: 10,
                                children: groups
                                    .map(
                                      (g) => ChoiceChip(
                                        label: LocalizedText(
                                          g,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        selected: g == group,
                                        onSelected: (_) =>
                                            setState(() => group = g),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                          ContentHandoff(
                            child: Column(
                              key: ValueKey(
                                snapshot.connectionState != ConnectionState.done
                                    ? 'catalog-loading'
                                    : snapshot.hasError
                                    ? 'catalog-error'
                                    : chapters.isEmpty
                                    ? 'catalog-empty'
                                    : 'catalog-ready',
                              ),
                              children: [
                                if (snapshot.connectionState !=
                                    ConnectionState.done)
                                  const Padding(
                                    padding: EdgeInsets.all(55),
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                else if (snapshot.hasError)
                                  EmptyState(
                                    icon: noCopyright
                                        ? Icons.copyright_outlined
                                        : Icons.cloud_off_outlined,
                                    title: noCopyright
                                        ? '当前书源没有版权'
                                        : '目录暂时无法读取',
                                    message: friendlyError(snapshot.error),
                                    action: retry,
                                    actionLabel: '重新加载',
                                  )
                                else if (chapters.isEmpty)
                                  EmptyState(
                                    icon: Icons.menu_book_outlined,
                                    title: '尚未读取到目录',
                                    message: '当前返回内容中未识别到章节，请重新加载或打开原站核对。',
                                    action: retry,
                                    actionLabel: '重新加载',
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                  SliverHandoff(
                    identity: (group, ascending, snapshot.data),
                    animate: widget.library.motion,
                    sliver: SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        compact ? 26 : 60,
                        0,
                        compact ? 26 : 60,
                        45,
                      ),
                      sliver: SliverLayoutBuilder(
                        builder: (context, constraints) {
                          final columns = constraints.crossAxisExtent < 500
                              ? 2
                              : 4;
                          final rows = (ordered.length / columns).ceil();
                          final gridExtent = rows == 0
                              ? 0
                              : rows * 48 + (rows - 1) * 11;
                          // Keep a short group's first row at the same scroll
                          // position. This is virtual trailing space, not an
                          // eager list or a second laid-out chapter catalog.
                          final trailing = ordered.isEmpty
                              ? 0.0
                              : math.max(
                                  0.0,
                                  constraints.viewportMainAxisExtent -
                                      gridExtent -
                                      45,
                                );
                          return SliverMainAxisGroup(
                            slivers: [
                              SliverGrid(
                                delegate: SliverChildBuilderDelegate((
                                  context,
                                  i,
                                ) {
                                  final chapter = ordered[i];
                                  final marked =
                                      history?.chapterPath == chapter.path;
                                  return OutlinedButton(
                                    key: ValueKey(chapter.path),
                                    onPressed: () => read(
                                      comic,
                                      chapter,
                                      visible.reversed.toList(),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      alignment: Alignment.centerLeft,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 13,
                                      ),
                                      side: BorderSide(
                                        color: marked
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.primary
                                            : Theme.of(context).dividerColor,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: LocalizedText(
                                            chapter.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: marked
                                                  ? Theme.of(
                                                      context,
                                                    ).colorScheme.primary
                                                  : Theme.of(
                                                      context,
                                                    ).colorScheme.onSurface,
                                            ),
                                          ),
                                        ),
                                        if (marked)
                                          const Icon(Icons.bookmark, size: 14),
                                        if (widget.library.chapterRead(
                                          comic,
                                          chapter.path,
                                        ))
                                          const Icon(
                                            Icons.check_circle_outline,
                                            size: 14,
                                          ),
                                      ],
                                    ),
                                  );
                                }, childCount: ordered.length),
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: columns,
                                      mainAxisExtent: 48,
                                      mainAxisSpacing: 11,
                                      crossAxisSpacing: 11,
                                    ),
                              ),
                              if (trailing > 0)
                                SliverToBoxAdapter(
                                  child: SizedBox(height: trailing),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}
