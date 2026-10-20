import 'localized_text.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/comic.dart';
import '../data/discovery.dart';
import '../data/dm5_source.dart';
import '../data/library.dart';
import '../data/source_hub.dart';
import 'app_shell.dart' show ComicGrid, EmptyState, quiet, small;
import 'book_object.dart';
import 'materials.dart';
import 'source_browser.dart';

class DiscoveryPage extends StatefulWidget {
  const DiscoveryPage({
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
  State<DiscoveryPage> createState() => _DiscoveryPageState();
}

class _DiscoveryPageState extends State<DiscoveryPage> {
  late Future<Discovery> data;
  String tab = '精选', rank = '人气', query = '';
  bool authors = false, busy = false;
  final input = TextEditingController();
  List<Comic>? searchResults;
  String? error;
  int searchRequest = 0;
  String typing = '';
  bool checking = false;
  List<Comic> dailyPicks(Discovery snapshot, DateTime date) {
    final edition = widget.library.option<int>('dailyEdition', 0);
    final key = '${date.toIso8601String().substring(0, 10)}/$edition';
    final pref =
        'daily.picks.${widget.library.option<String>('source', 'dm5')}';
    try {
      final saved =
          jsonDecode(widget.library.prefs.getString(pref) ?? '{}') as Map;
      if (saved['key'] == key) {
        return (saved['books'] as List)
            .map((v) => Comic.fromJson(Map<String, dynamic>.from(v)))
            .toList();
      }
    } catch (_) {}
    final picks = snapshot.daily(date, edition: edition);
    widget.library.prefs.setString(
      pref,
      jsonEncode({'key': key, 'books': picks.map((c) => c.toJson()).toList()}),
    );
    return picks;
  }

  String get cacheKey =>
      'discovery.cache.${widget.library.option<String>('source', 'dm5')}';
  Future<Discovery> cached() async {
    final saved = widget.library.prefs.getString(cacheKey);
    if (saved != null) {
      return Discovery.fromJson(jsonDecode(saved), cached: true);
    }
    if (widget.source is SourceHub &&
        (widget.source as SourceHub).selected != null) {
      return widget.source.discover();
    }
    return Discovery.fromJson(
      jsonDecode(await rootBundle.loadString('assets/discovery.json')),
      cached: true,
    );
  }

  @override
  void initState() {
    super.initState();
    data = cached();
    refreshInBackground();
  }

  Future<void> refreshInBackground() async {
    try {
      final result = await widget.source.discover();
      await widget.library.prefs.setString(
        cacheKey,
        jsonEncode(result.toJson()),
      );
      if (mounted) {
        setState(() {
          error = null;
          data = Future.value(result);
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<Discovery> load() async {
    try {
      final result = await widget.source.discover();
      await widget.library.prefs.setString(
        cacheKey,
        jsonEncode(result.toJson()),
      );
      return result;
    } catch (e) {
      error = e.toString();
      return cached();
    }
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> search(String value) async {
    final generation = ++searchRequest;
    query = value.trim();
    if (query.isEmpty) {
      setState(() {
        searchResults = null;
        busy = false;
      });
      return;
    }
    setState(() => busy = true);
    await widget.library.rememberSearch(query);
    try {
      final result =
          authors && widget.library.option<String>('source', 'dm5') == 'dm5'
          ? Dm5Source.parseCatalog(
              await widget.source.fetchPage(
                '/search?title=${Uri.encodeComponent(query)}&f=2',
              ),
            )
          : await widget.source.search(query);
      if (mounted && generation == searchRequest) {
        setState(() {
          searchResults = result;
          error = null;
        });
      }
    } catch (e) {
      if (mounted && generation == searchRequest) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted && generation == searchRequest) setState(() => busy = false);
    }
  }

  Widget heading(String title, String sub, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LocalizedText(
                title,
                style: const TextStyle(fontSize: 30, letterSpacing: 2),
              ),
              const SizedBox(height: 8),
              LocalizedText(sub, style: small(context)),
            ],
          ),
        ),
        ?trailing,
      ],
    ),
  );
  Widget row(List<Comic> books, {int count = 12}) => SizedBox(
    height: 220,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: books.take(count).length,
      separatorBuilder: (_, _) => const SizedBox(width: 20),
      itemBuilder: (c, i) {
        final book = books[i];
        return SizedBox(
          width: 125,
          child: InkWell(
            onTap: () => widget.onOpen(book),
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
                          offset: const Offset(3, 8),
                        ),
                      ],
                    ),
                    child: SizedBox(
                      width: 125,
                      child: ComicCover(book, web: widget.web),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                LocalizedText(
                  book.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 4),
                LocalizedText(
                  book.latest.isEmpty ? '查看漫画' : book.latest,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: small(context),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
  @override
  Widget build(BuildContext context) => FutureBuilder<Discovery>(
    future: data,
    builder: (context, s) {
      if (!s.hasData) {
        if (s.hasError) {
          return EmptyState(
            icon: Icons.cloud_off,
            title: '暂时无法打开漫画源',
            message: '${s.error}',
            action: () => setState(() => data = load()),
            actionLabel: '重试',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            heading('发现漫画', '正在打开下一段故事'),
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Container(
                  height: 140,
                  decoration: BoxDecoration(
                    color: quiet(context).withValues(alpha: .06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
          ],
        );
      }
      final snapshot = s.data!;
      final date = DateTime.now().toUtc().add(const Duration(hours: 8));
      final day =
          '${date.month.toString().padLeft(2, '0')} / ${date.day.toString().padLeft(2, '0')}';
      final daily = dailyPicks(snapshot, date);
      final ranks =
          snapshot.ranks[rank] ?? snapshot.ranks.values.firstOrNull ?? [];
      final updated = snapshot.sections['万人追更'] ?? [];
      return EntryReveal(
        enabled: widget.library.motion,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            heading(
              '发现漫画',
              '今天，也有值得翻开的故事。',
              trailing: IconButton(
                tooltip: '刷新发现页',
                onPressed: () => setState(() {
                  error = null;
                  data = load();
                }),
                icon: const Icon(Icons.refresh, size: 20),
              ),
            ),
            TextField(
              controller: input,
              onSubmitted: search,
              onChanged: (v) => setState(() => typing = v.trim()),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hint: LocalizedText(authors ? '搜索漫画作者' : '搜索漫画名称'),
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: IconButton(
                  tooltip: '开始搜索',
                  onPressed: () => search(input.text),
                  icon: const Icon(Icons.arrow_forward, size: 20),
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (typing.isNotEmpty && typing != query)
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final book
                      in snapshot.books
                          .where(
                            (b) => b.title.toLowerCase().contains(
                              typing.toLowerCase(),
                            ),
                          )
                          .take(5))
                    ActionChip(
                      label: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 190),
                        child: LocalizedText(
                          book.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      onPressed: () {
                        input.text = book.title;
                        search(book.title);
                      },
                    ),
                ],
              ),
            Row(
              children: [
                FilterChip(
                  label: const LocalizedText(
                    '按作者搜索',
                    style: TextStyle(fontSize: 11),
                  ),
                  selected: authors,
                  onSelected:
                      widget.library.option<String>('source', 'dm5') == 'dm5'
                      ? (v) => setState(() => authors = v)
                      : null,
                ),
                const Spacer(),
                if (searchResults != null)
                  TextButton(
                    onPressed: () {
                      input.clear();
                      setState(() {
                        query = '';
                        searchResults = null;
                      });
                    },
                    child: const LocalizedText('返回发现'),
                  ),
              ],
            ),
            if (widget.library.searchHistory.isNotEmpty && query.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Wrap(
                  spacing: 7,
                  runSpacing: 5,
                  children: widget.library.searchHistory
                      .take(6)
                      .map(
                        (q) => ActionChip(
                          label: LocalizedText(
                            q,
                            style: const TextStyle(fontSize: 11),
                          ),
                          onPressed: () {
                            input.text = q;
                            search(q);
                          },
                        ),
                      )
                      .toList(),
                ),
              ),
            if (busy)
              const Padding(
                padding: EdgeInsets.all(35),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (query.isNotEmpty) ...[
              const SizedBox(height: 12),
              LocalizedText(
                '“$query”的搜索结果',
                style: const TextStyle(fontSize: 22),
              ),
              const SizedBox(height: 20),
              if (error != null)
                EmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: '搜索暂时不可用',
                  message: error!,
                  action: () => search(query),
                  actionLabel: '重新搜索',
                )
              else if (searchResults?.isEmpty ?? true)
                const EmptyState(
                  icon: Icons.search_off,
                  title: '没有找到漫画',
                  message: '试试更短的关键词。',
                )
              else
                ComicGrid(
                  books: searchResults!,
                  web: widget.web,
                  onOpen: widget.onOpen,
                ),
            ] else ...[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final label in ['精选', '排行', '更新', '分类', '书单'])
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: ChoiceChip(
                          label: LocalizedText(
                            label,
                            style: const TextStyle(fontSize: 12),
                          ),
                          selected: tab == label,
                          onSelected: (_) => setState(() => tab = label),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              if (snapshot.cached)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Row(
                    children: [
                      Icon(
                        Icons.offline_bolt_outlined,
                        size: 14,
                        color: quiet(context),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: LocalizedText(
                          '来源暂不可达 · 展示 ${snapshot.capturedAt.substring(0, 10)} 的目录快照',
                          style: small(context),
                        ),
                      ),
                    ],
                  ),
                ),
              if (tab == '精选') ...[
                Row(
                  children: [
                    const LocalizedText('每日精选', style: TextStyle(fontSize: 23)),
                    const SizedBox(width: 12),
                    LocalizedText(day, style: small(context)),
                    const Spacer(),
                    TextButton(
                      onPressed: () async {
                        await widget.library.setOption(
                          'dailyEdition',
                          widget.library.option<int>('dailyEdition', 0) + 1,
                        );
                        if (mounted) setState(() {});
                      },
                      child: const LocalizedText(
                        '换一组',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                if (daily.isNotEmpty) _dailyHero(daily.first, day),
                const SizedBox(height: 24),
                row(daily.skip(1).toList()),
                const SizedBox(height: 28),
                _sectionTitle(
                  '人气正在上升',
                  '来源：动漫屋人气榜',
                  () => setState(() => tab = '排行'),
                ),
                row((snapshot.ranks['人气'] ?? [])),
                const SizedBox(height: 28),
                _sectionTitle('你可能还喜欢', '根据本机收藏题材与未收藏作品选取', null),
                row(
                  snapshot.forYou([
                    ...widget.library.favorites,
                    ...widget.library.history.map((r) => r.comic),
                  ]),
                ),
              ],
              if (tab == '排行') ...[
                _sectionTitle('故事的人气榜', '按动漫屋原始顺序；不虚构热度数字', null),
                Wrap(
                  spacing: 8,
                  children: snapshot.ranks.keys
                      .map(
                        (r) => ChoiceChip(
                          label: LocalizedText(r),
                          selected: r == rank,
                          onSelected: (_) => setState(() => rank = r),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 18),
                for (final entry in ranks.indexed)
                  _rankRow(entry.$2, entry.$1 + 1),
              ],
              if (tab == '更新') ...[
                _sectionTitle(
                  '收藏追更',
                  checking ? '正在检查收藏…' : '检查收藏是否出现新章节',
                  checking ? null : () => checkUpdates(),
                ),
                for (final book in widget.library.favorites.where(
                  (b) => widget.library.updates[b.path]?['changed'] == true,
                ))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: LocalizedText(book.title),
                    subtitle: LocalizedText(
                      '新章 · ${widget.library.updates[book.path]!['latest']}',
                    ),
                    trailing: const Icon(Icons.bookmark_added_outlined),
                    onTap: () => widget.onOpen(book),
                  ),
                _sectionTitle('最近更新', '来源：动漫屋更新栏目', null),
                ComicGrid(
                  books: updated,
                  web: widget.web,
                  onOpen: widget.onOpen,
                ),
              ],
              if (tab == '分类')
                if (widget.library.option<String>('source', 'dm5') == 'dm5')
                  SourceBrowser(
                    source: widget.source,
                    library: widget.library,
                    web: widget.web,
                    onOpen: widget.onOpen,
                  )
                else
                  ComicGrid(
                    books: snapshot.books,
                    web: widget.web,
                    onOpen: widget.onOpen,
                  ),
              if (tab == '书单') ...[
                for (final group in widget.library.groups.where(
                  (g) => g != '全部',
                )) ...[
                  _sectionTitle(group, '我的主题书单', null),
                  row(
                    widget.library.favorites
                        .where((b) => widget.library.meta(b)['group'] == group)
                        .toList(),
                  ),
                  const SizedBox(height: 28),
                ],
                _sectionTitle('完结佳作', '来源完结栏目', null),
                row(snapshot.sections['完结佳作'] ?? []),
                const SizedBox(height: 28),
              ],
              if (tab == '书单')
                for (final entry in snapshot.sections.entries) ...[
                  _sectionTitle(
                    entry.key,
                    '${entry.value.length} 部 · 动漫屋栏目书单',
                    null,
                  ),
                  row(entry.value),
                  const SizedBox(height: 28),
                ],
              const SizedBox(height: 20),
              LocalizedText(
                '每日精选按日期与目录稳定选取；个人推荐只使用本机记录。',
                style: small(context),
              ),
            ],
          ],
        ),
      );
    },
  );
  Widget _sectionTitle(String title, String subtitle, VoidCallback? more) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LocalizedText(title, style: const TextStyle(fontSize: 23)),
                  const SizedBox(height: 7),
                  LocalizedText(subtitle, style: small(context)),
                ],
              ),
            ),
            if (more != null)
              IconButton(
                tooltip: '查看或刷新',
                onPressed: more,
                icon: const Icon(Icons.arrow_forward, size: 18),
              ),
          ],
        ),
      );
  Widget _dailyHero(Comic comic, String day) => MilkGlass(
    radius: 12,
    high: widget.library.option<String>('quality', 'high') == 'high',
    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
    child: InkWell(
      onTap: () => widget.onOpen(comic),
      child: Row(
        children: [
          SizedBox(
            width: 125,
            height: 180,
            child: BookObject(comic, web: widget.web),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LocalizedText('今日的一册 / $day', style: small(context)),
                const SizedBox(height: 16),
                LocalizedText(
                  comic.title,
                  style: const TextStyle(fontSize: 24, height: 1.5),
                ),
                const SizedBox(height: 20),
                const LocalizedText(
                  '翻开故事  ↗',
                  style: TextStyle(fontSize: 12, color: Color(0xff47775e)),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  Widget _rankRow(Comic comic, int place) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: InkWell(
      onTap: () => widget.onOpen(comic),
      child: Row(
        children: [
          SizedBox(
            width: 45,
            child: LocalizedText(
              place.toString().padLeft(2, '0'),
              style: TextStyle(
                fontSize: 28,
                color: place <= 3
                    ? Theme.of(context).colorScheme.primary
                    : quiet(context),
              ),
            ),
          ),
          SizedBox(
            width: 60,
            height: 80,
            child: ComicCover(comic, web: widget.web),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: LocalizedText(
              comic.title,
              style: const TextStyle(fontSize: 16),
            ),
          ),
          const Icon(Icons.north_east, size: 18),
        ],
      ),
    ),
  );
  Future<void> checkUpdates() async {
    if (checking) return;
    setState(() => checking = true);
    var failed = 0;
    final list = widget.library.favorites
        .where((c) => c.sourceId != 'local')
        .toList();
    for (var i = 0; i < list.length; i += 3) {
      if (!mounted) break;
      await Future.wait(
        list.skip(i).take(3).map((book) async {
          try {
            final detail = await widget.source.detail(book);
            final prior = widget.library.updates[book.path];
            final latest = detail.comic.latest.isNotEmpty
                ? detail.comic.latest
                : detail.chapters.firstOrNull?.title ?? '';
            final fingerprint = detail.chapters.firstOrNull?.path ?? latest;
            final changed =
                prior != null &&
                (prior['fingerprint'] ?? prior['latest']) != fingerprint;
            final now = DateTime.now().millisecondsSinceEpoch;
            widget.library.updates[book.path] = {
              'latest': latest,
              'fingerprint': fingerprint,
              'changed': prior?['changed'] == true || changed,
              'checkedAt': now,
              'updatedAt': changed ? now : prior?['updatedAt'] ?? 0,
            };
          } catch (_) {
            failed++;
          }
        }),
      );
    }
    await widget.library.persistFeatures();
    if (mounted) {
      setState(() => checking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText(
            failed > 0 ? '检查完成，$failed 部漫画暂时无法连接' : '追更检查完成',
          ),
        ),
      );
    }
  }
}
