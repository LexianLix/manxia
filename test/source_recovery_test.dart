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
import 'package:manxia/data/source_hub.dart';
import 'package:manxia/ui/app_shell.dart';
import 'package:manxia/ui/detail_page.dart';
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
      expect(opened.single.path, startsWith('custom:second:'));
      expect(library.option<String>('source', 'dm5'), 'dm5');
      expect(library.favorites.single.path, original.path);
      expect(library.record(original)!.chapterPath, '/m-old/');
      expect(library.record(original)!.page, 4);
      await expectLater(
        hub.searchIn('removed', original.title),
        throwsA(isA<SourceException>()),
      );
      expect(requests, hasLength(2));
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
      final current = tester.widget<DetailPage>(find.byType(DetailPage).last);
      await _capture(tester, 'alternative-detail');
      expect(current.comic.sourceId, 'alternative');
      expect(find.text('MANGA / alternative 书源'), findsOneWidget);
      expect(find.text('开始阅读'), findsOneWidget);
      expect(library.option<String>('source', 'dm5'), 'dm5');
      expect(library.favorites.single.path, original.path);
      expect(library.record(original)!.page, 4);
      expect(library.record(current.comic), isNull);
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
}

final _boundary = GlobalKey();
Widget _app(Widget child) => RepaintBoundary(
  key: _boundary,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
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
}
