import 'dart:convert';
import 'dart:io';
import 'package:http/io_client.dart';
import 'package:manxia/data/builtin_source.dart';

/// Live desktop/CI probe of the actual native adapters. Does not claim phone
/// connectivity or FPS. No mock catalog, cookies or chapter data are supplied.
Future<void> main(List<String> args) async {
  final http = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  final proxy = Platform.environment['MANXIA_CHECK_PROXY'];
  if (proxy != null) http.findProxy = (_) => 'PROXY $proxy';
  final client = IOClient(http);
  final results = <String, Object>{};
  try {
    final selected = args
        .where((a) => a.startsWith('--source='))
        .firstOrNull
        ?.substring(9);
    for (final id in BuiltinSource.names.keys.where(
      (id) => selected == null || selected == id,
    )) {
      final source = BuiltinSource(id, client);
      final timer = Stopwatch()..start();
      stdout.writeln('$id discovery');
      final catalog = await source.catalog();
      stdout.writeln('$id discovery=${catalog.length}; search');
      final query = id == 'mangabz' ? '火影' : '女儿';
      final search = await source.catalog(query: query);
      if (catalog.isEmpty || search.isEmpty) {
        throw StateError('$id returned empty discovery/search');
      }
      stdout.writeln('$id search=${search.length}; detail');
      final book = id == 'mangabz' ? search.first : catalog.first;
      final detail = await source.detail(book);
      stdout.writeln('$id chapters=${detail.chapters.length}; pages');
      final pages = await source.pages(detail.chapters.last.path);
      stdout.writeln('$id pages=${pages.length}; image');
      final image = await client.get(
        Uri.parse(pages.first),
        headers: {'Referer': '${source.origin}/'},
      );
      if (image.statusCode != 200 ||
          image.bodyBytes.length < 1000 ||
          !(image.headers['content-type'] ?? '').startsWith('image/')) {
        throw StateError('$id first chapter image failed: ${image.statusCode}');
      }
      results[id] = {
        'discovery': catalog.length,
        'search': search.length,
        'book': book.title,
        'chapters': detail.chapters.length,
        'pages': pages.length,
        'imageBytes': image.bodyBytes.length,
        'elapsedMs': timer.elapsedMilliseconds,
      };
      stdout.writeln(jsonEncode({id: results[id]}));
    }
    final output = args.where((a) => !a.startsWith('--')).firstOrNull;
    if (output != null) {
      await File(
        output,
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(results));
    }
  } finally {
    client.close();
  }
}
