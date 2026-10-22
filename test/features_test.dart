import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/discovery.dart';
import 'package:manxia/data/dm5_source.dart';
import 'package:manxia/data/library.dart';
import 'package:manxia/data/offline_library.dart';
import 'package:manxia/data/source_hub.dart';
import 'package:manxia/data/source_catalog.dart';
import 'package:manxia/data/sync_service.dart';
import 'package:manxia/platform/blob_store.dart';

const comic = Comic(
  path: '/manhua-test/',
  title: '测试漫画',
  cover: 'https://images.cdndm5.com/a.jpg',
);
ReadingRecord record(int page, int at) => ReadingRecord(
  comic: comic,
  chapterPath: '/m1/',
  chapterTitle: '第1话',
  page: page,
  total: 20,
  updatedAt: at,
  position: .35,
);
Future<Library> library() async {
  SharedPreferences.setMockInitialValues({});
  final l = Library(await SharedPreferences.getInstance());
  await l.load();
  return l;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    Dm5Source.chapterCatalogs.clear();
    Dm5Source.offlinePages = null;
    Dm5Source.offlineDetail = null;
    OfflineLibrary.instance = null;
  });
  test(
    'offline chapter order follows the source after out-of-order downloads and restart',
    () async {
      final l = await library();
      final source = Dm5Source(
        client: MockClient(
          (r) async => http.Response(
            r.url.path == comic.path
                ? '<h1 class="detail-main-info-title">Test</h1><div class="detail-list-select" id="detail-list-select-1"><a href="/m3/">3</a><a href="/m2/">2</a><a href="/m1/">1</a></div>'
                : "var newImgs=['https://images.cdndm5.com/1.jpg'];",
            200,
          ),
        ),
      );
      await source.detail(comic);
      final store = MemoryBlobStore();
      final offline = OfflineLibrary(
        l,
        source,
        store: store,
        client: MockClient(
          (_) async => http.Response.bytes(
            [255, 216, 255],
            200,
            headers: {'content-type': 'image/jpeg'},
          ),
        ),
      );
      await offline.initialize();
      await offline.enqueue(comic, const Chapter('/m1/', '1'));
      await offline.enqueue(comic, const Chapter('/m3/', '3'));
      for (
        var i = 0;
        i < 100 && offline.entries.any((e) => e['status'] != 'complete');
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      Dm5Source.chapterCatalogs.clear();
      final restored = OfflineLibrary(l, source, store: store);
      await restored.initialize();
      expect(restored.chapters(comic).map((c) => c.path), ['/m3/', '/m1/']);
      source.close();
    },
  );
  test(
    'a stale backup cannot resurrect deleted books, history or bookmarks',
    () async {
      final l = await library();
      await l.toggle(comic);
      await l.save(record(1, 100));
      await l.addBookmark(record(1, 100));
      final stale = jsonDecode(jsonEncode(l.backup())) as Map<String, dynamic>;
      await l.toggle(comic);
      await l.removeHistory(comic);
      await l.removeBookmark(l.bookmarks.single['id']);
      await l.restore(stale);
      expect(l.favorites, isEmpty);
      expect(l.history, isEmpty);
      expect(l.bookmarks, isEmpty);
      await l.toggle(comic);
      await l.restore(stale);
      expect(l.favorites.length, 1);
    },
  );
  test(
    'category links preserve combined source filters and normalize tracking query strings',
    () {
      const input = '''<script>var tagid = "31"; var pagesize = "10";</script>
      <a class="manga-list-bar-item" href="javascript:pushHistory('/manhua-list-tag31-st2-s18/');">最新上架</a>
      <ul><li><div class="manga-list-2-cover"><a href="/manhua-test/?from=tag"><img src="https://images.cdndm5.com/test.jpg"></a></div><p class="manga-list-2-title">Test</p></li></ul>''';
      final books = Dm5Source.parseCatalog(input);
      final result = SourceCatalog.parse(input, books);
      expect(books.single.path, '/manhua-test/');
      expect(result.sorts['最新上架'], '/manhua-list-tag31-st2-s18/');
      expect(result.parameters['tagid'], '31');
      expect(result.parameters['pagesize'], '10');
    },
  );
  test(
    'complete offline bundles restore images and reject corrupt page bytes',
    () async {
      final l = await library();
      final source = Dm5Source();
      final offline = OfflineLibrary(l, source, store: MemoryBlobStore());
      await offline.initialize();
      final c = await offline.importImages('Bundle', [
        (name: '1.png', bytes: Uint8List.fromList([137, 80, 78, 71])),
      ]);
      final bytes = await offline.exportBundle();
      final target = OfflineLibrary(l, source, store: MemoryBlobStore());
      await target.initialize();
      await target.importBundle(bytes);
      expect((await target.detail(c))!.chapters.length, 1);
      final zip = ZipDecoder().decodeBytes(bytes);
      final broken = Archive();
      for (final f in zip.files) {
        broken.addFile(
          f.name.startsWith('pages/')
              ? ArchiveFile(f.name, 1, Uint8List.fromList([0]))
              : f,
        );
      }
      final clean = await library();
      final other = OfflineLibrary(clean, source, store: MemoryBlobStore());
      await other.initialize();
      await expectLater(
        other.importBundle(Uint8List.fromList(ZipEncoder().encode(broken))),
        throwsFormatException,
      );
      expect(other.entries, isEmpty);
      final future = Archive();
      for (final f in zip.files) {
        if (f.name == 'manifest.json') {
          final manifest = jsonDecode(utf8.decode(f.content)) as Map;
          manifest['library']['schema'] = 999;
          final data = utf8.encode(jsonEncode(manifest));
          future.addFile(ArchiveFile(f.name, data.length, data));
        } else {
          future.addFile(f);
        }
      }
      await expectLater(
        other.importBundle(Uint8List.fromList(ZipEncoder().encode(future))),
        throwsFormatException,
      );
      expect(other.entries, isEmpty);
      expect(await other.read(offline.entries.single['keys'][0]), isNull);
      source.close();
    },
  );
  test(
    'daily picks are date stable, unique and edition changes selection',
    () async {
      final books = List.generate(
        30,
        (i) => Comic(path: '/$i', title: '$i', cover: ''),
      );
      final d = Discovery(
        books: books,
        sections: {},
        ranks: {},
        capturedAt: '2026-10-20',
      );
      final day = DateTime(2026, 10, 20);
      expect(d.daily(day).map((b) => b.path), d.daily(day).map((b) => b.path));
      expect(d.daily(day).map((b) => b.path).toSet().length, 12);
      expect(
        d.daily(day, edition: 1).map((b) => b.path),
        isNot(d.daily(day).map((b) => b.path)),
      );
    },
  );
  test(
    'backup merge preserves newer progress and per-book preferences across reload',
    () async {
      final l = await library();
      await l.toggle(comic);
      await l.save(record(8, 200));
      await l.setReaderOption(comic, 'mode', 'strip');
      await l.addBookmark(record(3, 100), note: '想再读这一页');
      final backup = jsonDecode(jsonEncode(l.backup())) as Map<String, dynamic>;
      backup['history'] = [record(1, 100).toJson()];
      await l.restore(backup);
      expect(l.favorites.length, 1);
      expect(l.history.single.page, 8);
      expect(l.demo, false);
      final loaded = Library(l.prefs);
      await loaded.load();
      expect(loaded.readerOptions(comic)['mode'], 'strip');
      expect(loaded.history.single.position, .35);
      expect(loaded.bookmarks.single['note'], '想再读这一页');
      await expectLater(
        l.restore({'format': 'manxia', 'schema': 999}),
        throwsFormatException,
      );
    },
  );
  test(
    'ZIP import uses natural page order, survives restart and exports real image extensions',
    () async {
      final l = await library();
      final store = MemoryBlobStore();
      final source = Dm5Source();
      final offline = OfflineLibrary(l, source, store: store);
      await offline.initialize();
      final archive = Archive();
      final png = Uint8List.fromList([137, 80, 78, 71, 10]);
      archive.addFile(ArchiveFile('10.png', 5, png));
      archive.addFile(
        ArchiveFile('2.png', 5, Uint8List.fromList([137, 80, 78, 71, 2])),
      );
      archive.addFile(
        ArchiveFile('1.png', 5, Uint8List.fromList([137, 80, 78, 71, 1])),
      );
      final c = await offline.importZip(
        '漫画.cbz',
        Uint8List.fromList(ZipEncoder().encode(archive)),
      );
      final e = offline.entries.single;
      expect((await offline.read(e['keys'][0]))!.last, 1);
      expect((await offline.read(e['keys'][1]))!.last, 2);
      final restored = OfflineLibrary(l, source, store: store);
      await restored.initialize();
      expect((await restored.detail(c))!.chapters.length, 1);
      expect((await restored.pages(e['chapter']['path']))!.length, 3);
      final output = ZipDecoder().decodeBytes(await restored.exportChapter(e));
      expect(output.files.map((f) => f.name), [
        '0001.png',
        '0002.png',
        '0003.png',
      ]);
      await restored.remove(e['id']);
      expect(restored.bytes, 0);
      expect(await restored.read(e['keys'][0]), isNull);
      source.close();
    },
  );
  test(
    'failed downloads retain completed pages and retry only missing images',
    () async {
      final l = await library();
      var failures = true;
      final calls = <String, int>{};
      final source = Dm5Source(
        client: MockClient(
          (_) async => http.Response(
            "var newImgs=['https://images.cdndm5.com/1.jpg','https://images.cdndm5.com/2.jpg'];",
            200,
          ),
        ),
      );
      final client = MockClient((r) async {
        calls.update(r.url.path, (i) => i + 1, ifAbsent: () => 1);
        return failures && r.url.path == '/2.jpg'
            ? http.Response('', 503)
            : http.Response.bytes(
                [255, 216, 255],
                200,
                headers: {'content-type': 'image/jpeg'},
              );
      });
      final offline = OfflineLibrary(
        l,
        source,
        store: MemoryBlobStore(),
        client: client,
      );
      await offline.initialize();
      await offline.enqueue(comic, const Chapter('/m1/', '1'));
      for (
        var i = 0;
        i < 100 && offline.entries.single['status'] != 'failed';
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(offline.entries.single['status'], 'failed');
      expect(offline.entries.single['done'], 1);
      failures = false;
      await offline.resume(offline.entries.single['id']);
      for (
        var i = 0;
        i < 100 && offline.entries.single['status'] != 'complete';
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(offline.entries.single['status'], 'complete');
      expect(calls['/1.jpg'], 1);
      expect(calls['/2.jpg'], 2);
      source.close();
      client.close();
    },
  );
  test(
    'declarative source parses cards, chapter links and pages without executing scripts',
    () {
      final p = SourceProfile({
        'id': 'test',
        'name': 'Test',
        'baseUrl': 'https://example.com',
        'cards': '.comic',
        'title': '.title',
        'link': 'a',
        'cover': 'img',
        'chapters': '.chapters a',
        'pages': '.reader img',
        'imageHosts': ['cdn.example.com'],
      });
      final books = p.catalog(
        '<div class="comic"><a href="/book/1"><span class="title">Title</span><img src="https://cdn.example.com/cover.png"></a></div>',
      );
      expect(books.single.sourceId, 'test');
      expect(p.decode(books.single.path).path, '/book/1');
      final detail = p.detail(
        '<div class="chapters"><a href="/chapter/1">One</a></div>',
        books.single,
      );
      expect(p.decode(detail.chapters.single.path).path, '/chapter/1');
      expect(
        p.pages(
          '<div class="reader"><img src="https://cdn.example.com/1.png"><img src="http://bad.com/2.png"></div>',
        ),
        ['https://cdn.example.com/1.png'],
      );
      expect(() => p.url('https://other.com/'), throwsFormatException);
    },
  );
  test(
    'WebDAV merges remote progress and writes with ETag, rejects conflicts',
    () async {
      final l = await library();
      await l.save(record(1, 100));
      final remote = {
        ...l.backup(),
        'history': [record(9, 500).toJson()],
      };
      var conflict = false;
      String? matched;
      final sync = SyncService(
        l,
        readPassword: () async => 'test-password',
        client: MockClient((r) async {
          if (r.method == 'GET') {
            return http.Response(
              jsonEncode(remote),
              200,
              headers: {
                'etag': '"v1"',
                'content-type': 'application/json; charset=utf-8',
              },
            );
          }
          matched = r.headers['if-match'];
          expect(r.headers['authorization'], startsWith('Basic '));
          expect((jsonDecode(r.body)['history'] as List).single['page'], 9);
          return http.Response('', conflict ? 412 : 204);
        }),
      );
      await l.setOption('webdav.url', 'https://dav.example.com/library.json');
      await sync.synchronize();
      expect(matched, '"v1"');
      expect(l.history.single.page, 9);
      conflict = true;
      await expectLater(sync.synchronize(), throwsStateError);
      expect(jsonEncode(l.backup()), isNot(contains('test-password')));
      sync.close();
    },
  );
  test(
    'WebDAV offline backup transfers actual archive bytes and restores them',
    () async {
      final l = await library();
      await l.setOption('webdav.url', 'https://dav.example.com/library.json');
      final source = Dm5Source();
      final offline = OfflineLibrary(l, source, store: MemoryBlobStore());
      await offline.initialize();
      await offline.importImages('Cloud', [
        (name: '1.png', bytes: Uint8List.fromList([137, 80, 78, 71])),
      ]);
      Uint8List? uploaded;
      final sync = SyncService(
        l,
        readPassword: () async => 'test-password',
        client: MockClient((r) async {
          expect(r.url.path, '/library.offline.zip');
          if (r.method == 'HEAD') return http.Response('', 404);
          if (r.method == 'PUT') {
            expect(r.headers['if-none-match'], '*');
            uploaded = r.bodyBytes;
            return http.Response('', 201);
          }
          return http.Response.bytes(uploaded!, 200);
        }),
      );
      await sync.uploadLibrary(offline);
      expect(uploaded, isNotEmpty);
      final clean = await library();
      final restored = OfflineLibrary(clean, source, store: MemoryBlobStore());
      await restored.initialize();
      await sync.downloadLibrary(restored);
      expect(restored.localBooks.single.title, 'Cloud');
      expect(restored.entries.single['done'], 1);
      sync.close();
      source.close();
    },
  );
}
