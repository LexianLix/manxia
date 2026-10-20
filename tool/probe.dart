import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:manxia/data/dm5_source.dart';

Future<void> main() async {
  final source = Dm5Source();
  final result = <String, dynamic>{};
  try {
    final home = await source.home();
    result['catalogCount'] = home.length;
    final matches = await source.search('冰之城壁');
    result['searchCount'] = matches.length;
    final comic = matches.firstWhere((c) => c.title == '冰之城壁');
    final detail = await source.detail(comic);
    result['title'] = detail.comic.title;
    result['chapterCount'] = detail.chapters.length;
    final first = detail.chapters.where((c) => c.group == '连载').last;
    final pages = await source.pages(first.path);
    result['chapter'] = first.title;
    result['pageCount'] = pages.length;
    final image = await http
        .get(Uri.parse(pages.first), headers: {'Referer': 'https://m.dm5.com/'})
        .timeout(const Duration(seconds: 25));
    result['firstImageStatus'] = image.statusCode;
    result['firstImageBytes'] = image.bodyBytes.length;
    result['firstImageContentType'] = image.headers['content-type'];
    if (image.statusCode != 200 ||
        !(image.headers['content-type'] ?? '').startsWith('image/')) {
      throw Exception('First image did not load');
    }
    result['passed'] = true;
  } catch (e) {
    result['passed'] = false;
    result['error'] = e.toString();
    exitCode = 1;
  } finally {
    source.close();
  }
  final output = const JsonEncoder.withIndent('  ').convert(result);
  stdout.writeln(output);
  await Directory('artifacts').create(recursive: true);
  await File('artifacts/source-probe.json').writeAsString(output);
}
