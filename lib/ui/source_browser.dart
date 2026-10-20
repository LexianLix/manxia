import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/comic.dart';
import '../data/dm5_source.dart';
import '../data/library.dart';
import '../data/source_catalog.dart';
import 'localized_text.dart';
import 'app_shell.dart' show ComicGrid;

class SourceBrowser extends StatefulWidget {
  const SourceBrowser({
    super.key,
    required this.source,
    required this.library,
    required this.web,
    required this.onOpen,
  });
  final Dm5Source source;
  final Library library;
  final bool web;
  final ValueChanged<Comic> onOpen;
  @override
  State<SourceBrowser> createState() => _SourceBrowserState();
}

class _SourceBrowserState extends State<SourceBrowser> {
  Map<String, String> categories = {};
  SourceCatalog? catalog;
  final List<Comic> books = [];
  String genre = '', path = '', order = '最热门', status = '全部';
  int page = 1, request = 0;
  bool busy = false, more = true;
  String? error;
  @override
  void initState() {
    super.initState();
    initialize();
  }

  Future<void> initialize() async {
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
            ..addAll(saved == null ? <Comic>[] : Comic.decode(saved));
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
    setState(() => busy = true);
    try {
      final result = await widget.source.catalogNext(
        catalog!.parameters,
        page + 1,
      );
      if (mounted && generation == request) {
        setState(() {
          final seen = books.map((b) => b.path).toSet();
          books.addAll(result.where((c) => seen.add(c.path)));
          more = result.isNotEmpty;
          page++;
        });
      }
    } catch (e) {
      if (mounted && generation == request) setState(() => error = '$e');
    } finally {
      if (mounted && generation == request) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const LocalizedText('按题材探索', style: TextStyle(fontSize: 23)),
      const SizedBox(height: 8),
      const LocalizedText(
        '题材、状态与排序使用动漫屋实际筛选链接。',
        style: TextStyle(fontSize: 12),
      ),
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
      if (busy)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: LinearProgressIndicator(),
        ),
      if (error != null)
        Padding(
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
                onPressed: () => load(path),
                child: const LocalizedText('重试'),
              ),
            ],
          ),
        ),
      const SizedBox(height: 20),
      ComicGrid(books: books, web: widget.web, onOpen: widget.onOpen),
      if (catalog != null && more)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: OutlinedButton(
              onPressed: busy ? null : next,
              child: const LocalizedText('加载更多'),
            ),
          ),
        ),
    ],
  );
}
