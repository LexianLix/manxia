import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/dm5_source.dart';
import 'package:manxia/data/offline_library.dart';
import 'package:manxia/platform/blob_store.dart';
import 'features_test.dart' as fixtures;
import 'offline_queue_test.dart' show until;

class _ExpiringSource extends Dm5Source {
  int reads = 0;
  @override
  Future<List<String>> networkPages(String path) async {
    reads++;
    return [
      'https://images.cdndm5.com/1.png?token=$reads',
      'https://images.cdndm5.com/2.png?token=$reads',
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'expired download addresses refresh once and retain the completed page',
    () async {
      final library = await fixtures.library();
      final source = _ExpiringSource();
      var firstPageRequests = 0;
      final offline = OfflineLibrary(
        library,
        source,
        store: MemoryBlobStore(),
        client: MockClient((r) async {
          if (r.url.path == '/1.png') firstPageRequests++;
          if (r.url.path == '/2.png' && r.url.queryParameters['token'] == '1') {
            return http.Response('', 403);
          }
          return http.Response.bytes(
            [1, 2, 3],
            200,
            headers: {'content-type': 'image/png'},
          );
        }),
      );
      addTearDown(() {
        source.close();
        OfflineLibrary.instance = null;
        Dm5Source.offlinePages = null;
        Dm5Source.offlineDetail = null;
      });
      await offline.initialize();
      await offline.enqueue(
        fixtures.comic,
        const Chapter('/expired/', 'Chapter'),
      );
      await until(
        () => ['complete', 'failed'].contains(offline.entries.single['status']),
      );
      expect(offline.entries.single['status'], 'complete');
      expect(source.reads, 2);
      expect(firstPageRequests, 1);
      expect((await offline.pages('/expired/'))!, hasLength(2));
    },
  );
}
