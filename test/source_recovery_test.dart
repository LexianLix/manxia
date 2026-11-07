import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/dm5_source.dart';
import 'package:manxia/data/library.dart';
import 'package:manxia/data/offline_library.dart';
import 'package:manxia/platform/blob_store.dart';
import 'package:manxia/data/source_hub.dart';
import 'package:manxia/ui/app_shell.dart';
import 'package:manxia/ui/book_link.dart';
import 'package:manxia/ui/book_navigation.dart';
import 'package:manxia/ui/detail_page.dart';
import 'package:manxia/ui/reader_page.dart';
import 'package:manxia/ui/room_motion.dart';
import 'package:manxia/ui/search_page.dart';
import 'package:manxia/ui/source_search_page.dart';

const original = Comic(
  path: '/manhua-original/',
  title: '测试漫画',
  cover: 'offline:original',
);
Map<String, dynamic> profile(String id) => {
  'id': id,
  'name': '$id 书源',
  'baseUrl': 'https://$id.example',
  'search': '/search?q={query}',
  'cards': '.book',
  'title': '.name',
  'link': 'a',
  'cover': 'img',
  'chapters': '.chapters a',
  'pages': '.pages img',
};
http.Response catalog(String title) => http.Response(
  '<div class="book"><a href="/book/"><span class="name">$title</span><img src="/cover.jpg"></a></div>',
  200,
  headers: {'content-type': 'text/html; charset=utf-8'},
);
Future<Library> state() async {
  SharedPreferences.setMockInitialValues({});
  final library = Library(await SharedPreferences.getInstance());
  await library.load();
  await library.toggle(original);
  await library.save(
    const ReadingRecord(
      comic: original,
      chapterPath: '/m-old/',
      chapterTitle: '旧章',
      page: 4,
      total: 20,
      position: .3,
      updatedAt: 10,
    ),
  );
  return library;
}

void main() {
  setUpAll(() async {
    if (Platform.environment['MANXIA_CAPTURE_DIR'] == null) return;
    await (FontLoader('ArchiveSerif')..addFont(
          rootBundle.load('assets/fonts/SourceHanSerifCN-Regular.otf'),
        ))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  testWidgets(
    'discovery search groups matching authors and preserves expanded results on a quick return',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late Library library;
      await tester.runAsync(() async => library = await state());
      library.sourceProfiles.addAll([profile('second'), profile('broken')]);
      final hub = _GroupedHub(library);
      addTearDown(hub.close);
      await tester.runAsync(() async {
        final store = MemoryBlobStore();
        final art = await rootBundle.load('assets/characters/xiaxia/idle.png');
        await store.write('fixture', art.buffer.asUint8List());
        OfflineLibrary(library, hub, store: store);
      });
      addTearDown(() => OfflineLibrary.instance = null);
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => ComicSearchPage(
              library: library,
              source: hub,
              web: false,
              onOpen: (comic) => Navigator.of(context).push(
                comicDetailRoute(
                  context,
                  comic: comic,
                  library: library,
                  source: hub,
                  web: false,
                  flightTag: BookLink.takeTag(context, comic),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '星光');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('作者甲 · 2 个来源'), findsOneWidget);
      final listScroll = find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('作者乙 · second 书源'),
        250,
        scrollable: listScroll,
      );
      expect(find.text('作者乙 · second 书源'), findsOneWidget);
      tester.state<ScrollableState>(listScroll).position.jumpTo(0);
      await tester.pumpAndSettle();
      expect(find.text('部分书源失败：broken 书源'), findsOneWidget);
      await tester.tap(find.text('作者甲 · 2 个来源'));
      await tester.pumpAndSettle();
      expect(find.text('第12话'), findsOneWidget);
      if (Platform.environment['MANXIA_CAPTURE_DIR'] != null) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 180)),
        );
        await tester.pumpAndSettle();
      }
      await _capture(tester, 'grouped-search');
      final scroll = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      scroll.position.jumpTo(60);
      await tester.pump();
      final offset = scroll.position.pixels;
      expect(offset, greaterThan(0));
      await tester.tap(find.widgetWithText(ListTile, '第12话').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final detail = find.byType(DetailPage, skipOffstage: false);
      expect(tester.widget<DetailPage>(detail).comic.sourceId, 'second');
      Navigator.of(tester.element(detail)).pop();
      await tester.pumpAndSettle();
      expect(find.text('第12话'), findsOneWidget);
      expect(scroll.position.pixels, offset);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'all-source lookup ranks matches and keeps successful results after a source fails',
    (tester) async {
      late Library library;
      await tester.runAsync(() async {
        library = await state();
      });
      library.sourceProfiles.addAll([
        profile('match'),
        profile('other'),
        profile('broken'),
      ]);
      final hub = SourceHub(
        library,
        transport: MockClient((request) async {
          return switch (request.url.host) {
            'match.example' => catalog(original.title),
            'other.example' => catalog('另一部漫画'),
            _ => http.Response('offline', 503),
          };
        }),
      );
      addTearDown(hub.close);
      await tester.pumpWidget(
        _app(
          SourceSearchPage(
            comic: original,
            library: library,
            source: hub,
            web: false,
            onOpen: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('搜索全部书源'));
      await tester.pumpAndSettle();
      final grid = tester.widget<ComicGrid>(find.byType(ComicGrid));
      expect(grid.books.map((book) => book.sourceId), ['match', 'other']);
      expect(find.text('部分书源失败：broken 书源'), findsOneWidget);
      expect(library.record(original)?.page, 4);
      await _capture(tester, 'all-sources');
    },
  );
  testWidgets(
    'one-off source lookup rejects stale replies and preserves the original library',
    (tester) async {
      late Library library;
      await tester.runAsync(() async {
        library = await state();
      });
      library.sourceProfiles.addAll([profile('first'), profile('second')]);
      final delayed = Completer<http.Response>();
      final requests = <Uri>[];
      final hub = SourceHub(
        library,
        transport: MockClient((r) async {
          requests.add(r.url);
          if (r.url.path == '/book/') {
            return http.Response(
              '<div class="chapters"><a href="/chapter-1/">第1话</a></div>',
              200,
              headers: {'content-type': 'text/html;charset=utf-8'},
            );
          }
          expect(r.url.queryParameters['q'], original.title);
          return r.url.host == 'first.example'
              ? delayed.future
              : catalog('第二源结果');
        }),
      );
      addTearDown(hub.close);
      final opened = <Comic>[];
      await tester.pumpWidget(
        _app(
          SourceSearchPage(
            comic: original,
            library: library,
            source: hub,
            web: false,
            onOpen: (c) async {
              opened.add(c);
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 280));
      expect(requests.single.host, 'first.example');
      await tester.tap(find.widgetWithText(ChoiceChip, 'second 书源'));
      await tester.pumpAndSettle();
      delayed.complete(catalog('过时结果'));
      await tester.pumpAndSettle();
      final grid = tester.widget<ComicGrid>(find.byType(ComicGrid));
      expect(grid.books.single.sourceId, 'second');
      expect(grid.books.single.title, '第二源结果');
      await tester.ensureVisible(find.text('第二源结果').last);
      await tester.tap(find.text('第二源结果').last);
      await tester.pumpAndSettle();
      expect(find.text('匹配新来源章节'), findsOneWidget);
      await tester.tap(find.text('仅查看详情'));
      await tester.pumpAndSettle();
      expect(opened.single.path, startsWith('custom:second:'));
      expect(library.option<String>('source', 'dm5'), 'dm5');
      expect(library.favorites.single.path, original.path);
      expect(library.record(original)!.chapterPath, '/m-old/');
      expect(library.record(original)!.page, 4);
      await expectLater(
        hub.searchIn('removed', original.title),
        throwsA(isA<SourceException>()),
      );
      expect(requests, hasLength(3));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'unavailable detail opens a configured source and its real catalog without rewriting the original',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late Library library;
      await tester.runAsync(() async {
        library = await state();
      });
      library.sourceProfiles.add(profile('alternative'));
      final hub = _UnavailableHub(
        library,
        transport: MockClient(
          (r) async => r.url.path.startsWith('/search')
              ? catalog('测试漫画·另一版本')
              : http.Response(
                  '<div class="chapters"><a href="/chapter-2/">第2话</a><a href="/chapter-1/">第1话</a></div>',
                  200,
                  headers: {'content-type': 'text/html; charset=utf-8'},
                ),
        ),
      );
      addTearDown(hub.close);
      await tester.runAsync(() async {
        final store = MemoryBlobStore();
        final art = await rootBundle.load('assets/characters/xiaxia/idle.png');
        await store.write('alternative-page', art.buffer.asUint8List());
        OfflineLibrary(library, hub, store: store);
      });
      addTearDown(() => OfflineLibrary.instance = null);
      await tester.pumpWidget(
        _app(
          DetailPage(
            comic: original,
            library: library,
            source: hub,
            web: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('继续阅读'), findsOneWidget);
      expect(find.textContaining('版权方'), findsWidgets);
      await _capture(tester, 'unavailable');
      await tester.ensureVisible(find.text('换源查找'));
      await tester.tap(find.text('换源查找'));
      await tester.pumpAndSettle();
      expect(find.byType(SourceSearchPage), findsOneWidget);
      await _capture(tester, 'alternative-results');
      await tester.ensureVisible(find.text('测试漫画·另一版本').last);
      await tester.tap(find.text('测试漫画·另一版本').last);
      await tester.pumpAndSettle();
      expect(find.text('匹配新来源章节'), findsOneWidget);
      await tester.tap(find.text('第2话'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('从此章节开头继续'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 180)),
      );
      await tester.pump(const Duration(milliseconds: 450));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 180)),
      );
      await tester.pumpAndSettle();
      final current = tester.widget<ReaderPage>(find.byType(ReaderPage));
      await _capture(tester, 'alternative-reader');
      expect(current.comic.sourceId, 'alternative');
      expect(current.chapter.title, '第2话');
      expect(current.initialPage, 0);
      expect(library.option<String>('source', 'dm5'), 'dm5');
      expect(library.favorites.single.path, original.path);
      expect(library.record(original)!.page, 4);
      expect(library.record(current.comic)!.page, 0);
      expect(library.record(current.comic)!.chapterTitle, '第2话');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'with no alternative source the recovery flow opens focused source settings',
    (tester) async {
      late Library library;
      await tester.runAsync(() async {
        library = await state();
      });
      final hub = SourceHub(library);
      addTearDown(hub.close);
      await tester.pumpWidget(
        _app(
          SourceSearchPage(
            comic: original,
            library: library,
            source: hub,
            web: false,
            onOpen: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('还没有其他漫画源'), findsOneWidget);
      await tester.ensureVisible(find.text('配置漫画源'));
      await tester.tap(find.text('配置漫画源'));
      await tester.pumpAndSettle();
      expect(find.text('添加声明式漫画源'), findsOneWidget);
      expect(find.text('质感与性能'), findsNothing);
      expect(tester.takeException(), isNull);
      await _capture(tester, 'source-settings');
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'reader failure matches the failed chapter and preserves the old record',
    (tester) async {
      late Library library;
      await tester.runAsync(() async => library = await state());
      library.sourceProfiles.add(profile('alternative'));
      final hub = _UnavailableHub(
        library,
        transport: MockClient(
          (request) async => request.url.path == '/search'
              ? catalog('可读版本')
              : http.Response(
                  '<div class="chapters"><a href="/new/">第2话</a></div>',
                  200,
                  headers: {'content-type': 'text/html; charset=utf-8'},
                ),
        ),
      );
      addTearDown(hub.close);
      await tester.pumpWidget(
        _app(
          ReaderPage(
            comic: original,
            chapter: const Chapter('/m-new/', '第2话'),
            library: library,
            source: hub,
            web: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('当前书源没有版权'), findsOneWidget);
      await tester.tap(find.text('换源查找'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('可读版本').last);
      await tester.tap(find.text('可读版本').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('原进度：第2话'), findsOneWidget);
      expect(library.record(original)!.page, 4);
      expect(tester.takeException(), isNull);
    },
  );
}

final _boundary = GlobalKey();
Widget _app(Widget child) => RepaintBoundary(
  key: _boundary,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {TargetPlatform.android: RoomPageTransitions()},
      ),
      fontFamily: 'ArchiveSerif',
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff47775e),
        surface: const Color(0xfff7f7f2),
      ),
    ),
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: child,
  ),
);
Future<void> _capture(WidgetTester tester, String name) async {
  final path = Platform.environment['MANXIA_CAPTURE_DIR'];
  if (path == null) return;
  await tester.runAsync(() async {
    await Directory(path).create(recursive: true);
    final render =
        _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await render.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$path/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

class _UnavailableHub extends SourceHub {
  _UnavailableHub(super.library, {super.transport});
  @override
  Future<ComicDetail> detail(Comic c) async {
    if (c.sourceId == 'dm5') throw SourceException('应版权方要求，原站已移除本作品章节链接。');
    return super.detail(c);
  }

  @override
  Future<List<String>> pages(String path) async {
    if (!path.startsWith('custom:')) throw SourceCopyrightException('版权方移除');
    return const ['offline:alternative-page'];
  }
}

class _GroupedHub extends SourceHub {
  _GroupedHub(super.library);

  @override
  Future<List<Comic>> searchIn(String sourceId, String query) async {
    if (sourceId == 'broken') throw SourceException('fixture unavailable');
    return [
      Comic(
        path: '/$sourceId-1/',
        title: '星光',
        author: '作者甲',
        cover: 'offline:fixture',
        sourceId: sourceId,
        latest: sourceId == 'dm5' ? '第10话' : '第12话',
      ),
      if (sourceId == 'second')
        const Comic(
          path: '/second-2/',
          title: '星光',
          author: '作者乙',
          cover: 'offline:fixture',
          sourceId: 'second',
        ),
      if (sourceId == 'dm5')
        for (var index = 0; index < 12; index++)
          Comic(
            path: '/other-$index/',
            title: '相关漫画 ${index + 1}',
            cover: 'offline:fixture',
          ),
    ];
  }

  @override
  Future<ComicDetail> detail(Comic comic) async => ComicDetail(comic, const []);
}
