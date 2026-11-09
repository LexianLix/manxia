import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/comic.dart';
import '../data/dm5_source.dart';
import '../data/library.dart';
import '../data/discovery_preferences.dart';
import '../data/source_catalog.dart';
import 'localized_text.dart';
import 'app_shell.dart' show ComicGrid;
import 'content_handoff.dart';
import 'room_motion.dart';

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

class _SourceBrowserState extends State<SourceBrowser>
    with SingleTickerProviderStateMixin {
  late final arrival = AnimationController(
    vsync: this,
    duration: RoomMotion.cover,
    value: 1,
  );
  int arrivingFrom = 0;
  ScrollPosition? scroll;
  bool autoQueued = false, visible = true, loadingNext = false;

  void queueNext() {
    if (autoQueued || !mounted) return;
    autoQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      autoQueued = false;
      final position = scroll;
      if (!mounted ||
          !visible ||
          busy ||
          error != null ||
          !more ||
          catalog?.canPaginate != true ||
          position == null ||
          !position.hasContentDimensions) {
        return;
      }
      // Fetch ahead of the last visible row, with only one request in flight.
      if (position.extentAfter <= position.viewportDimension * .65) next();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) arrival.value = 1;
    visible = TickerMode.valuesOf(context).enabled;
    final position = Scrollable.maybeOf(context)?.position;
    if (!identical(position, scroll)) {
      scroll?.removeListener(queueNext);
      scroll = position;
      scroll?.addListener(queueNext);
    }
    queueNext();
  }

  @override
  void dispose() {
    scroll?.removeListener(queueNext);
    arrival.dispose();
    super.dispose();
  }

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
      loadingNext = false;
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
          arrivingFrom = result.books.length;
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
      if (mounted && generation == request) {
        setState(() => busy = false);
        queueNext();
      }
    }
  }

  Future<void> next() async {
    if (catalog == null || busy) return;
    final generation = request;
    setState(() {
      busy = true;
      loadingNext = true;
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
          if (added.isNotEmpty) arrivingFrom = books.length;
          books.addAll(added);
          if (added.isNotEmpty) {
            if (widget.library.motion &&
                !MediaQuery.disableAnimationsOf(context)) {
              arrival.forward(from: 0);
            } else {
              arrival.value = 1;
            }
          }
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
      if (mounted && generation == request) {
        setState(() {
          busy = false;
          loadingNext = false;
        });
        queueNext();
      }
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
        child: busy && !loadingNext
            ? const Padding(
                key: ValueKey('catalog-busy'),
                padding: EdgeInsets.symmetric(vertical: 18),
                child: LinearProgressIndicator(),
              )
            : const SizedBox.shrink(key: ValueKey('catalog-idle')),
      ),
      ContentHandoff(
        child: error != null && !retryNext
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
  Widget pagination() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Center(
      child: retryNext
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Flexible(
                  child: LocalizedText('加载失败', style: TextStyle(fontSize: 12)),
                ),
                TextButton(
                  key: const ValueKey('source-retry'),
                  onPressed: busy ? null : next,
                  child: const LocalizedText('重试'),
                ),
              ],
            )
          : SizedBox(
              height: 24,
              child: busy
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 1.6),
                        ),
                        SizedBox(width: 10),
                        LocalizedText('正在加载…', style: TextStyle(fontSize: 12)),
                      ],
                    )
                  : more
                  ? null
                  : const LocalizedText(
                      '已加载全部',
                      style: TextStyle(fontSize: 12),
                    ),
            ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    queueNext();
    if (widget.sliver) {
      return SliverMainAxisGroup(
        slivers: [
          SliverToBoxAdapter(child: controls(context)),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
          ComicGrid(
            discoveryActions: true,
            books: widget.library.discoveryBooks(books),
            library: widget.library,
            web: widget.web,
            onOpen: widget.onOpen,
            sliver: true,
            itemArrival: arrival,
            arrivingFrom: arrivingFrom,
          ),
          SliverToBoxAdapter(
            child: ContentHandoff(
              child: catalog?.canPaginate == true
                  ? pagination()
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
        ComicGrid(
          discoveryActions: true,
          books: widget.library.discoveryBooks(books),
          library: widget.library,
          web: widget.web,
          onOpen: widget.onOpen,
          itemArrival: arrival,
          arrivingFrom: arrivingFrom,
        ),
        ContentHandoff(
          child: catalog?.canPaginate == true
              ? pagination()
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
