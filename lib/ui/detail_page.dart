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
import '../data/script_source.dart';
import 'app_shell.dart';
import 'book_object.dart';
import 'collection_motion.dart';
import 'reader_page.dart';
import 'offline_page.dart';
import 'library_manager.dart';
import 'source_search_page.dart';
import 'sliver_handoff.dart';
import 'room_motion.dart';
import 'materials.dart';
import '../data/offline_library.dart';
import 'visible_listenable_builder.dart';

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
  bool fetchingDetail = false;
  Future<ComicDetail> fetchDetail() async {
    fetchingDetail = true;
    try {
      final result = await widget.source.detail(widget.comic);
      try {
        await widget.library.rememberChapters(result.comic, result.chapters);
      } catch (_) {
        /* Local metadata must not block a readable catalog. */
      }
      return result;
    } finally {
      fetchingDetail = false;
    }
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
      await showSourceRecovery(
        context,
        comic: widget.comic,
        library: widget.library,
        source: widget.source as SourceHub,
        web: widget.web,
      );
    } finally {
      findingSource = false;
    }
  }

  final coverKey = GlobalKey();
  void retry() {
    if (fetchingDetail) return;
    setState(() {
      detail = fetchDetail();
    });
  }

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

  bool descriptionExpanded = false;

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
  Widget build(BuildContext context) => FutureBuilder<ComicDetail>(
    future: detail,
    builder: (context, snapshot) {
      SourceCopyrightException? copyrightFailure =
          snapshot.error is SourceCopyrightException
          ? snapshot.error as SourceCopyrightException
          : null;
      final comic =
          snapshot.data?.comic ?? copyrightFailure?.comic ?? widget.comic;
      final attempts = widget.source.detailDiagnostics[comic.path]?['attempts'];
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
      final emptyCatalog =
          snapshot.error is ScriptSourceFailure &&
          (snapshot.error as ScriptSourceFailure).kind ==
              ScriptFailureKind.empty;
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

      final ready = snapshot.connectionState == ConnectionState.done;
      final canRead = history != null || mainChapters.isNotEmpty;
      final canChangeSource =
          comic.sourceId != 'local' && widget.source is SourceHub;
      final stateLabel = !ready
          ? '正在读取目录'
          : noCopyright
          ? '当前书源没有版权'
          : chapters.isEmpty
          ? snapshot.hasError && !emptyCatalog
                ? '目录暂时无法读取'
                : '暂无章节'
          : '${chapters.length} 章';
      final primaryLabel = canRead
          ? history != null
                ? '继续阅读'
                : noCopyright
                ? '阅读已下载章节'
                : '开始阅读'
          : !ready
          ? '正在读取目录'
          : canChangeSource
          ? '换源查找'
          : noCopyright
          ? '书源没有版权'
          : '重新加载';

      Widget info() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LocalizedText(
            comic.title,
            style: TextStyle(
              fontSize: compact ? 25 : 36,
              height: 1.3,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          LocalizedText(
            comic.author.isEmpty ? '漫画详情' : comic.author,
            style: TextStyle(fontSize: 13, color: quiet(context)),
          ),
          if (comic.tags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              comic.tags.join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: small(context),
            ),
          ],
          if (history != null) ...[
            const SizedBox(height: 12),
            LocalizedText(
              '上次读到 ${history.chapterTitle} · 第 ${history.page + 1} 页',
              style: small(context),
            ),
          ] else if (comic.latest.isNotEmpty) ...[
            const SizedBox(height: 12),
            LocalizedText('最新章节 · ${comic.latest}', style: small(context)),
          ],
        ],
      );
      Widget cover(double width) => SizedBox(
        width: width,
        height: width * 1.4,
        child: DetailCover(
          comic,
          web: widget.web,
          opening: widget.library.option<bool>('bookOpening', true),
          tag: widget.flightTag,
          key: coverKey,
        ),
      );
      final stacked =
          MediaQuery.sizeOf(context).width < 350 ||
          MediaQuery.textScalerOf(context).scale(14) > 19;
      return Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: () => Navigator.maybePop(context)),
          title: const LocalizedText('漫画详情', style: TextStyle(fontSize: 15)),
          actions: [
            PopupMenuButton<String>(
              tooltip: translate('更多操作', Localizations.localeOf(context)),
              popUpAnimationStyle: RoomMotion.sheet(context),
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'organize',
                  child: LocalizedText('分组、标签与系列'),
                ),
                if (comic.sourceId != 'local')
                  const PopupMenuItem(
                    value: 'original',
                    child: LocalizedText('在原站打开'),
                  ),
                if (widget.source.detailDiagnostics.containsKey(comic.path))
                  const PopupMenuItem(
                    value: 'diagnostics',
                    child: LocalizedText('复制目录诊断'),
                  ),
              ],
              onSelected: (value) async {
                if (value == 'organize') {
                  await editBook(context, widget.library, comic);
                } else if (value == 'diagnostics') {
                  await copyDiagnostics(comic.path);
                } else {
                  try {
                    final url =
                        comic.path.startsWith('custom:') &&
                            widget.source is SourceHub
                        ? (widget.source as SourceHub)
                              .profile(comic.path)
                              .decode(comic.path)
                        : Uri.parse('${Dm5Source.origin}${comic.path}');
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  } catch (error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: LocalizedText(friendlyError(error))),
                      );
                    }
                  }
                }
              },
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
                child: MilkGlass(
                  radius: 20,
                  high:
                      widget.library.option<String>('quality', 'high') ==
                      'high',
                  padding: const EdgeInsets.all(6),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          key: const ValueKey('detail-read'),
                          onPressed:
                              !canRead &&
                                  (!ready || noCopyright && !canChangeSource)
                              ? null
                              : canRead
                              ? start
                              : canChangeSource
                              ? findAnotherSource
                              : retry,
                          icon: Icon(
                            canRead
                                ? Icons.menu_book_outlined
                                : Icons.travel_explore,
                            size: 19,
                          ),
                          label: LocalizedText(
                            primaryLabel,
                            maxLines: 2,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      ListenableBuilder(
                        listenable: widget.library,
                        builder: (context, _) => IconButton(
                          key: const ValueKey('detail-collect'),
                          tooltip: translate(
                            widget.library.contains(comic) ? '已收藏' : '加入书架',
                            Localizations.localeOf(context),
                          ),
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
                            size: 22,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        compact ? 26 : 60,
                        compact ? 5 : 35,
                        compact ? 26 : 60,
                        35,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (stacked) ...[
                            Center(child: cover(128)),
                            const SizedBox(height: 16),
                            info(),
                          ] else
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                cover(compact ? 112 : 210),
                                SizedBox(width: compact ? 20 : 36),
                                Expanded(child: info()),
                              ],
                            ),
                          if (comic.description.isNotEmpty) ...[
                            const SizedBox(height: 18),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final style = TextStyle(
                                  fontSize: 13,
                                  height: 1.65,
                                  color: quiet(context),
                                );
                                final measure = TextPainter(
                                  text: TextSpan(
                                    text: comic.description,
                                    style: DefaultTextStyle.of(
                                      context,
                                    ).style.merge(style),
                                  ),
                                  textDirection: Directionality.of(context),
                                  textScaler: MediaQuery.textScalerOf(context),
                                  maxLines: 2,
                                )..layout(maxWidth: constraints.maxWidth);
                                final expandable = measure.didExceedMaxLines;
                                measure.dispose();
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    AnimatedSize(
                                      duration: RoomMotion.duration(
                                        context,
                                        RoomMotion.feedback,
                                      ),
                                      alignment: Alignment.topLeft,
                                      curve: RoomMotion.ease,
                                      child: LocalizedText(
                                        comic.description,
                                        maxLines: descriptionExpanded
                                            ? null
                                            : 2,
                                        overflow: descriptionExpanded
                                            ? null
                                            : TextOverflow.ellipsis,
                                        style: style,
                                      ),
                                    ),
                                    if (expandable)
                                      TextButton(
                                        onPressed: () => setState(
                                          () => descriptionExpanded =
                                              !descriptionExpanded,
                                        ),
                                        child: LocalizedText(
                                          descriptionExpanded ? '收起简介' : '展开简介',
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                          ],
                          const SizedBox(height: 18),
                          Container(
                            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerLow
                                  .withValues(alpha: .8),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            sourceName,
                                            style: const TextStyle(
                                              fontSize: 13,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          LocalizedText(
                                            stateLabel,
                                            style: small(context),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (!ready)
                                      const Padding(
                                        padding: EdgeInsets.all(12),
                                        child: SizedBox.square(
                                          dimension: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      ),
                                    if (canChangeSource && canRead)
                                      TextButton.icon(
                                        onPressed: findAnotherSource,
                                        icon: const Icon(
                                          Icons.travel_explore,
                                          size: 16,
                                        ),
                                        label: const LocalizedText('换源查找'),
                                      ),
                                  ],
                                ),
                                if (ready &&
                                    (snapshot.hasError ||
                                        noCopyright ||
                                        chapters.isEmpty)) ...[
                                  const SizedBox(height: 8),
                                  LocalizedText(
                                    noCopyright
                                        ? '${copyrightFailure.message}${chapters.isNotEmpty ? '\n已下载章节仍可离线阅读。' : ''}'
                                        : snapshot.hasError
                                        ? friendlyError(snapshot.error)
                                        : '尚未识别到章节目录，请重新加载。',
                                    style: small(context),
                                  ),
                                  TextButton.icon(
                                    onPressed: retry,
                                    icon: const Icon(Icons.refresh, size: 16),
                                    label: const LocalizedText('重试读取目录'),
                                  ),
                                ],
                              ],
                            ),
                          ),
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
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Wrap(
                                  spacing: 10,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    const LocalizedText(
                                      '章节目录',
                                      style: TextStyle(fontSize: 20),
                                    ),
                                    if (chapters.isNotEmpty)
                                      LocalizedText(
                                        '${chapters.length} 章',
                                        style: small(context),
                                      ),
                                  ],
                                ),
                              ),
                              if (chapters.isNotEmpty &&
                                  comic.sourceId != 'local')
                                IconButton(
                                  tooltip: translate(
                                    '下载章节',
                                    Localizations.localeOf(context),
                                  ),
                                  onPressed: () => selectDownloads(
                                    context,
                                    comic,
                                    chapters.reversed.toList(),
                                  ),
                                  icon: const Icon(
                                    Icons.download_outlined,
                                    size: 20,
                                  ),
                                ),
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
                                        ChapterOfflineBadge(
                                          library: widget.library,
                                          path: chapter.path,
                                        ),
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
          ),
        ),
      );
    },
  );
}

class ChapterOfflineBadge extends StatelessWidget {
  const ChapterOfflineBadge({
    super.key,
    required this.library,
    required this.path,
  });
  final Library library;
  final String path;
  @override
  Widget build(BuildContext context) {
    final offline = OfflineLibrary.instance;
    if (offline == null || !identical(offline.library, library)) {
      return const SizedBox.shrink();
    }
    return VisibleListenableBuilder(
      listenable: offline,
      builder: (context, _) {
        final entry = offline.entries
            .where((e) => e['chapter']['path'] == path)
            .firstOrNull;
        if (entry == null) return const SizedBox.shrink();
        final (label, icon) = switch (entry['status']) {
          'complete' => ('已下载', Icons.download_done),
          'failed' => ('下载失败', Icons.error_outline),
          'paused' => ('下载已暂停', Icons.pause_circle_outline),
          'downloading' => ('正在下载', Icons.downloading_outlined),
          _ => ('等待下载', Icons.schedule),
        };
        return Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Tooltip(
            key: ValueKey('offline-status-$path'),
            message: translate(label, Localizations.localeOf(context)),
            child: Icon(
              icon,
              size: 14,
              color: entry['status'] == 'failed'
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.primary,
            ),
          ),
        );
      },
    );
  }
}
