// Public catalog/chapters only. Does not download comic images or execute scripts.
import 'dart:convert';
import 'dart:io';
import 'package:http/io_client.dart';
import 'package:manxia/data/dm5_source.dart';
import 'package:manxia/data/comic.dart';

Future<void> main(List<String> arguments) async {
  final network = HttpClient();
  final proxy = arguments.where((a) => a.startsWith('--proxy=')).firstOrNull;
  if (proxy != null) {
    final address = Uri.parse(proxy.substring('--proxy='.length));
    if (address.scheme != 'http' ||
        address.host.isEmpty ||
        address.userInfo.isNotEmpty) {
      throw ArgumentError('Use an HTTP proxy without credentials.');
    }
    network.findProxy = (_) => 'PROXY ${address.host}:${address.port}';
  }
  final source = Dm5Source(client: IOClient(network), allowOffline: false);
  final queries = arguments.where((a) => !a.startsWith('--')).take(6).toList();
  if (queries.isEmpty) queries.addAll(['火影忍者', '海贼王', '山海逆战', '百炼成神']);
  final results = <Map<String, Object?>>[];
  final watch = Stopwatch()..start();
  try {
    try {
      final discovery = await source.discover();
      results.add({
        'stage': 'discovery',
        'books': discovery.books.length,
        'state': 'ok',
      });
    } catch (error) {
      results.add({
        'stage': 'discovery',
        'state': 'unavailable',
        'message': '$error',
      });
    }
    for (final query in queries) {
      final result = <String, Object?>{'query': query, 'stage': 'search'};
      results.add(result);
      try {
        final books = await source.search(query);
        result['matches'] = books.length;
        final comic = books.where((b) => b.title == query).firstOrNull;
        if (comic == null) {
          result['state'] = 'no_exact_match';
          continue;
        }
        result.addAll({'path': comic.path, 'stage': 'detail'});
        final detail = await source.detail(comic);
        result['chapters'] = detail.chapters.length;
        if (detail.chapters.isEmpty) {
          result['state'] = 'no_chapters';
          continue;
        }
        result['stage'] = 'pages';
        final pages = await source.networkPages(detail.chapters.last.path);
        result.addAll({'images': pages.length, 'state': 'addresses_ok'});
      } on SourceCopyrightException catch (error) {
        result.addAll({'state': 'copyright', 'notice': error.notice});
      } catch (error) {
        result.addAll({'state': 'unavailable', 'message': '$error'});
      }
    }
    for (final argument in arguments.where((a) => a.startsWith('--path='))) {
      final path = argument.substring('--path='.length);
      if (!RegExp(r'^/manhua-[\w-]+/$').hasMatch(path)) {
        throw ArgumentError('Expected a canonical /manhua-name/ detail path.');
      }
      final result = <String, Object?>{'path': path, 'stage': 'detail'};
      results.add(result);
      try {
        final detail = await source.detail(
          Comic(path: path, title: path, cover: ''),
        );
        result['chapters'] = detail.chapters.length;
        result['title'] = detail.comic.title;
        if (detail.chapters.isNotEmpty) {
          result['stage'] = 'pages';
          final pages = await source.networkPages(detail.chapters.last.path);
          result.addAll({'images': pages.length, 'state': 'addresses_ok'});
        } else {
          result['state'] = 'no_chapters';
        }
      } on SourceCopyrightException catch (error) {
        result.addAll({'state': 'copyright', 'notice': error.notice});
      } catch (error) {
        result.addAll({'state': 'unavailable', 'message': '$error'});
      }
      result['attempts'] = source.detailDiagnostics[path]?['attempts'];
    }
  } finally {
    source.close();
  }
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'checkedAt': DateTime.now().toUtc().toIso8601String(),
      'elapsedMs': watch.elapsedMilliseconds,
      'scope':
          'public metadata and image addresses; not image rendering or device reading',
      'results': results,
    }),
  );
}
