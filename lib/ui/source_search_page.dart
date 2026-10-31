import 'package:flutter/material.dart';
import '../data/comic.dart';
import '../data/library.dart';
import '../data/source_hub.dart';
import 'advanced_settings.dart';
import 'app_shell.dart' show ComicGrid, EmptyState, friendlyError, small;
import 'content_handoff.dart';
import 'localized_text.dart';
import 'chapter_match_page.dart';

/// User-selected lookups preserve source identities. No automatic replacement
/// of a favorite or its reading record, and no unconfigured remote sources.
class SourceSearchPage extends StatefulWidget {
  const SourceSearchPage({
    super.key,
    required this.comic,
    required this.library,
    required this.source,
    required this.web,
    required this.onOpen,
  });
  final Comic comic;
  final Library library;
  final SourceHub source;
  final bool web;
  final Future<void> Function(Comic) onOpen;
  @override
  State<SourceSearchPage> createState() => _SourceSearchPageState();
}

class _SourceSearchPageState extends State<SourceSearchPage> {
  late final input = TextEditingController(text: widget.comic.title);
  String? selected, error;
  String resultSource = '';
  String? resultId;
  List<Comic>? results;
  bool busy = false, opening = false, configuring = false;
  int request = 0, revision = 0;
  Map<String, String> get sources => {
    if (widget.comic.sourceId != 'dm5') 'dm5': '动漫屋',
    for (final p in widget.source.profiles)
      if (p['id'] != widget.comic.sourceId)
        p['id'] as String: p['name'] as String,
  };
  String? get active =>
      sources.containsKey(selected) ? selected : sources.keys.firstOrNull;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && active != null) search();
    });
  }

  Future<void> search() async {
    if (opening) return;
    final id = active, query = input.text.trim();
    if (id == null || query.isEmpty) return;
    final name = sources[id]!;
    final generation = ++request;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final matches = await widget.source.searchIn(id, query);
      if (!mounted || generation != request || !sources.containsKey(id)) return;
      setState(() {
        results = matches;
        resultSource = name;
        resultId = id;
        revision++;
      });
    } catch (e) {
      if (mounted && generation == request) {
        setState(() => error = friendlyError(e));
      }
    } finally {
      if (mounted && generation == request) setState(() => busy = false);
    }
  }

  Future<void> configure() async {
    if (configuring) return;
    configuring = true;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const LocalizedText('漫画源设置')),
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: AdvancedSettings(
                  library: widget.library,
                  source: widget.source,
                  web: widget.web,
                  sourceOnly: true,
                ),
              ),
            ),
          ),
        ),
      );
    } finally {
      configuring = false;
    }
  }

  Future<void> open(Comic comic) async {
    if (opening || busy) return;
    setState(() {
      opening = true;
      error = null;
    });
    try {
      final prior = widget.library.record(widget.comic);
      if (prior != null) {
        final detail = await widget.source.detail(comic);
        if (!mounted) return;
        final choice = await Navigator.push<Object>(
          context,
          MaterialPageRoute(
            builder: (_) => ChapterMatchPage(record: prior, detail: detail),
          ),
        );
        if (choice == null || !mounted) return;
        if (choice is Chapter) {
          await widget.library.save(
            ReadingRecord(
              comic: comic,
              chapterPath: choice.path,
              chapterTitle: choice.title,
              page: 0,
              total: 0,
              updatedAt: DateTime.now().millisecondsSinceEpoch,
            ),
          );
        }
      }
      await widget.onOpen(comic);
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  @override
  void dispose() {
    request++;
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const LocalizedText('换源查找'),
      actions: [
        IconButton(
          tooltip: '漫画源设置',
          onPressed: configure,
          icon: const Icon(Icons.tune),
        ),
      ],
    ),
    body: SafeArea(
      child: ListenableBuilder(
        listenable: widget.library,
        builder: (context, _) {
          final choices = sources;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(26, 16, 26, 36),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const LocalizedText(
                      '在其他书源中寻找',
                      style: TextStyle(fontSize: 22),
                    ),
                    const SizedBox(height: 10),
                    LocalizedText(
                      '按漫画名搜索，确认版本后再打开。原来的收藏与阅读位置会保留。',
                      style: small(context),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      enabled: !opening,
                      controller: input,
                      onSubmitted: (_) => search(),
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        label: const LocalizedText('漫画名'),
                        suffixIcon: IconButton(
                          tooltip: '搜索这个书源',
                          onPressed: active == null || opening ? null : search,
                          icon: const Icon(Icons.search),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (choices.isEmpty)
                      EmptyState(
                        icon: Icons.extension_outlined,
                        title: '还没有其他漫画源',
                        message: '添加你自己的漫画源，或在插件页启用书源扩展。也可以从离线页导入本地漫画。',
                        action: configure,
                        actionLabel: '配置漫画源',
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final choice in choices.entries)
                            ChoiceChip(
                              label: Text(choice.value),
                              selected: active == choice.key,
                              onSelected: opening
                                  ? null
                                  : (_) {
                                      setState(() => selected = choice.key);
                                      search();
                                    },
                            ),
                        ],
                      ),
                    ContentHandoff(
                      child: busy || opening
                          ? const Padding(
                              key: ValueKey('source-search-busy'),
                              padding: EdgeInsets.symmetric(vertical: 20),
                              child: LinearProgressIndicator(minHeight: 2),
                            )
                          : const SizedBox.shrink(
                              key: ValueKey('source-search-idle'),
                            ),
                    ),
                    ContentHandoff(
                      child: error == null
                          ? const SizedBox.shrink(
                              key: ValueKey('no-search-error'),
                            )
                          : Padding(
                              key: const ValueKey('source-search-error'),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  LocalizedText(error!, style: small(context)),
                                  TextButton.icon(
                                    onPressed: busy ? null : search,
                                    icon: const Icon(Icons.refresh, size: 16),
                                    label: const LocalizedText('重试搜索'),
                                  ),
                                ],
                              ),
                            ),
                    ),
                    if (results != null && choices.containsKey(resultId)) ...[
                      const SizedBox(height: 16),
                      Text(
                        '$resultSource · ${results!.length} 部',
                        style: small(context),
                      ),
                      const SizedBox(height: 16),
                      IgnorePointer(
                        ignoring: busy || opening,
                        child: AnimatedOpacity(
                          opacity: busy || opening ? .55 : 1,
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 180),
                          child: ContentHandoff(
                            child: results!.isEmpty
                                ? const EmptyState(
                                    key: ValueKey('no-source-matches'),
                                    icon: Icons.search_off,
                                    title: '这个书源没有找到匹配漫画',
                                    message: '试试别名，或选择其他书源。',
                                  )
                                : ComicGrid(
                                    key: ValueKey(revision),
                                    books: results!,
                                    web: widget.web,
                                    onOpen: open,
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}
