import 'package:flutter/material.dart';
import '../data/comic.dart';
import '../data/dm5_source.dart';
import '../data/library.dart';
import 'app_shell.dart' show ComicGrid, EmptyState, friendlyError;
import 'localized_text.dart';
import 'content_handoff.dart';
import 'sliver_handoff.dart';

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
  bool busy = false, authors = false;
  int generation = 0, revision = 0;
  Future<void> search([String? value]) async {
    final requested = (value ?? input.text).trim();
    if (requested.isEmpty) return;
    input.text = requested;
    focus.unfocus();
    final current = ++generation, byAuthor = authors;
    setState(() {
      query = requested;
      busy = true;
      error = null;
    });
    await widget.library.rememberSearch(requested);
    if (!mounted || current != generation) return;
    try {
      final books = byAuthor
          ? Dm5Source.parseCatalog(
              await widget.source.fetchPage(
                '/search?title=${Uri.encodeComponent(requested)}&f=2',
              ),
            )
          : await widget.source.search(requested);
      if (mounted && current == generation) {
        setState(() {
          results = books;
          resultQuery = requested;
          revision++;
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
      busy = false;
    });
    focus.requestFocus();
  }

  @override
  void dispose() {
    generation++;
    input.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
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
                                icon: const Icon(Icons.arrow_forward, size: 20),
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
                                onSelected: (_) =>
                                    setState(() => authors = false),
                              ),
                              ChoiceChip(
                                label: const LocalizedText('作者'),
                                selected: authors,
                                onSelected: (_) =>
                                    setState(() => authors = true),
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
                                      in widget.library.searchHistory.take(12))
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
                      ContentHandoff(
                        child: busy
                            ? const Padding(
                                key: ValueKey('search-busy'),
                                padding: EdgeInsets.only(top: 14),
                                child: LinearProgressIndicator(minHeight: 2),
                              )
                            : const SizedBox(key: ValueKey('search-idle')),
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
                              'count': results?.length ?? 0,
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
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 36),
                sliver: SliverHandoff(
                  identity: revision,
                  animate: widget.library.motion,
                  sliver: results == null
                      ? const SliverToBoxAdapter(child: SizedBox())
                      : results!.isEmpty
                      ? const SliverToBoxAdapter(
                          child: EmptyState(
                            icon: Icons.search_off,
                            title: '没有找到漫画',
                            message: '试试更短的关键词。',
                          ),
                        )
                      : SliverIgnorePointer(
                          ignoring: busy,
                          sliver: SliverOpacity(
                            opacity: busy ? .55 : 1,
                            sliver: ComicGrid(
                              books: results!,
                              web: widget.web,
                              onOpen: widget.onOpen,
                              sliver: true,
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
