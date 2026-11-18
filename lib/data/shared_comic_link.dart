import 'builtin_source.dart';
import 'comic.dart';

/// Resolve only known public comic-detail routes, using the same identities
/// as the source catalogs. The pasted URL itself is never fetched.
Comic? comicFromSharedText(String text) {
  if (text.length > 8192) return null;
  final links = RegExp(
    r'''https?://[^\s<>"'，。；、！（）《》]+''',
    caseSensitive: false,
  );
  for (final match in links.allMatches(text)) {
    final raw = match[0]!.replaceFirst(RegExp(r'[)\]},.!;]+$'), '');
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.userInfo.isNotEmpty || uri.hasPort) continue;
    final path = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
    switch (uri.host) {
      case 'dm5.com':
      case 'm.dm5.com':
      case 'www.dm5.com':
        if (RegExp(r'^/manhua-[a-zA-Z0-9-]+/$').hasMatch(path)) {
          return Comic(path: path, title: '动漫屋', cover: '');
        }
      case 'mangabz.com':
      case 'www.mangabz.com':
        if (RegExp(r'^/\d{1,12}bz/$').hasMatch(path)) {
          return Comic(
            path: BuiltinSource.encode('mangabz', path),
            title: 'Mangabz',
            cover: '',
            sourceId: 'mangabz',
          );
        }
      case 'dongmanmanhua.cn':
      case 'www.dongmanmanhua.cn':
      case 'm.dongmanmanhua.cn':
        if (path != '/episodeList/' &&
            !RegExp(r'^/[A-Za-z_]+/[^/]+/list/$').hasMatch(path)) {
          continue;
        }
        final ids = [
          ...?uri.queryParametersAll['title_no'],
          ...?uri.queryParametersAll['titleNo'],
        ];
        if (ids.length == 1 && RegExp(r'^\d{1,12}$').hasMatch(ids.single)) {
          return Comic(
            path: BuiltinSource.encode(
              'dongman',
              '/episodeList?titleNo=${ids.single}',
            ),
            title: '咚漫漫画',
            cover: '',
            sourceId: 'dongman',
          );
        }
    }
  }
  return null;
}
