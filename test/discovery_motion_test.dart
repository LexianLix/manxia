import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/discovery.dart';
import 'package:manxia/data/dm5_source.dart';
import 'package:manxia/data/library.dart';
import 'package:manxia/data/source_catalog.dart';
import 'package:manxia/ui/app_shell.dart';
import 'package:manxia/ui/discovery_page.dart';
import 'package:manxia/ui/localized_text.dart';

void main() {
  testWidgets(
    'refresh keeps the visible catalog and scroll until new content is accepted',
    (tester) async {
      late Library library;
      late Discovery old;
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        library = Library(await SharedPreferences.getInstance());
        await library.load();
        old = Discovery.fromJson(
          jsonDecode(await rootBundle.loadString('assets/discovery.json')),
        );
        await library.prefs.setString(
          'discovery.cache.dm5',
          jsonEncode(old.toJson()),
        );
      });
      final source = _RefreshSource();
      addTearDown(source.close);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              controller: scroll,
              child: DiscoveryPage(
                library: library,
                source: source,
                web: false,
                onOpen: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      scroll.jumpTo(300);
      await tester.pump();
      final oldTitles = tester
          .widgetList<ComicGrid>(find.byType(ComicGrid))
          .expand((g) => g.books)
          .map((b) => b.path)
          .toList();
      const replacement = Comic(
        path: '/fresh/',
        title: 'New catalog book',
        cover: 'offline:fresh',
      );
      source.responses.last.complete(
        Discovery(
          books: const [replacement],
          sections: const {},
          ranks: const {},
          capturedAt: 'now',
        ),
      );
      await tester.pumpAndSettle();
      expect(scroll.offset, 300);
      expect(
        tester
            .widgetList<ComicGrid>(find.byType(ComicGrid))
            .expand((g) => g.books)
            .map((b) => b.path)
            .toList(),
        oldTitles,
      );
      expect(find.text('New catalog book'), findsNothing);
      final updates = find.text(translate('查看新内容', const Locale('en')));
      expect(updates, findsOneWidget);
      await tester.ensureVisible(updates);
      await tester.tap(updates);
      await tester.pumpAndSettle();
      expect(scroll.offset, 0);
      expect(find.text('New catalog book'), findsWidgets);
      expect(updates, findsNothing);
      await tester.tap(find.byTooltip('Refresh discovery'));
      await tester.pump();
      source.responses.last.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(find.text('New catalog book'), findsWidgets);
      expect(
        find.text(translate('刷新失败，已保留当前目录', const Locale('en'))),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'a source with different ranking names selects its first real ranking',
    (tester) async {
      late Library library;
      late _Source source;
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        library = Library(await SharedPreferences.getInstance());
        await library.load();
        final original = Discovery.fromJson(
          jsonDecode(await rootBundle.loadString('assets/discovery.json')),
        );
        source = _Source(
          Discovery(
            books: original.books,
            sections: {},
            ranks: {'近期排行': original.books.take(2).toList()},
            capturedAt: original.capturedAt,
          ),
        );
        await library.prefs.setString(
          'discovery.cache.dm5',
          jsonEncode(source.snapshot.toJson()),
        );
      });
      addTearDown(source.close);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(
            body: SingleChildScrollView(
              child: DiscoveryPage(
                library: library,
                source: source,
                web: false,
                onOpen: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('排行'));
      await tester.tap(find.text('排行'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '近期排行'))
            .selected,
        isTrue,
      );
      expect(find.text('这个来源暂未提供榜单'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'discovery retains filters across tabs and search, keeps results during requests and rejects stale replies',
    (tester) async {
      late Library library;
      late _Source source;
      final captureDir = Platform.environment['MANXIA_CAPTURE_DIR'];
      final boundary = GlobalKey();
      if (captureDir != null) {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
      }
      await tester.runAsync(() async {
        if (captureDir != null) {
          await (FontLoader('ArchiveSerif')..addFont(
                rootBundle.load('assets/fonts/SourceHanSerifCN-Regular.otf'),
              ))
              .load();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
          await Directory(captureDir).create(recursive: true);
        }
        SharedPreferences.setMockInitialValues({});
        library = Library(await SharedPreferences.getInstance());
        await library.load();
        final snapshot = Discovery.fromJson(
          jsonDecode(await rootBundle.loadString('assets/discovery.json')),
        );
        await library.prefs.setString(
          'discovery.cache.dm5',
          jsonEncode(snapshot.toJson()),
        );
        source = _Source(snapshot);
      });
      addTearDown(source.close);
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: ThemeData(fontFamily: 'ArchiveSerif'),
            home: Scaffold(
              body: SingleChildScrollView(
                child: DiscoveryPage(
                  library: library,
                  source: source,
                  web: false,
                  onOpen: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> capture(String name) async {
        if (captureDir == null) return;
        await tester.runAsync(() async {
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await render.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '$captureDir/$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      var tapSequence = 0;
      Future<void> tap(Finder target) async {
        await tester.ensureVisible(target);
        await tester.tap(target);
        if (captureDir != null) {
          tapSequence++;
          await tester.pump();
          for (var i = 0; i < 7; i++) {
            await tester.pump(const Duration(milliseconds: 40));
            await capture('tab-$tapSequence-$i');
          }
        }
        await tester.pumpAndSettle();
      }

      await tap(find.text('分类'));
      final catalogRequest = Completer<SourceCatalog>();
      source.pausedCatalog = catalogRequest;
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, '科幻'));
      await tester.tap(find.widgetWithText(ChoiceChip, '科幻'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 280));
      await capture('catalog-pending');
      catalogRequest.complete(source.catalogResult);
      await tester.pumpAndSettle();
      expect(source.catalogs, ['/manhua-adventure/', '/manhua-scifi/']);
      await tap(find.text('排行'));
      await tap(find.widgetWithText(ChoiceChip, '新番'));
      await tap(find.text('分类'));
      expect(source.categoriesCalls, 1);
      expect(source.catalogs.length, 2);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '科幻'))
            .selected,
        isTrue,
      );
      Future<void> search(String query) async {
        final field = find.byType(TextField).first;
        await tester.ensureVisible(field);
        await tester.enterText(field, query);
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 280));
      }

      bool hasResult(String title) => tester
          .widgetList<ComicGrid>(find.byType(ComicGrid))
          .any((g) => g.books.any((b) => b.title == title));
      await tester.ensureVisible(
        find.byKey(const ValueKey('open-comic-search')),
      );
      await tester.tap(find.byKey(const ValueKey('open-comic-search')));
      await tester.pumpAndSettle();
      await search('one');
      source.searches['one']!.complete(const [
        Comic(path: '/a/', title: 'Result A', cover: 'offline:a'),
      ]);
      await tester.pumpAndSettle();
      await search('two');
      await capture('search-pending');
      expect(hasResult('Result A'), isTrue);
      await search('three');
      source.searches['two']!.complete(const [
        Comic(path: '/b/', title: 'Stale B', cover: 'offline:b'),
      ]);
      source.searches['three']!.complete(const [
        Comic(path: '/c/', title: 'Latest C', cover: 'offline:c'),
      ]);
      await tester.pumpAndSettle();
      expect(hasResult('Stale B'), isFalse);
      expect(hasResult('Latest C'), isTrue);
      await capture('search-latest');
      await search('failure');
      source.searches['failure']!.completeError(StateError('source offline'));
      await tester.pumpAndSettle();
      expect(find.text('搜索暂时不可用'), findsOneWidget);
      await capture('search-error');
      expect(hasResult('Latest C'), isTrue);
      await tester.ensureVisible(find.text('重新搜索'));
      await tester.tap(find.text('重新搜索'));
      await tester.pump();
      source.searches['failure']!.complete(const [
        Comic(path: '/d/', title: 'Recovered D', cover: 'offline:d'),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('搜索暂时不可用'), findsNothing);
      expect(hasResult('Recovered D'), isTrue);
      Navigator.of(tester.element(find.byType(TextField).first)).pop();
      await tester.pumpAndSettle();
      expect(source.categoriesCalls, 1);
      expect(source.catalogs.length, 2);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '科幻'))
            .selected,
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

class _RefreshSource extends Dm5Source {
  final responses = <Completer<Discovery>>[];
  @override
  Future<Discovery> discover() {
    final response = Completer<Discovery>();
    responses.add(response);
    return response.future;
  }
}

class _Source extends Dm5Source {
  _Source(this.snapshot);
  final Discovery snapshot;
  int categoriesCalls = 0;
  final catalogs = <String>[];
  final searches = <String, Completer<List<Comic>>>{};
  Completer<SourceCatalog>? pausedCatalog;
  SourceCatalog get catalogResult => SourceCatalog(
    books: snapshot.books.take(6).toList(),
    sorts: {},
    statuses: {},
    parameters: {},
  );
  @override
  Future<Discovery> discover() async => snapshot;
  @override
  Future<Map<String, String>> categories() async {
    categoriesCalls++;
    return {'冒险': '/manhua-adventure/', '科幻': '/manhua-scifi/'};
  }

  @override
  Future<SourceCatalog> catalog(String path) async {
    catalogs.add(path);
    final pending = pausedCatalog;
    pausedCatalog = null;
    return pending == null ? catalogResult : pending.future;
  }

  @override
  Future<List<Comic>> search(String query) =>
      (searches[query] = Completer<List<Comic>>()).future;
}
