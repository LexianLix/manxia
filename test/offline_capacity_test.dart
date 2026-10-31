import 'package:flutter_test/flutter_test.dart';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/dm5_source.dart';
import 'package:manxia/data/offline_library.dart';
import 'package:manxia/platform/blob_store.dart';
import 'features_test.dart' as fixtures;
import 'offline_queue_test.dart' show until;

class _Source extends Dm5Source {
  @override
  Future<List<String>> networkPages(String path) async => [
    'https://images.cdndm5.com/a.png',
    'https://images.cdndm5.com/b.png',
  ];
}

class _SlowStore extends MemoryBlobStore {
  @override
  Future<void> write(String key, Uint8List bytes) async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await super.write(key, bytes);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'concurrent downloads reserve capacity before either file write finishes',
    () async {
      final library = await fixtures.library();
      await library.setOption('offlineLimitMb', 1);
      await library.setOption('downloadParallel', 2);
      final source = _Source();
      final offline = OfflineLibrary(
        library,
        source,
        store: _SlowStore(),
        client: MockClient(
          (_) async => http.Response.bytes(
            List.filled(600000, 1),
            200,
            headers: {'content-type': 'image/png'},
          ),
        ),
      );
      addTearDown(() {
        source.close();
        OfflineLibrary.instance = null;
        Dm5Source.offlineDetail = null;
        Dm5Source.offlinePages = null;
      });
      await offline.initialize();
      await offline.enqueue(fixtures.comic, const Chapter('/first/', 'First'));
      await offline.enqueue(
        fixtures.comic,
        const Chapter('/second/', 'Second'),
      );
      await until(() => offline.entries.every((e) => e['status'] == 'paused'));
      expect(offline.bytes, 600000);
      expect(offline.entries.fold<int>(0, (n, e) => n + (e['done'] as int)), 1);
    },
  );
  test(
    'capacity pauses before writing the excess page and resumes without redownloading',
    () async {
      final library = await fixtures.library();
      await library.setOption('offlineLimitMb', 1);
      await library.toggle(fixtures.comic);
      await library.save(fixtures.record(1, 10));
      final source = _Source();
      final store = MemoryBlobStore();
      var firstRequests = 0;
      final offline = OfflineLibrary(
        library,
        source,
        store: store,
        client: MockClient((r) async {
          if (r.url.path == '/a.png') firstRequests++;
          return http.Response.bytes(
            List.filled(r.url.path.endsWith('.png') ? 600000 : 1, 1),
            200,
            headers: {'content-type': 'image/png'},
          );
        }),
      );
      addTearDown(() {
        source.close();
        OfflineLibrary.instance = null;
        Dm5Source.offlineDetail = null;
        Dm5Source.offlinePages = null;
      });
      await offline.initialize();
      await offline.enqueue(
        fixtures.comic,
        const Chapter('/capacity/', 'Capacity'),
      );
      await until(() => offline.entries.single['status'] == 'paused');
      expect(offline.entries.single['done'], 1);
      expect(offline.bytes, 600000);
      await library.setOption('offlineLimitMb', 2);
      await offline.resume(offline.entries.single['id']);
      await until(() => offline.entries.single['status'] == 'complete');
      expect(firstRequests, 1);
      final id = offline.entries.single['id'] as String;
      expect(offline.reclaimableBytes([id]), offline.bytes);
      await offline.removeMany([id]);
      expect(offline.bytes, 0);
      expect(library.favorites, hasLength(1));
      expect(library.record(fixtures.comic)!.page, 1);
    },
  );
}
