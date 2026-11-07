import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/dm5_source.dart';
import 'package:manxia/data/offline_library.dart';
import 'package:manxia/platform/blob_store.dart';
import 'package:manxia/platform/network_monitor.dart';
import 'features_test.dart' as fixtures;

class _Source extends Dm5Source {
  int catalogRequests = 0;
  @override
  Future<List<String>> networkPages(String path) async {
    catalogRequests++;
    return [
      'https://images.cdndm5.com/1.png',
      'https://images.cdndm5.com/2.png',
    ];
  }
}

Future<void> until(bool Function() ready) async {
  for (var i = 0; i < 200 && !ready(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(ready(), isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'foreground leases hold new tasks and pause between downloaded pages',
    () async {
      final library = await fixtures.library();
      final source = _Source();
      final first = Completer<http.Response>();
      var requests = 0;
      final offline = OfflineLibrary(
        library,
        source,
        store: MemoryBlobStore(),
        client: MockClient((r) async {
          if (!r.url.path.endsWith('/1.png') &&
              !r.url.path.endsWith('/2.png')) {
            return http.Response.bytes(
              [1, 2, 3],
              200,
              headers: {'content-type': 'image/png'},
            );
          }
          requests++;
          if (requests == 1) return first.future;
          return http.Response.bytes(
            [1, 2, 3],
            200,
            headers: {'content-type': 'image/png'},
          );
        }),
      );
      addTearDown(() {
        offline.dispose();
        source.close();
        library.dispose();
        OfflineLibrary.instance = null;
        Dm5Source.offlinePages = null;
        Dm5Source.offlineDetail = null;
      });
      await offline.initialize();
      final one = offline.prioritizeReading(),
          two = offline.prioritizeReading();
      await offline.enqueue(
        fixtures.comic,
        const Chapter('/reading-priority/', '章节'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(source.catalogRequests, 0);
      one();
      one();
      expect(source.catalogRequests, 0);
      two();
      await until(() => requests == 1);
      final next = offline.prioritizeReading();
      first.complete(
        http.Response.bytes(
          [1, 2, 3],
          200,
          headers: {'content-type': 'image/png'},
        ),
      );
      await until(() => offline.entries.single['done'] == 1);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(requests, 1);
      next();
      await until(() => offline.entries.single['status'] == 'complete');
      expect(requests, 2);
      expect(offline.entries.single['done'], 2);
    },
  );

  test(
    'one missing page repairs without redownloading neighbors or double accounting',
    () async {
      final library = await fixtures.library();
      final source = _Source(), store = MemoryBlobStore();
      var requests = 0;
      final network = NetworkMonitor(
        native: false,
        initial: const NetworkInfo('wifi'),
      );
      final offline = OfflineLibrary(
        library,
        source,
        store: store,
        network: network,
        client: MockClient((r) async {
          if (!r.url.path.endsWith('/1.png') &&
              !r.url.path.endsWith('/2.png')) {
            return http.Response.bytes(
              [1, 2, 3],
              200,
              headers: {'content-type': 'image/png'},
            );
          }
          requests++;
          return http.Response.bytes(
            requests > 2 ? [4, 5, 6, 7] : [1, 2, 3],
            200,
            headers: {'content-type': 'image/png'},
          );
        }),
      );
      addTearDown(() {
        offline.dispose();
        source.close();
        library.dispose();
        OfflineLibrary.instance = null;
        Dm5Source.offlinePages = null;
        Dm5Source.offlineDetail = null;
      });
      await offline.initialize();
      await offline.enqueue(fixtures.comic, const Chapter('/repair/', '修复章节'));
      await until(() => offline.entries.single['status'] == 'complete');
      final entry = offline.entries.single,
          keys = List<String>.from(offline.entries.single['keys']);
      final neighbor = store.data[keys[1]];
      await store.delete(keys[0]);
      await offline.repairPage('offline:${keys[0]}');
      expect(requests, 3);
      expect(source.catalogRequests, 1);
      expect(store.data[keys[0]], [4, 5, 6, 7]);
      expect(identical(store.data[keys[1]], neighbor), isTrue);
      expect(entry['bytes'], 7);
      expect(entry['done'], 2);
      expect(entry['status'], 'complete');
      await store.delete(keys[0]);
      await store.delete(keys[1]);
      await Future.wait([
        offline.repairPage('offline:${keys[0]}'),
        offline.repairPage('offline:${keys[1]}'),
      ]);
      expect(
        entry['bytes'],
        8,
        reason: 'Concurrent repairs must account for both repaired pages',
      );
      network.value = const NetworkInfo('none');
      await expectLater(
        offline.repairPage('offline:${keys[0]}'),
        throwsStateError,
      );
      expect(requests, 5);
      entry['local'] = true;
      await expectLater(
        offline.repairPage('offline:${keys[0]}'),
        throwsStateError,
      );
    },
  );
}
