import 'localized_text.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/comic.dart';
import '../data/dm5_source.dart';
import '../data/library.dart';
import '../data/source_hub.dart';
import 'app_shell.dart';
import 'book_object.dart';
import 'collection_motion.dart';
import 'reader_page.dart';
import 'offline_page.dart';
import 'library_manager.dart';

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
  late Future<ComicDetail> detail = widget.source.detail(widget.comic);
  String group = '连载';
  bool ascending = true;
  bool enteringReader = false;
  final coverKey = GlobalKey();

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
          final comic = snapshot.data?.comic ?? widget.comic;
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
                'MANGA / 动漫屋',
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
                      history == null ? '开始阅读' : '继续阅读',
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
                                  child: BookFlight(
                                    tag: widget.flightTag,
                                    key: coverKey,
                                    child: BookObject(
                                      comic,
                                      web: widget.web,
                                      number: widget.bookNumber,
                                      opening:
                                          widget.library.option<bool>(
                                            'bookOpening',
                                            true,
                                          )
                                          ? 1
                                          : 0,
                                      bookmark: history != null,
                                    ),
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
                                      child: BookFlight(
                                        tag: widget.flightTag,
                                        key: coverKey,
                                        child: BookObject(
                                          comic,
                                          web: widget.web,
                                          number: widget.bookNumber,
                                          opening:
                                              widget.library.option<bool>(
                                                'bookOpening',
                                                true,
                                              )
                                              ? 1
                                              : 0,
                                          bookmark: history != null,
                                        ),
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
                          if (snapshot.connectionState != ConnectionState.done)
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
                              icon: Icons.cloud_off_outlined,
                              title: '目录暂时无法读取',
                              message: friendlyError(snapshot.error),
                              action: () => setState(
                                () =>
                                    detail = widget.source.detail(widget.comic),
                              ),
                              actionLabel: '重新加载',
                            )
                          else if (chapters.isEmpty)
                            const EmptyState(
                              icon: Icons.menu_book_outlined,
                              title: '原站暂未提供章节',
                              message: '可以在右上角打开动漫屋查看。',
                            ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
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
                        return SliverGrid(
                          delegate: SliverChildBuilderDelegate((context, i) {
                            final chapter = ordered[i];
                            final marked = history?.chapterPath == chapter.path;
                            return OutlinedButton(
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
                                      ? Theme.of(context).colorScheme.primary
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
                        );
                      },
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
