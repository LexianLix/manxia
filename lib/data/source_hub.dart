import 'dart:convert';
import 'package:http/http.dart' as http;
import 'comic.dart';
import 'discovery.dart';
import 'dm5_source.dart';
import 'library.dart';
import 'source_profile.dart';
import 'plugin.dart';
import 'script_source.dart';
import 'source_catalog.dart';
import 'builtin_source.dart';
export 'source_profile.dart';

typedef SourceSearchResult = ({
  List<Comic> books,
  Map<String, Object> failures,
});

class SourceHub extends Dm5Source {
  SourceHub(
    this.library, {
    super.gateway,
    http.Client? transport,
    ScriptSourceRuntime? scripts,
    this.adapters,
  }) : transport = transport ?? http.Client(),
       scripts = scripts ?? ScriptSourceRuntime() {
    refreshImageOrigins();
    onDetailStatus = (comic, error) async {
      if (error == null ||
          error is SourceCopyrightException ||
          error is SourceEntryException) {
        await library.recordSourceStatus(
          comic,
          error is SourceCopyrightException
              ? 'copyright'
              : error is SourceEntryException
              ? 'missing'
              : null,
          message: error?.message ?? '',
        );
      }
    };
  }
  final Library library;
  final http.Client transport;
  final ScriptSourceRuntime scripts;
  final Map<String, BuiltinSource>? adapters;
  late final builtins =
      adapters ??
      {
        for (final id in BuiltinSource.names.keys)
          id: BuiltinSource(id, transport, gateway: gateway),
      };
  String get selectedId =>
      _fixedSource ?? library.option<String>('source', 'dm5');
  bool get hasCatalogBrowser =>
      selectedId == 'dm5' ||
      builtins.containsKey(selectedId) ||
      selected?.json['pagination'] == true;
  Uri originalUrl(String path) {
    final id = BuiltinSource.sourceId(path);
    if (id != null && builtins.containsKey(id)) {
      return builtins[id]!.decode(path);
    }
    if (path.startsWith('custom:')) return profile(path).decode(path);
    return Uri.parse('${Dm5Source.origin}$path');
  }

  List<Map<String, dynamic>>? _fixedProfiles;
  String? _fixedSource;
  @override
  Dm5Source forkForCheck() => SourceHub._check(
    library,
    gateway: gateway,
    profiles: List<Map<String, dynamic>>.from(jsonDecode(jsonEncode(profiles))),
    sourceId: library.option<String>('source', 'dm5'),
  );
  SourceHub._check(
    this.library, {
    super.gateway,
    required List<Map<String, dynamic>> profiles,
    required String sourceId,
  }) : transport = http.Client(),
       scripts = ScriptSourceRuntime(),
       adapters = null,
       super(allowOffline: false) {
    _fixedProfiles = profiles;
    _fixedSource = sourceId;
    refreshImageOrigins();
  }
  List<Map<String, dynamic>> get profiles =>
      _fixedProfiles ??
      [
        ...library.sourceProfiles,
        ...PluginSnapshot(library.options).sources,
      ].where((p) => gateway == null || !p.containsKey('script')).toList();

  Map<String, String> get sourceNames => {
    'dm5': '动漫屋',
    for (final profile in profiles)
      profile['id'] as String: profile['name'] as String,
    for (final id in builtins.keys) id: BuiltinSource.names[id]!,
  };

  Future<SourceSearchResult> searchAcross(
    Iterable<String> sourceIds,
    String query, {
    required bool Function() isCurrent,
    void Function(SourceSearchResult)? onProgress,
  }) async {
    final ids = sourceIds.toSet().toList();
    final books = <String, List<Comic>>{};
    final failures = <String, Object>{};
    SourceSearchResult snapshot() {
      final enabled = sourceNames;
      return (
        books: books.values
            .expand((items) => items)
            .where((book) => enabled.containsKey(book.sourceId))
            .toList(),
        failures: Map.unmodifiable(failures),
      );
    }

    for (var offset = 0; offset < ids.length; offset += 3) {
      if (!isCurrent()) break;
      await Future.wait(
        ids.skip(offset).take(3).map((id) async {
          try {
            final result = await searchIn(
              id,
              query,
            ).timeout(const Duration(seconds: 16));
            books[id] = result.take(40).toList();
          } catch (error) {
            failures[id] = error;
          }
          if (isCurrent()) onProgress?.call(snapshot());
        }),
      );
    }
    return snapshot();
  }

  void refreshImageOrigins() {
    Dm5Source.imageOrigins.addAll({
      for (final host in [
        'cover.mangabz.com',
        'static.mangabz.com',
        'image.mangabz.com',
      ])
        host: '${BuiltinSource.origins['mangabz']}/',
      for (final host in [
        'cdn.dongmanmanhua.cn',
        'cdn-static.dongmanmanhua.cn',
      ])
        host: '${BuiltinSource.origins['dongman']}/',
    });
    for (final json in profiles) {
      final p = SourceProfile.enabled(json);
      for (final host in p.imageHosts) {
        Dm5Source.imageOrigins[host] = p.base.toString();
      }
    }
  }

  SourceProfile? get selected => profiles
      .where(
        (s) =>
            s['id'] ==
            (_fixedSource ?? library.option<String>('source', 'dm5')),
      )
      .map(SourceProfile.enabled)
      .firstOrNull;
  SourceProfile profile(String path) {
    final id = path.split(':')[1];
    return profiles
            .where((p) => p['id'] == id)
            .map(SourceProfile.enabled)
            .firstOrNull ??
        (throw SourceException('请先恢复漫画源 $id 的配置。'));
  }

  Future<void> register() async {
    refreshImageOrigins();
    if (gateway == null) return;
    final response = await transport.post(
      gateway!.resolve('/api/profiles'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(profiles),
    );
    if (response.statusCode != 200) throw SourceException('预览代理未接受漫画源配置。');
  }

  Future<String> customPage(SourceProfile p, Uri url) async {
    refreshImageOrigins();
    if (gateway != null) await register();
    final target =
        gateway
            ?.resolve('/api/custom')
            .replace(queryParameters: {'id': p.id, 'url': url.toString()}) ??
        url;
    return Dm5Source.requestText(
      () => transport.get(target),
      sourceName: p.name,
    );
  }

  @override
  Future<List<Comic>> home() async {
    if (builtins[selectedId] case final source?) return source.catalog();
    final p = selected;
    if (p == null) return super.home();
    if (p.script != null) return scripts.catalog(p);
    return p.catalog(await customPage(p, p.url(p.value('home', '/'))));
  }

  @override
  Future<List<Comic>> search(String query) async {
    if (builtins[selectedId] case final source?) {
      return source.catalog(query: query);
    }
    final p = selected;
    return p == null ? super.search(query) : _searchProfile(p, query);
  }

  /// A one-off lookup must not change discovery's default source or rewrite
  /// the original book's identity, favorites, or reading position.
  Future<List<Comic>> searchIn(String sourceId, String query) async {
    final value = query.trim();
    if (value.isEmpty) return [];
    if (sourceId == 'dm5') return super.search(value);
    if (builtins[sourceId] case final source?) {
      return source.catalog(query: value);
    }
    final json = profiles.where((p) => p['id'] == sourceId).firstOrNull;
    if (json == null) throw SourceException('这个漫画源已停用或被移除，请重新选择。');
    return _searchProfile(SourceProfile.enabled(json), value);
  }

  Future<List<Comic>> _searchProfile(SourceProfile p, String value) async {
    if (p.script != null) return scripts.catalog(p, query: value);
    final url = p.url(
      p
          .value('search', '/search?q={query}')
          .replaceAll('{query}', Uri.encodeComponent(value)),
    );
    return p.catalog(await customPage(p, url));
  }

  @override
  Future<Discovery> discover() async {
    if (selected == null && !builtins.containsKey(selectedId)) {
      return super.discover();
    }
    return Discovery(
      books: await home(),
      sections: const {},
      ranks: const {},
      capturedAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  @override
  Future<Map<String, String>> categories() async =>
      selected == null && !builtins.containsKey(selectedId)
      ? super.categories()
      : {'全部漫画': '/'};

  @override
  Future<SourceCatalog> catalog(String path) async {
    if (builtins[selectedId] case final source?) {
      return SourceCatalog(
        books: await source.catalog(),
        sorts: const {},
        statuses: const {},
        parameters: {
          'sourceId': selectedId,
          if (source.paginated) 'pagesize': '20',
        },
      );
    }
    final p = selected;
    if (p == null) return super.catalog(path);
    final books = p.script == null
        ? p.catalog(await customPage(p, p.url(path)))
        : await scripts.catalog(p);
    return SourceCatalog(
      books: books,
      sorts: const {},
      statuses: const {},
      parameters: p.script != null && p.json['pagination'] == true
          ? {'sourceId': p.id, 'pagesize': '40'}
          : const {},
    );
  }

  @override
  Future<List<Comic>> catalogNext(Map<String, String> specs, int page) async {
    final id = specs['sourceId'];
    if (id == null) return super.catalogNext(specs, page);
    if (builtins[id] case final source?) return source.catalog(page: page);
    final json = profiles.where((p) => p['id'] == id).firstOrNull;
    if (json == null) throw SourceException('这个漫画源已停用或被移除，请重新选择。');
    return scripts.catalog(SourceProfile.scripted(json), page: page);
  }

  @override
  Future<ComicDetail> detail(Comic comic) async {
    final builtin = builtins[BuiltinSource.sourceId(comic.path)];
    if (builtin != null) {
      try {
        final result = await builtin.detail(comic);
        Dm5Source.chapterCatalogs[comic.path] = result.chapters;
        await reportDetailStatus(comic, null);
        return result;
      } catch (error) {
        if (error is SourceCopyrightException ||
            error is SourceEntryException) {
          await reportDetailStatus(comic, error as SourceException);
        }
        final stored = allowOffline
            ? await Dm5Source.offlineDetail?.call(comic)
            : null;
        if (stored != null) return stored;
        rethrow;
      }
    }
    if (!comic.path.startsWith('custom:')) return super.detail(comic);
    try {
      final p = profile(comic.path);
      final result = p.script == null
          ? p.detail(await customPage(p, p.decode(comic.path)), comic)
          : await scripts.detail(p, comic);
      Dm5Source.chapterCatalogs[comic.path] = result.chapters;
      await reportDetailStatus(comic, null);
      return result;
    } catch (error) {
      if (error is SourceCopyrightException || error is SourceEntryException) {
        await reportDetailStatus(comic, error as SourceException);
      }
      final stored = allowOffline
          ? await Dm5Source.offlineDetail?.call(comic)
          : null;
      if (stored != null) return stored;
      rethrow;
    }
  }

  @override
  Future<List<String>> networkPages(String path) async {
    if (builtins[BuiltinSource.sourceId(path)] case final source?) {
      return source.pages(path);
    }
    if (!path.startsWith('custom:')) return super.networkPages(path);
    final p = profile(path);
    return p.script == null
        ? p.pages(await customPage(p, p.decode(path)))
        : scripts.pages(p, path);
  }

  @override
  void close() {
    scripts.close();
    transport.close();
    super.close();
  }
}
