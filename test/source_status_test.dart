import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/dm5_source.dart';
import 'package:manxia/data/source_hub.dart';
import 'package:manxia/data/library.dart';
import 'features_test.dart' as fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'copyright state persists even when downloaded chapters remain readable',
    () async {
      final library = await fixtures.library();
      final book = fixtures.comic;
      var blocked = true;
      late SourceHub source;
      http.runWithClient(
        () {
          source = SourceHub(library);
        },
        () => MockClient(
          (_) async => http.Response(
            blocked
                ? '<div class="warning-bar">应版权方要求已删除本作品链接</div>'
                : 'verification required',
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          ),
        ),
      );
      addTearDown(() {
        source.close();
        Dm5Source.offlineDetail = null;
      });
      Dm5Source.offlineDetail = (comic) async =>
          ComicDetail(comic, const [Chapter('/downloaded/', 'Downloaded')]);
      expect((await source.detail(book)).chapters.single.path, '/downloaded/');
      expect(library.sourceStatus(book)!['kind'], 'copyright');
      blocked = false;
      // A temporary parsing/network failure must not turn an old explicit state into success.
      await source.detail(book);
      expect(library.sourceStatus(book)!['kind'], 'copyright');
    },
  );
  test(
    'explicit source failures are local, scoped, expire and clear after a successful live detail',
    () async {
      final library = await fixtures.library();
      final book = fixtures.comic;
      await library.toggle(book);
      var state = 404;
      late SourceHub source;
      http.runWithClient(
        () {
          source = SourceHub(library);
        },
        () => MockClient(
          (_) async => http.Response(
            state == 200
                ? '<p class="detail-main-info-title">Test</p><ul class="detail-list-select"><a href="/m1/">1</a></ul>'
                : '',
            state,
          ),
        ),
      );
      addTearDown(source.close);
      await expectLater(
        source.detail(book),
        throwsA(isA<SourceEntryException>()),
      );
      expect(library.sourceStatus(book)!['kind'], 'missing');
      await library.setOption('hideUnavailable', true);
      expect(library.browseBooks([book]), isEmpty);
      expect(library.favorites.single.path, book.path);
      final restored = Library(library.prefs)..loadFeatures();
      expect(restored.sourceStatus(book)!['kind'], 'missing');
      final at = library.sourceStatus(book)!['checkedAt'] as int;
      expect(
        library.sourceStatus(
          book,
          at: at + const Duration(hours: 24).inMilliseconds,
        ),
        isNull,
      );
      expect(
        library.sourceStatus(
          Comic(
            path: book.path,
            title: book.title,
            cover: '',
            sourceId: 'other',
          ),
        ),
        isNull,
      );
      expect(library.backup().containsKey('sourceStatuses'), false);
      state = 200;
      expect((await source.detail(book)).chapters, isNotEmpty);
      expect(library.sourceStatus(book), isNull);
      expect(library.browseBooks([book]), hasLength(1));
    },
  );
  test(
    'marking updates read preserves latest chapter and check failure details',
    () async {
      final library = await fixtures.library();
      library.updates['/a'] = {
        'fingerprint': '/m2/',
        'latest': '2',
        'changed': true,
        'checkError': 'offline',
      };
      await library.markUpdatesRead(['/a']);
      expect(library.updates['/a']!['changed'], false);
      expect(library.updates['/a']!['seenFingerprint'], '/m2/');
      expect(library.updates['/a']!['checkError'], 'offline');
      final restored = Library(library.prefs)..loadFeatures();
      expect(restored.updates['/a']!['changed'], false);
    },
  );
}
