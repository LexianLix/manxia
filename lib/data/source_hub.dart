import 'dart:convert';
import 'package:http/http.dart' as http;
import 'comic.dart';
import 'discovery.dart';
import 'dm5_source.dart';
import 'library.dart';
import 'source_profile.dart';
import 'plugin.dart';
export 'source_profile.dart';

class SourceHub extends Dm5Source {
  SourceHub(this.library, {super.gateway, http.Client? transport})
    : transport = transport ?? http.Client() {
    refreshImageOrigins();
  }
  final Library library;
  final http.Client transport;
  List<Map<String, dynamic>> get profiles => [
    ...library.sourceProfiles,
    ...PluginSnapshot(library.options).sources,
  ];
  void refreshImageOrigins() {
    for (final json in profiles) {
      final p = SourceProfile(json);
      for (final host in p.imageHosts) {
        Dm5Source.imageOrigins[host] = p.base.toString();
      }
    }
  }

  SourceProfile? get selected => profiles
      .where((s) => s['id'] == library.option<String>('source', 'dm5'))
      .map(SourceProfile.new)
      .firstOrNull;
  SourceProfile profile(String path) {
    final id = path.split(':')[1];
    return profiles
            .where((p) => p['id'] == id)
            .map(SourceProfile.new)
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
    final response = await transport
        .get(target)
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw SourceException('${p.name} 返回 HTTP ${response.statusCode}');
    }
    return utf8.decode(response.bodyBytes);
  }

  @override
  Future<List<Comic>> home() async {
    final p = selected;
    return p == null
        ? super.home()
        : p.catalog(await customPage(p, p.url(p.value('home', '/'))));
  }

  @override
  Future<List<Comic>> search(String query) async {
    final p = selected;
    return p == null
        ? super.search(query)
        : p.catalog(
            await customPage(
              p,
              p.url(
                p
                    .value('search', '/search?q={query}')
                    .replaceAll('{query}', Uri.encodeComponent(query)),
              ),
            ),
          );
  }

  @override
  Future<Discovery> discover() async {
    if (selected == null) return super.discover();
    return Discovery(
      books: await home(),
      sections: const {},
      ranks: const {},
      capturedAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  @override
  Future<ComicDetail> detail(Comic comic) async {
    if (!comic.path.startsWith('custom:')) return super.detail(comic);
    final p = profile(comic.path);
    try {
      final result = p.detail(await customPage(p, p.decode(comic.path)), comic);
      Dm5Source.chapterCatalogs[comic.path] = result.chapters;
      return result;
    } catch (_) {
      final stored = await Dm5Source.offlineDetail?.call(comic);
      if (stored != null) return stored;
      rethrow;
    }
  }

  @override
  Future<List<String>> networkPages(String path) async {
    if (!path.startsWith('custom:')) return super.networkPages(path);
    final p = profile(path);
    return p.pages(await customPage(p, p.decode(path)));
  }

  @override
  void close() {
    transport.close();
    super.close();
  }
}
