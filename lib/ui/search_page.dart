import 'package:flutter/material.dart';
import '../data/comic.dart';
import '../data/dm5_source.dart';
import '../data/library.dart';
import '../data/search_relevance.dart';
import '../data/source_hub.dart';
import 'app_shell.dart' show ComicGrid, EmptyState, friendlyError;
import 'book_link.dart';
import 'room_motion.dart';
import 'localized_text.dart';
import 'sliver_handoff.dart';
import 'visible_listenable_builder.dart';
import 'scroll_arrival.dart';

class ComicSearchPage extends StatefulWidget {
  const ComicSearchPage({
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
  State<ComicSearchPage> createState() => _ComicSearchState();
}

class _ComicSearchState extends State<ComicSearchPage> {
  final input = TextEditingController(), focus = FocusNode();
  List<Comic>? results;
  String query = '', resultQuery = '';
  String? error;
  Map<String, Object> failedSources = {};
  bool busy = false, authors = false;
  bool allSources = true, groupedResults = false;
  int generation = 0, revision = 0;
  SourceHub? get hub =>
      widget.source is SourceHub ? widget.source as SourceHub : null;

  Future<void> search([String? value, Set<String>? retrySources]) async {
    final requested = (value ?? input.text).trim();
    if (requested.isEmpty) return;
    input.text = requested;
    focus.unfocus();
    final current = ++generation, byAuthor = authors;
    final names = hub?.sourceNames ?? const <String, String>{};
    final across = !byAuthor && allSources && names.length > 1;
    final retained = retrySources == null
        ? <Comic>[]
        : List<Comic>.from(results ?? []);
    var received = retrySources != null;
    void accept(SourceSearchResult batch) {
      if (!mounted || current != generation) return;
      final incoming = relevantComics([...retained, ...batch.books], requested);
      final byId = {
        for (final book in incoming) '${book.sourceId}/${book.path}': book,
      };
      final stable = received
          ? [
              for (final book in results ?? <Comic>[])
                if (byId.containsKey('${book.sourceId}/${book.path}'))
                  byId.remove('${book.sourceId}/${book.path}')!,
              ...byId.values,
            ]
          : incoming;
      setState(() {
        if (!received) revision++;
        received = true;
        results = stable;
        resultQuery = requested;
        groupedResults = true;
        failedSources = Map.from(batch.failures);
      });
    }

    setState(() {
      query = requested;
      busy = true;
      error = null;
      failedSources = {};
    });
    try {
      await widget.library.rememberSearch(requested);
      if (!mounted || current != generation) return;
      final batch = across
          ? await hub!.searchAcross(
              retrySources ?? names.keys,
              requested,
              isCurrent: () => mounted && current == generation,
              onProgress: accept,
            )
          : null;
      final books =
          batch?.books ??
          (byAuthor
              ? Dm5Source.parseCatalog(
                  await widget.source.fetchPage(
                    '/search?title=${Uri.encodeComponent(requested)}&f=2',
                  ),
                )
              : await widget.source.search(requested));
      if (mounted && current == generation) {
        if (batch != null) accept(batch);
        setState(() {
          if (batch == null) {
            results = byAuthor ? books : relevantComics(books, requested);
            groupedResults = false;
            revision++;
          } else {
            if (batch.failures.length ==
                    (retrySources?.length ?? names.length) &&
                (results?.isEmpty ?? true)) {
              error = friendlyError(batch.failures.values.first);
            }
          }
          resultQuery = requested;
        });
      }
    } catch (e) {
      if (mounted && current == generation) {
        setState(() => error = friendlyError(e));
      }
    } finally {
      if (mounted && current == generation) setState(() => busy = false);
    }
  }

  void clear() {
    generation++;
    input.clear();
    setState(() {
      query = '';
      results = null;
      error = null;
      failedSources = {};
      busy = false;
    });
    focus.requestFocus();
  }

  void selectMode(bool value) {
    if (authors == value) return;
    generation++;
    setState(() {
      authors = value;
      busy = false;
      error = null;
      failedSources = {};
    });
    if (query.isNotEmpty) search(query);
  }

  @override
  void dispose() {
    generation++;
    input.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => VisibleListenableBuilder(
    listenable: widget.library,
    builder: (context, _) => buildResults(context),
  );
  Widget buildResults(BuildContext context) {
    final names = hub?.sourceNames ?? const <String, String>{};
    final books = results == null
        ? null
        : widget.library.browseBooks([
            for (final comic in results!)
              if (!groupedResults || names.containsKey(comic.sourceId)) comic,
          ]);
    final groups = groupedResults && books != null
        ? groupSearchComics(books)
        : null;
    return Scaffold(
      appBar: AppBar(title: const LocalizedText('搜索漫画')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: CustomScrollView(
              key: const PageStorageKey('comic-search-scroll'),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: input,
                          focusNode: focus,
                          autofocus: true,
                          onSubmitted: search,
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hint: LocalizedText(authors ? '搜索漫画作者' : '搜索漫画名称'),
                            prefixIcon: const Icon(Icons.search, size: 20),
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: translate(
                                    '清除搜索',
                                    Localizations.localeOf(context),
                                  ),
                                  onPressed: clear,
                                  icon: const Icon(Icons.close, size: 18),
                                ),
                                IconButton(
                                  tooltip: translate(
                                    '开始搜索',
                                    Localizations.localeOf(context),
                                  ),
                                  onPressed: () => search(),
                                  icon: const Icon(
                                    Icons.arrow_forward,
                                    size: 20,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (widget.library.option<String>('source', 'dm5') ==
                            'dm5')
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Wrap(
                              spacing: 8,
                              children: [
                                ChoiceChip(
                                  label: const LocalizedText('漫画名称'),
                                  selected: !authors,
                                  onSelected: (_) => selectMode(false),
                                ),
                                ChoiceChip(
                                  label: const LocalizedText('作者'),
                                  selected: authors,
                                  onSelected: (_) => selectMode(true),
                                ),
                              ],
                            ),
                          ),
                        if (query.isEmpty)
                          ListenableBuilder(
                            listenable: widget.library,
                            builder: (context, _) => Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 24),
                                Row(
                                  children: [
                                    const Expanded(
                                      child: LocalizedText(
                                        '最近搜索',
                                        style: TextStyle(fontSize: 15),
                                      ),
                                    ),
                                    if (widget.library.searchHistory.isNotEmpty)
                                      TextButton(
                                        onPressed: () =>
                                            widget.library.clearSearchHistory(),
                                        child: const LocalizedText('清空'),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                if (widget.library.searchHistory.isEmpty)
                                  const LocalizedText(
                                    '输入漫画名或作者，寻找下一段故事。',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final term
                                        in widget.library.searchHistory.take(
                                          12,
                                        ))
                                      ActionChip(
                                        label: Text(
                                          term,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        onPressed: () => search(term),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Wrap(
                            spacing: 8,
                            children: [
                              if (!authors && names.length > 1)
                                FilterChip(
                                  label: const LocalizedText('所有已启用书源'),
                                  selected: allSources,
                                  onSelected: (value) {
                                    setState(() => allSources = value);
                                    if (query.isNotEmpty) search(query);
                                  },
                                ),
                              FilterChip(
                                label: const LocalizedText('隐藏不可读'),
                                tooltip: translate(
                                  '仅影响在线浏览；状态保留 24 小时，收藏和离线章节始终保留',
                                  Localizations.localeOf(context),
                                ),
                                selected: widget.library.option<bool>(
                                  'hideUnavailable',
                                  false,
                                ),
                                onSelected: (value) => widget.library.setOption(
                                  'hideUnavailable',
                                  value,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          height: 18,
                          child: busy
                              ? const Align(
                                  alignment: Alignment.bottomCenter,
                                  child: LinearProgressIndicator(minHeight: 2),
                                )
                              : const SizedBox.shrink(),
                        ),
                        if (query.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: LocalizedText(
                              '“{query}” · {count} 部',
                              arguments: {
                                'query': resultQuery.isEmpty
                                    ? query
                                    : resultQuery,
                                'count': groups?.length ?? books?.length ?? 0,
                              },
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        if (error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const LocalizedText(
                                  '搜索暂时不可用',
                                  style: TextStyle(fontSize: 14),
                                ),
                                LocalizedText(
                                  error!,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                TextButton(
                                  onPressed: busy ? null : () => search(query),
                                  child: const LocalizedText('重新搜索'),
                                ),
                              ],
                            ),
                          ),
                        if (query.isNotEmpty && error == null)
                          SizedBox(
                            height: 48,
                            child: failedSources.isEmpty
                                ? Align(
                                    alignment: Alignment.centerLeft,
                                    child: LocalizedText(
                                      busy ? '正在查询书源…' : '书源查询完成',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  )
                                : Row(
                                    children: [
                                      Expanded(
                                        child: LocalizedText(
                                          '部分书源失败：{sources}',
                                          arguments: {
                                            'sources': failedSources.keys
                                                .map((id) => names[id] ?? id)
                                                .join('、'),
                                          },
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: translate(
                                          '重试失败的书源',
                                          Localizations.localeOf(context),
                                        ),
                                        onPressed: busy
                                            ? null
                                            : () => search(
                                                query,
                                                failedSources.keys.toSet(),
                                              ),
                                        icon: const Icon(
                                          Icons.refresh,
                                          size: 20,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 36),
                  sliver: SliverHandoff(
                    identity: revision,
                    animate: widget.library.motion && !groupedResults,
                    sliver: books == null || busy && books.isEmpty
                        ? const SliverToBoxAdapter(child: SizedBox())
                        : books.isEmpty
                        ? SliverToBoxAdapter(
                            child: EmptyState(
                              icon: Icons.search_off,
                              title: '没有找到漫画',
                              message: results!.isNotEmpty
                                  ? '结果中的作品已隐藏，可关闭不可读筛选查看。'
                                  : '试试更短的关键词。',
                            ),
                          )
                        : SliverIgnorePointer(
                            ignoring: busy && resultQuery != query,
                            sliver: SliverOpacity(
                              opacity: busy && resultQuery != query ? .55 : 1,
                              sliver: groups == null
                                  ? ComicGrid(
                                      books: books,
                                      library: widget.library,
                                      web: widget.web,
                                      onOpen: widget.onOpen,
                                      sliver: true,
                                    )
                                  : SliverList.builder(
                                      itemCount: groups.length,
                                      itemBuilder: (context, index) =>
                                          _SourceResult(
                                            key: ValueKey((
                                              groups[index].first.path,
                                              groups[index].first.sourceId,
                                            )),
                                            variants: groups[index],
                                            names: names,
                                            web: widget.web,
                                            onOpen: widget.onOpen,
                                          ),
                                    ),
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SourceResult extends StatelessWidget {
  const _SourceResult({
    super.key,
    required this.variants,
    required this.names,
    required this.web,
    required this.onOpen,
  });

  final List<Comic> variants;
  final Map<String, String> names;
  final bool web;
  final ValueChanged<Comic> onOpen;

  Widget sourceRow(Comic comic, {required bool showTitle}) => BookLink(
    comic: comic,
    web: web,
    onOpen: onOpen,
    builder: (cover, open) => ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(width: 38, height: 52, child: cover),
      ),
      title: Text(showTitle ? comic.title : names[comic.sourceId]!),
      subtitle: Text(
        [
          if (showTitle && comic.author.isNotEmpty) comic.author,
          if (showTitle) names[comic.sourceId]!,
          if (comic.latest.isNotEmpty) comic.latest,
        ].join(' · '),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: open,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final comic = variants.first;
    return ScrollArrival(
      identity: '${comic.sourceId}/${comic.path}',
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Theme.of(context).dividerColor),
        ),
        margin: const EdgeInsets.only(bottom: 8),
        child: variants.length == 1
            ? sourceRow(comic, showTitle: true)
            : BookLink(
                comic: comic,
                web: web,
                onOpen: onOpen,
                builder: (cover, open) => ExpansionTile(
                  shape: const Border(),
                  collapsedShape: const Border(),
                  key: PageStorageKey((
                    'search-variants',
                    comic.sourceId,
                    comic.path,
                  )),
                  leading: InkWell(
                    onTap: open,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(width: 38, height: 52, child: cover),
                    ),
                  ),
                  title: Text(comic.title),
                  subtitle: LocalizedText(
                    '{author} · {count} 个来源',
                    arguments: {
                      'author': comic.author,
                      'count': variants.length,
                    },
                  ),
                  expansionAnimationStyle:
                      MediaQuery.disableAnimationsOf(context)
                      ? AnimationStyle.noAnimation
                      : const AnimationStyle(
                          duration: RoomMotion.feedback,
                          curve: RoomMotion.ease,
                        ),
                  children: [
                    for (final variant in variants)
                      sourceRow(variant, showTitle: false),
                  ],
                ),
              ),
      ),
    );
  }
}
