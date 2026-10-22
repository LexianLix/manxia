import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/discovery.dart';
import 'package:manxia/data/dm5_source.dart';
import 'package:manxia/data/library.dart';
import 'package:manxia/data/offline_library.dart';
import 'package:manxia/main.dart';
import 'package:manxia/platform/blob_store.dart';
import 'package:manxia/ui/app_shell.dart';
import 'package:manxia/ui/discovery_collection.dart';
import 'package:manxia/ui/discovery_page.dart';
import 'package:manxia/ui/source_browser.dart';

class SnapshotSource extends Dm5Source {
  SnapshotSource(this.snapshot);
  final Discovery snapshot;
  @override
  Future<Discovery> discover() async => snapshot;
}

Future<Library> library({Map<String, Object> values = const {}}) async {
  SharedPreferences.setMockInitialValues(values);
  final result = Library(await SharedPreferences.getInstance());
  await result.load();
  return result;
}

Future<Discovery> snapshot() async => Discovery.fromJson(
  jsonDecode(await rootBundle.loadString('assets/discovery.json')),
);

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  final directory = Platform.environment['MANXIA_CAPTURE_DIR'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File(
      '$directory/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    if (Platform.environment['MANXIA_CAPTURE_DIR'] != null) {
      await (FontLoader('ArchiveSerif')..addFont(
            rootBundle.load('assets/fonts/SourceHanSerifCN-Regular.otf'),
          ))
          .load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
  });

  testWidgets('an empty real shelf has no demo books or demo recommendations', (
    tester,
  ) async {
    late Library state;
    await tester.runAsync(() async {
      state = await library(values: {'demo': true});
    });
    await tester.pumpWidget(ManxiaApp(library: state));
    await tester.pumpAndSettle();
    expect(find.text('书架，等你放上第一本漫画'), findsOneWidget);
    expect(find.text('演示书架'), findsNothing);
    expect(find.text('下一段故事'), findsNothing);
    for (final comic in state.samples) {
      expect(find.text(comic.title), findsNothing);
    }
    expect(state.favorites, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('legacy six-pick cache cannot truncate twelve-pick collection', (
    tester,
  ) async {
    late Library state;
    late Discovery data;
    await tester.runAsync(() async {
      state = await library();
      data = await snapshot();
      final date = DateTime.now().toUtc().add(const Duration(hours: 8));
      await state.prefs.setString(
        'daily.picks.dm5',
        jsonEncode({
          'key': '${date.toIso8601String().substring(0, 10)}/0',
          'books': data.books.take(6).map((b) => b.toJson()).toList(),
        }),
      );
    });
    final source = SnapshotSource(data);
    addTearDown(source.close);
    final opened = <Comic>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DiscoveryPage(
              library: state,
              source: source,
              web: false,
              onOpen: opened.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('collection-每日精选'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byType(DiscoveryCollection), findsOneWidget);
    final grid = tester.widget<ComicGrid>(find.byType(ComicGrid).last);
    expect(grid.books, hasLength(12));
    expect(grid.books.map((b) => b.path).toSet(), hasLength(12));
    expect(find.text('12 部漫画'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'a source collection loads its actual next page without unrelated category requests',
    (tester) async {
      final requests = <String>[];
      var posts = 0;
      final client = MockClient((request) async {
        requests.add(
          request.method == 'POST' ? request.body : request.url.path,
        );
        if (request.method == 'POST') {
          if (posts++ == 0) return http.Response('unavailable', 503);
          return http.Response(
            jsonEncode({
              'UpdateComicItems': [
                {
                  'UrlKey': 'manhua-two',
                  'Title': '第二册',
                  'ShowPicUrlB': 'https://images.cdndm5.com/2.jpg',
                },
                {
                  'UrlKey': 'manhua-three',
                  'Title': '第三册',
                  'ShowPicUrlB': 'https://images.cdndm5.com/3.jpg',
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response(
          '''<script>var pagesize = "2"; var pageindex = "1";</script>
        <ul><li><div class="manga-list-2-cover"><a href="/manhua-one/" title="第一册"><img src="https://images.cdndm5.com/1.jpg"></a></div></li>
        <li><div class="manga-list-2-cover"><a href="/manhua-two/" title="第二册"><img src="https://images.cdndm5.com/2.jpg"></a></div></li></ul>''',
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      });
      final source = Dm5Source(client: client);
      addTearDown(source.close);
      late Library state;
      await tester.runAsync(() async {
        state = await library();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SourceBrowser(
                source: source,
                library: state,
                web: false,
                initialPath: '/manhua-curated/',
                onOpen: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(requests, ['/manhua-curated/']);
      await tester.ensureVisible(find.text('加载更多'));
      await tester.tap(find.text('加载更多'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ComicGrid>(find.byType(ComicGrid)).books,
        hasLength(2),
      );
      await tester.ensureVisible(find.byKey(const ValueKey('source-retry')));
      await tester.tap(find.byKey(const ValueKey('source-retry')));
      await tester.pumpAndSettle();
      expect(requests.where((r) => r.contains('pageindex=2')), hasLength(2));
      final grid = tester.widget<ComicGrid>(find.byType(ComicGrid));
      expect(grid.books.map((b) => b.path), [
        '/manhua-one/',
        '/manhua-two/',
        '/manhua-three/',
      ]);
      expect(requests.last, contains('pageindex=2'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final width in [390.0, 754.0, 1440.0]) {
    testWidgets('real discovery and empty shelf fit $width pixels', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late Library state;
      late OfflineLibrary offline;
      await tester.runAsync(() async {
        state = await library(values: {'demo': true});
        await state.setOption('startTab', 1);
        final data = await snapshot();
        await state.prefs.setString(
          'discovery.cache.dm5',
          jsonEncode(data.toJson()),
        );
        final store = MemoryBlobStore();
        offline = OfflineLibrary(state, Dm5Source(), store: store);
        if (Platform.environment['MANXIA_CAPTURE_DIR'] != null) {
          for (final comic in data.books) {
            final key = offline.key(comic.cover);
            final image = File('.cache/images/$key');
            if (await image.exists()) {
              await store.write(key, await image.readAsBytes());
              offline.entries.add({'comic': comic.toJson(), 'coverKey': key});
            }
          }
        }
      });
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: ManxiaApp(library: state),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      expect(find.text('今日主推'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, key, 'discovery-${width.toInt()}');
      if (width == 390) {
        final all = find.byKey(const ValueKey('collection-每日精选'));
        await tester.ensureVisible(all);
        await tester.tap(all);
        await tester.pumpAndSettle();
        expect(
          tester.widget<ComicGrid>(find.byType(ComicGrid).last).books,
          hasLength(12),
        );
        await capture(tester, key, 'daily-full-390');
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('排行'));

        await tester.tap(find.text('排行'));
        await tester.pumpAndSettle();
        await capture(tester, key, 'ranking-390');
        expect(tester.takeException(), isNull);
      }
      await tester.tap(
        find.text(width < 1000 ? '书架' : '我的书架').hitTestable().first,
      );
      await tester.pumpAndSettle();
      expect(find.text('书架，等你放上第一本漫画'), findsOneWidget);
      await capture(tester, key, 'empty-shelf-${width.toInt()}');
      expect(tester.takeException(), isNull);
      if (width == 390) {
        await tester.runAsync(() async {
          final data = await snapshot();
          for (final comic in data.books.take(7)) {
            await state.toggle(comic);
          }
          final restored = Library(state.prefs);
          await restored.load();
          expect(restored.favorites, hasLength(7));
        });
        await tester.pumpAndSettle();
        expect(find.text('书架，等你放上第一本漫画'), findsNothing);
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 180));
        });
        await tester.pumpAndSettle();
        await capture(tester, key, 'shelf-favorites-390');
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      offline.source.close();
      OfflineLibrary.instance = null;
    });
  }
  testWidgets('English discovery supports 150 percent type on a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late Library state;
    await tester.runAsync(() async {
      state = await library();
      await state.setOption('language', 'en');
      await state.setOption('textScale', 1.5);
      await state.setOption('startTab', 1);
      await state.prefs.setString(
        'discovery.cache.dm5',
        jsonEncode((await snapshot()).toJson()),
      );
    });
    await tester.pumpWidget(ManxiaApp(library: state));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pumpAndSettle();
    expect(find.text("Today's pick"), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(const ValueKey('collection-每日精选')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
