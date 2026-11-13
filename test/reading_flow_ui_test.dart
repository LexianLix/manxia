import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/dm5_source.dart';
import 'package:manxia/data/library.dart';
import 'package:manxia/data/offline_library.dart';
import 'package:manxia/data/source_hub.dart';
import 'package:manxia/platform/blob_store.dart';
import 'package:manxia/ui/detail_page.dart';
import 'package:manxia/ui/reader_page.dart';
import 'package:manxia/ui/room_motion.dart';
import 'package:manxia/ui/search_page.dart';
import 'package:manxia/ui/living_shelf.dart';
import 'package:manxia/ui/glass_navigation.dart';
import 'features_test.dart' as fixtures;

const book = Comic(
  path: '/reading-flow/',
  title: '星光与远方',
  author: '作者',
  cover: 'offline:flow-cover',
  description: '沿着故事里的光，寻找下一个目的地。',
);

class _FlowSource extends Dm5Source {
  @override
  Future<ComicDetail> detail(Comic _) async => ComicDetail(book, [
    for (var index = 80; index > 0; index--)
      Chapter('/chapter-$index/', '第$index话'),
  ]);
  @override
  Future<List<String>> pages(String path) async => [];
}

class _SearchHub extends SourceHub {
  _SearchHub(super.library);
  final slow = Completer<List<Comic>>();
  final calls = <String>[];
  bool broken = true;
  @override
  Future<List<Comic>> searchIn(String id, String query) async {
    calls.add(id);
    if (id == 'dm5') return [book];
    if (id == 'slow') return slow.future;
    if (broken) throw SourceException('fixture offline');
    return [
      const Comic(
        path: '/recovered/',
        title: '恢复的版本',
        author: '另一位作者',
        sourceId: 'broken',
        cover: '',
      ),
    ];
  }
}

void main() {
  setUpAll(() async {
    if (Platform.environment['MANXIA_CAPTURE_DIR'] == null) return;
    await (FontLoader('ArchiveSerif')..addFont(
          rootBundle.load('assets/fonts/SourceHanSerifCN-Regular.otf'),
        ))
        .load();
    await (FontLoader(
      'RoomSans',
    )..addFont(rootBundle.load('assets/fonts/ManxiaSansSC-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final count in [2, 5]) {
    testWidgets('$count books retain distinct detail and continue actions', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late Library library;
      final source = _FlowSource();
      final store = MemoryBlobStore();
      final books = <Comic>[];
      await tester.runAsync(() async {
        library = await fixtures.library();
        await library.setOption('parallax', false);
        final catalog =
            jsonDecode(await rootBundle.loadString('assets/catalog.json'))
                as List;
        for (var index = 0; index < count; index++) {
          final original = Comic.fromJson(
            Map<String, dynamic>.from(catalog[index]),
          );
          final cached = File(
            '.cache/images/${sha256.convert(utf8.encode(original.cover))}',
          );
          final bytes =
              Platform.environment['MANXIA_CAPTURE_DIR'] != null &&
                  await cached.exists()
              ? await cached.readAsBytes()
              : (await rootBundle.load(
                  'assets/characters/xiaxia/idle.png',
                )).buffer.asUint8List();
          await store.write('shelf-$index', bytes);
          books.add(
            Comic(
              path: original.path,
              title: original.title,
              cover: 'offline:shelf-$index',
            ),
          );
        }
        await library.save(
          ReadingRecord(
            comic: books.first,
            chapterPath: '/old/',
            chapterTitle: '第3话',
            page: 2,
            total: 10,
            updatedAt: 1,
          ),
        );
        OfflineLibrary(library, source, store: store);
      });
      addTearDown(() {
        source.close();
        OfflineLibrary.instance = null;
      });
      final opened = <Comic>[], continued = <Comic>[];
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: _app(
            Scaffold(
              appBar: AppBar(title: const Text('我的书架')),
              body: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: LivingShelf(
                  books: books,
                  library: library,
                  web: false,
                  onOpen: opened.add,
                  onContinue: continued.add,
                ),
              ),
              bottomNavigationBar: FrostedNavigation(
                selectedIndex: 0,
                onSelected: (_) {},
                highQuality: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 180)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('继续阅读'));
      expect(continued.single.path, books.first.path);
      expect(opened, isEmpty);
      await tester.tap(find.byTooltip(books.first.title));
      expect(opened.single.path, books.first.path);
      await _capture(tester, boundary, 'shelf-$count');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  for (final size in [const Size(390, 844), const Size(320, 568)]) {
    for (final reduced in [false, true]) {
      testWidgets(
        'detail actions stay reachable through scroll and return at $size, reduced=$reduced',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          late Library library;
          final source = _FlowSource();
          final store = MemoryBlobStore();
          await tester.runAsync(() async {
            library = await fixtures.library();
            await library.toggle(book);
            library.updates[book.path] = {
              'changed': true,
              'fingerprint': '/chapter-80/',
            };
            await store.write(
              'flow-cover',
              (await rootBundle.load(
                'assets/characters/xiaxia/idle.png',
              )).buffer.asUint8List(),
            );
            OfflineLibrary(library, source, store: store);
          });
          addTearDown(() {
            source.close();
            OfflineLibrary.instance = null;
          });
          final boundary = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: _app(
                DetailPage(
                  comic: book,
                  library: library,
                  source: source,
                  web: false,
                ),
                reduced: reduced,
                scale: size.width == 320 ? 1.5 : 1,
                locale: reduced ? const Locale('en') : const Locale('zh', 'CN'),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: 'Initial detail layout',
          );
          expect(library.updates[book.path]!['changed'], true);
          final button = find.byKey(const ValueKey('detail-read'));
          final footer = tester.getRect(button);
          expect(footer.bottom, lessThan(size.height));
          expect(footer.height, greaterThanOrEqualTo(40));
          expect(find.byTooltip('加入书架'), findsNothing);
          await tester.drag(
            find.byType(CustomScrollView),
            const Offset(0, -500),
          );
          await tester.pumpAndSettle();
          expect(tester.getRect(button), footer);
          final scroll = tester.state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(CustomScrollView),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          final offset = scroll.position.pixels;
          expect(offset, greaterThan(0));
          await tester.tap(button);
          await tester.pumpAndSettle();
          expect(find.byType(ReaderPage), findsOneWidget);
          Navigator.of(tester.element(find.byType(ReaderPage))).pop();
          await tester.pumpAndSettle();
          expect(scroll.position.pixels, closeTo(offset, .5));
          expect(tester.getRect(button), footer);
          expect(tester.takeException(), isNull);
          if (!reduced) {
            scroll.position.jumpTo(0);
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 150)),
            );
            await tester.pumpAndSettle();
            await _capture(tester, boundary, 'detail-${size.width.toInt()}');
          }
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
  testWidgets(
    'fast source results open before slow sources finish and failed-only retry retains the list',
    (tester) async {
      late Library library;
      await tester.runAsync(() async => library = await fixtures.library());
      for (final id in ['slow', 'broken']) {
        library.sourceProfiles.add({
          'id': id,
          'name': id,
          'baseUrl': 'https://$id.example',
          'cards': '.book',
          'title': '.name',
          'link': 'a',
          'cover': 'img',
          'chapters': 'a',
          'pages': 'img',
        });
      }
      final source = _SearchHub(library);
      addTearDown(source.close);
      final opened = <Comic>[];
      await tester.pumpWidget(
        _app(
          ComicSearchPage(
            library: library,
            source: source,
            web: false,
            onOpen: opened.add,
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '星光');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      final firstRow = find.widgetWithText(ListTile, '作者 · 动漫屋');
      final firstRect = tester.getRect(firstRow);
      await tester.tap(find.text('作者 · 动漫屋'));
      expect(opened.single.path, book.path);
      source.slow.complete([]);
      await tester.pumpAndSettle();
      expect(tester.getRect(firstRow), firstRect);
      source.broken = false;
      await tester.tap(find.byTooltip('重试失败的书源'));
      await tester.pumpAndSettle();
      expect(source.calls.where((id) => id == 'dm5'), hasLength(1));
      expect(source.calls.where((id) => id == 'broken'), hasLength(2));
      expect(find.text('作者 · 动漫屋'), findsOneWidget);
      expect(find.text('恢复的版本'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

Widget _app(
  Widget home, {
  bool reduced = false,
  double scale = 1,
  Locale locale = const Locale('zh', 'CN'),
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: locale,
  supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  theme: ThemeData(
    fontFamily: 'RoomSans',
    fontFamilyFallback: const ['ArchiveSerif'],
    appBarTheme: const AppBarTheme(
      toolbarHeight: 54,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff286c85)),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: RoomPageTransitions()},
    ),
  ),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      disableAnimations: reduced,
      textScaler: TextScaler.linear(scale),
    ),
    child: child!,
  ),
  home: home,
);

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundary,
  String name,
) async {
  final directory = Platform.environment['MANXIA_CAPTURE_DIR'];
  if (directory == null) return;
  await tester.runAsync(() async {
    await Directory(directory).create(recursive: true);
    final image =
        await (boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage();
    await File('$directory/$name.png').writeAsBytes(
      (await image.toByteData(
        format: ui.ImageByteFormat.png,
      ))!.buffer.asUint8List(),
    );
    image.dispose();
  });
}
