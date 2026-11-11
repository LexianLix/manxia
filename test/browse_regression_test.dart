import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/dm5_source.dart';
import 'package:manxia/data/discovery.dart';
import 'package:manxia/data/library.dart';
import 'package:manxia/data/source_catalog.dart';
import 'package:manxia/ui/glass_navigation.dart';
import 'package:manxia/ui/materials.dart';
import 'package:manxia/ui/source_browser.dart';
import 'package:manxia/ui/discovery_page.dart';
import 'package:manxia/ui/book_link.dart';
import 'package:manxia/ui/localized_text.dart';

void main() {
  testWidgets(
    'the discovery catalog stays virtual and survives section changes',
    (tester) async {
      tester.view.physicalSize = const Size(390, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final source = _Catalog(count: 240);
      final navigation = ValueNotifier<String?>(null);
      addTearDown(navigation.dispose);
      final navigator = GlobalKey<NavigatorState>();
      addTearDown(source.close);
      final library = (await tester.runAsync(() async {
        final l = Library(await SharedPreferences.getInstance());
        await l.load();
        await l.prefs.setString(
          'discovery.cache.dm5',
          jsonEncode((await source.discover()).toJson()),
        );
        return l;
      }))!;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: Scaffold(
            body: DiscoveryPage(
              library: library,
              source: source,
              web: false,
              scrollable: true,
              onOpen: (_) => navigator.currentState!.push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      const Scaffold(body: Text('Book detail fixture')),
                ),
              ),
              navigationRequest: navigation,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Finder label(String value) =>
          find.byWidgetPredicate((w) => w is LocalizedText && w.data == value);
      await tester.tap(label('全部漫画'));
      await tester.pumpAndSettle();
      int mountedBooks() =>
          tester.widgetList<BookLink>(find.byType(BookLink)).length;
      expect(
        mountedBooks(),
        lessThan(45),
        reason: 'A long catalog must not build all 240 covers.',
      );
      expect(source.catalogCalls, 1);
      final viewport = tester
          .widget<CustomScrollView>(
            find.byKey(const PageStorageKey('discovery-scroll')),
          )
          .controller!;
      viewport.jumpTo(1600);
      await tester.pumpAndSettle();
      expect(mountedBooks(), lessThan(45));
      expect(source.requests, isEmpty);
      final opened = tester.widgetList<BookLink>(find.byType(BookLink)).first;
      opened.onOpen(opened.comic);
      await tester.pumpAndSettle();
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(viewport.offset, closeTo(1600, 1));
      navigation.value = '逛一逛';
      await tester.pumpAndSettle();
      navigation.value = '全部漫画';
      await tester.pumpAndSettle();
      expect(viewport.offset, closeTo(1600, 1));
      viewport.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.tap(label('逛一逛'));
      await tester.pumpAndSettle();
      await tester.tap(label('全部漫画'));
      await tester.pumpAndSettle();
      expect(
        source.catalogCalls,
        1,
        reason: 'Switching sections must preserve the fetched catalog.',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      library.dispose();
    },
  );
  testWidgets('navigation refraction stays behind stationary icon anchors', (
    tester,
  ) async {
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (c, set) => Scaffold(
            bottomNavigationBar: FrostedNavigation(
              selectedIndex: selected,
              onSelected: (i) => set(() => selected = i),
            ),
          ),
        ),
      ),
    );
    final stack = tester
        .widgetList<Stack>(find.byType(Stack))
        .firstWhere(
          (s) => s.children.any(
            (w) =>
                w is Positioned &&
                w.child is IgnorePointer &&
                (w.child as IgnorePointer).child is GlassLens,
          ),
        );
    final lens = stack.children.indexWhere(
      (w) =>
          w is Positioned &&
          w.child is IgnorePointer &&
          (w.child as IgnorePointer).child is GlassLens,
    );
    final glyph = stack.children.indexWhere((w) => w.key == const ValueKey(0));
    expect(
      lens,
      lessThan(glyph),
      reason: 'Refraction must never resample and visually shift the glyphs.',
    );
    final positions = [
      for (var i = 0; i < 4; i++)
        tester.getCenter(find.byKey(ValueKey('navigation-icon-$i'))),
    ];
    for (final i in [1, 3, 0, 2]) {
      await tester.tap(
        find.byTooltip(['Library', 'Explore', 'History', 'Settings'][i]),
      );
      for (final ms in [16, 80, 400]) {
        await tester.pump(Duration(milliseconds: ms));
        for (var j = 0; j < 4; j++) {
          expect(
            tester.getCenter(find.byKey(ValueKey('navigation-icon-$j'))),
            positions[j],
          );
        }
      }
    }
  });

  testWidgets(
    'catalog prefetches near its end once, pauses on errors and retries explicitly',
    (tester) async {
      tester.view.physicalSize = const Size(390, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final library = (await tester.runAsync(() async {
        final l = Library(await SharedPreferences.getInstance());
        await l.load();
        return l;
      }))!;
      final source = _Catalog();
      addTearDown(source.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                SourceBrowser(
                  source: source,
                  library: library,
                  web: false,
                  onOpen: (_) {},
                  initialPath: '/all/',
                  sliver: true,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(source.requests, isEmpty);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -2800));
      await tester.pump(const Duration(milliseconds: 150));
      expect(source.requests, [2]);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pump(const Duration(milliseconds: 100));
      expect(source.requests, [
        2,
      ], reason: 'Overlapping scroll events must not duplicate requests.');
      source.pending.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(source.requests, [
        2,
      ], reason: 'A failed page must not enter an automatic retry loop.');
      source.pending = Completer<List<Comic>>();
      await tester.ensureVisible(find.byKey(const ValueKey('source-retry')));
      await tester.tap(find.byKey(const ValueKey('source-retry')));
      await tester.pump();
      expect(source.requests, [2, 2]);
      source.pending.complete([]);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(source.requests, [2, 2]);
      expect(find.text('加载更多'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      library.dispose();
    },
  );
}

class _Catalog extends Dm5Source {
  _Catalog({this.count = 24});
  final int count;
  int catalogCalls = 0;
  final requests = <int>[];
  var pending = Completer<List<Comic>>();
  @override
  Future<Map<String, String>> categories() async => {'全部': '/all/'};
  @override
  Future<Discovery> discover() async => Discovery(
    books: const [Comic(path: '/preview/', title: 'Preview', cover: '')],
    sections: const {},
    ranks: const {},
    capturedAt: 'fixture',
  );
  @override
  Future<SourceCatalog> catalog(String path) async {
    catalogCalls++;
    return SourceCatalog(
      books: [
        for (var i = 0; i < count; i++)
          Comic(path: '/book-$i/', title: 'Book $i', cover: ''),
      ],
      sorts: {},
      statuses: {},
      parameters: {'pagesize': '24'},
    );
  }

  @override
  Future<List<Comic>> catalogNext(Map<String, String> parameters, int page) {
    requests.add(page);
    return pending.future;
  }
}
