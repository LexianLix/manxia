import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/dm5_source.dart';
import 'package:manxia/data/offline_library.dart';
import 'package:manxia/platform/blob_store.dart';
import 'features_test.dart' as fixtures;

Future<void> until(bool Function() predicate) async {
  for (var i = 0; i < 200 && !predicate(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(predicate(), true);
}

class _QueueSource extends Dm5Source {
  final calls = <String>[];
  final first = Completer<List<String>>();
  @override
  Future<List<String>> networkPages(String path) {
    calls.add(path);
    return path == '/a/'
        ? first.future
        : Future.value(['https://images.cdndm5.com$path/page.png']);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'batch pause finishes only the current image and retry resumes after persisted restart',
    () async {
      final library = await fixtures.library();
      await library.setOption('downloadParallel', 1);
      final source = _QueueSource();
      final store = MemoryBlobStore();
      final firstImage = Completer<http.Response>();
      var requests = 0;
      final client = MockClient((request) async {
        if (requests++ == 0) return firstImage.future;
        return http.Response.bytes(
          [1, 2, 3],
          200,
          headers: {'content-type': 'image/png'},
        );
      });
      final offline = OfflineLibrary(
        library,
        source,
        store: store,
        client: client,
      );
      addTearDown(() {
        source.close();
        OfflineLibrary.instance = null;
        Dm5Source.offlinePages = null;
        Dm5Source.offlineDetail = null;
      });
      await offline.initialize();
      await offline.enqueue(fixtures.comic, const Chapter('/a/', 'A'));
      await offline.enqueue(fixtures.comic, const Chapter('/b/', 'B'));
      source.first.complete([
        'https://images.cdndm5.com/1.png',
        'https://images.cdndm5.com/2.png',
      ]);
      await until(() => requests == 1);
      await offline.pauseAll();
      firstImage.complete(
        http.Response.bytes(
          [1, 2, 3],
          200,
          headers: {'content-type': 'image/png'},
        ),
      );
      await until(() => !offline.isRunning(offline.entries.first['id']));
      expect(requests, 1);
      expect(offline.entries.first['done'], 1);
      expect(offline.entries.every((e) => e['status'] == 'paused'), true);
      final restored = OfflineLibrary(
        library,
        source,
        store: store,
        client: MockClient((_) async => http.Response('', 503)),
      );
      await restored.initialize();
      await restored.resume(restored.entries.first['id']);
      await until(() => restored.entries.first['status'] == 'failed');
      expect(restored.entries.first['done'], 1);
      expect(restored.entries.first['error'], contains('503'));
      final recovered = OfflineLibrary(
        library,
        source,
        store: store,
        client: client,
      );
      await recovered.initialize();
      await recovered.retryFailed();
      await until(() => recovered.entries.first['status'] == 'complete');
      expect(recovered.entries[1]['status'], 'paused');
      expect((await recovered.pages('/a/'))!, hasLength(2));
      expect(
        requests,
        3,
      ); // First page, remaining page and optional cover; first page was retained.
    },
  );
  test(
    'prioritizing queued work preserves the active image and survives persisted ordering',
    () async {
      final library = await fixtures.library();
      await library.setOption('downloadParallel', 1);
      final source = _QueueSource();
      final store = MemoryBlobStore();
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
      final offline = OfflineLibrary(
        library,
        source,
        store: store,
        client: MockClient(
          (_) async => http.Response.bytes(
            png,
            200,
            headers: {'content-type': 'image/png'},
          ),
        ),
      );
      addTearDown(() {
        source.close();
        OfflineLibrary.instance = null;
        Dm5Source.offlinePages = null;
        Dm5Source.offlineDetail = null;
      });
      await offline.initialize();
      for (final path in ['/a/', '/b/', '/c/']) {
        await offline.enqueue(fixtures.comic, Chapter(path, path));
      }
      await until(() => source.calls.length == 1);
      await offline.prioritize(offline.entries.last['id']);
      expect(source.calls, ['/a/']);
      source.first.complete(['https://images.cdndm5.com/a/page.png']);
      await until(
        () => offline.entries.every((e) => e['status'] == 'complete'),
      );
      expect(source.calls, ['/a/', '/c/', '/b/']);
      final restored = OfflineLibrary(library, source, store: store);
      await restored.initialize();
      expect(restored.entries.map((e) => e['chapter']['path']), [
        '/c/',
        '/a/',
        '/b/',
      ]);
      expect((await restored.pages('/a/'))!.single, startsWith('offline:'));
    },
  );
}
