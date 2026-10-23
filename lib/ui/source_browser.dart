import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/comic.dart';
import '../data/dm5_source.dart';
import '../data/library.dart';
import '../data/source_catalog.dart';
import 'localized_text.dart';
import 'app_shell.dart' show ComicGrid;
import 'content_handoff.dart';

class SourceBrowser extends StatefulWidget {
  const SourceBrowser({
    super.key,
    required this.source,
    required this.library,
    required this.web,
    required this.onOpen,
    this.sliver = false,
    this.initialPath,
    this.initialBooks = const [],
  });
  final Dm5Source source;
  final Library library;
  final bool web, sliver;
  final ValueChanged<Comic> onOpen;
  final String? initialPath;
  final List<Comic> initialBooks;
  @override
  State<SourceBrowser> createState() => _SourceBrowserState();
}

class _SourceBrowserState extends State<SourceBrowser> {
  Map<String, String> categories = {};
  SourceCatalog? catalog;
  final List<Comic> books = [];
  String genre = '', path = '', order = '最热门', status = '全部';
  int page = 1, request = 0;
  bool busy = false, more = true, retryNext = false;
  String? error;
  @override
  void initState() {
    super.initState();
    books.addAll(widget.initialBooks);
    initialize();
  }

  Future<void> initialize() async {
    if (widget.initialPath != null) {
      await load(widget.initialPath!);
      return;
    }
    try {
      categories = await widget.source.categories();
    } catch (_) {
      categories = Map<String, String>.from(
        jsonDecode(await rootBundle.loadString('assets/categories.json')),
      );
    }
    if (!mounted) return;
    if (categories.isNotEmpty) {
      genre = categories.keys.first;
      load(categories.values.first);
    } else {
      setState(() => error = '来源未提供可读取的分类。');
    }
  }

  Future<void> load(String selected) async {
    final generation = ++request;
    setState(() {
      busy = true;
      error = null;
      retryNext = false;
      path = selected;
      page = 1;
      more = true;
    });
    try {
      final result = await widget.source.catalog(selected);
      await widget.library.prefs.setString(
        'catalog.$selected',
        jsonEncode(result.books.map((c) => c.toJson()).toList()),
      );
      if (mounted && generation == request) {
        setState(() {
          catalog = result;
          books
            ..clear()
            ..addAll(result.books);
        });
      }
    } catch (e) {
      if (mounted && generation == request) {
        setState(() {
          error = '$e';
          final saved = widget.library.prefs.getString('catalog.$selected');
          books
            ..clear()
            ..addAll(saved == null ? widget.initialBooks : Comic.decode(saved));
          catalog = null;
        });
      }
    } finally {
      if (mounted && generation == request) setState(() => busy = false);
    }
  }

  Future<void> next() async {
    if (catalog == null || busy) return;
    final generation = request;
    setState(() {
      busy = true;
      error = null;
      retryNext = false;
    });
    try {
      final result = await widget.source.catalogNext(
        catalog!.parameters,
        page + 1,
      );
      if (mounted && generation == request) {
        setState(() {
          final seen = books.map((b) => b.path).toSet();
          final added = result.where((c) => seen.add(c.path)).toList();
          books.addAll(added);
          more = added.isNotEmpty;
          page++;
        });
      }
    } catch (e) {
      if (mounted && generation == request) {
        setState(() {
          error = '$e';
          retryNext = true;
        });
      }
    } finally {
      if (mounted && generation == request) setState(() => busy = false);
    }
  }

  Widget controls(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (widget.initialPath == null) ...[
        const LocalizedText('按题材探索', style: TextStyle(fontSize: 23)),
        const SizedBox(height: 8),
        const LocalizedText('选一个喜欢的题材，慢慢找。', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 18),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: categories.entries
              .map(
                (e) => ChoiceChip(
                  label: LocalizedText(
                    e.key,
                    style: const TextStyle(fontSize: 12),
                  ),
                  selected: genre == e.key,
                  onSelected: (_) {
                    genre = e.key;
                    order = '最热门';
                    status = '全部';
                    load(e.value);
                  },
                ),
              )
              .toList(),
        ),
      ],
      const SizedBox(height: 14),
      if (catalog != null)
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in catalog!.sorts.entries)
              ChoiceChip(
                label: LocalizedText(e.key),
                selected: order == e.key,
                onSelected: (_) {
                  order = e.key;
                  load(e.value);
                },
              ),
            for (final e in catalog!.statuses.entries)
              FilterChip(
                label: LocalizedText(e.key),
                selected: status == e.key,
                onSelected: (_) {
                  status = e.key;
                  load(e.value);
                },
              ),
          ],
        ),
      ContentHandoff(
        child: busy
            ? const Padding(
                key: ValueKey('catalog-busy'),
                padding: EdgeInsets.symmetric(vertical: 18),
                child: LinearProgressIndicator(),
              )
            : const SizedBox.shrink(key: ValueKey('catalog-idle')),
      ),
      ContentHandoff(
        child: error != null
            ? Padding(
                key: const ValueKey('catalog-error'),
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '来源暂不可达，已有缓存会继续显示。\n$error',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    TextButton(
                      key: const ValueKey('source-retry'),
                      onPressed: busy
                          ? null
                          : retryNext
                          ? next
                          : () => load(path),
                      child: const LocalizedText('重试'),
                    ),
                  ],
                ),
              )
            : const SizedBox.shrink(key: ValueKey('catalog-no-error')),
      ),
    ],
  );
  Widget loadMore() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Center(
      child: OutlinedButton(
        onPressed: busy ? null : next,
        child: ContentHandoff(
          child: LocalizedText(busy ? '正在加载…' : '加载更多', key: ValueKey(busy)),
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    if (widget.sliver) {
      return SliverMainAxisGroup(
        slivers: [
          SliverToBoxAdapter(child: controls(context)),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
          ComicGrid(
            books: books,
            web: widget.web,
            onOpen: widget.onOpen,
            sliver: true,
          ),
          SliverToBoxAdapter(
            child: ContentHandoff(
              child: catalog?.canPaginate == true && more
                  ? loadMore()
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        controls(context),
        const SizedBox(height: 20),
        ComicGrid(books: books, web: widget.web, onOpen: widget.onOpen),
        ContentHandoff(
          child: catalog?.canPaginate == true && more
              ? loadMore()
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
