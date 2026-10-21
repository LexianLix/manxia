import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/dm5_source.dart';
import 'package:manxia/data/library.dart';
import 'package:manxia/ui/reader_page.dart';
import 'package:manxia/ui/reader_surfaces.dart';

void main() {
  testWidgets(
    'interrupting reader chrome keeps the page viewport and progress fixed',
    (tester) async {
      late Library library;
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        library = Library(await SharedPreferences.getInstance());
        await library.load();
      });
      final comic = library.samples.first;
      final source = Dm5Source(
        client: MockClient(
          (_) async => http.Response(
            "var newImgs=['https://images.cdndm5.com/1.jpg','https://images.cdndm5.com/2.jpg'];",
            200,
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderPage(
            comic: comic,
            chapter: const Chapter('/m1/', 'Chapter'),
            library: library,
            source: source,
            web: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('下一页'));
      await tester.pumpAndSettle();
      final viewport = tester.getRect(find.byType(PagedSurface));
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump(const Duration(milliseconds: 70));
        expect(tester.getRect(find.byType(PagedSurface)), viewport);
      }
      await tester.pumpAndSettle();
      expect(find.byTooltip('返回目录'), findsNothing);
      expect(find.text('2 / 2'), findsOneWidget);
      expect(library.record(comic)!.page, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      source.close();
    },
  );
  testWidgets(
    'restoring the right page of a spread does not skip the final page',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late Library library;
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        library = Library(await SharedPreferences.getInstance());
        await library.load();
      });
      final source = Dm5Source(
        client: MockClient(
          (_) async => http.Response(
            "var newImgs=[${List.generate(6, (i) => "'https://images.cdndm5.com/${i + 1}.jpg'").join(',')}];",
            200,
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderPage(
            comic: library.samples.first,
            chapter: const Chapter('/m6/', 'Six pages'),
            initialPage: 4,
            library: library,
            source: source,
            web: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('4–5 / 6'), findsOneWidget);
      await tester.tap(find.byTooltip('下一页'));
      await tester.pumpAndSettle();
      expect(find.text('6 / 6'), findsOneWidget);
      await tester.tap(find.byTooltip('上一页'));
      await tester.pumpAndSettle();
      expect(find.text('4–5 / 6'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      source.close();
    },
  );
  testWidgets(
    'the final two-page spread shows its range and disables next page',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late Library library;
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        library = Library(await SharedPreferences.getInstance());
        await library.load();
      });
      final source = Dm5Source(
        client: MockClient(
          (_) async => http.Response(
            "var newImgs=['https://images.cdndm5.com/1.jpg','https://images.cdndm5.com/2.jpg','https://images.cdndm5.com/3.jpg'];",
            200,
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderPage(
            comic: library.samples.first,
            chapter: const Chapter('/m3/', 'Three pages'),
            library: library,
            source: source,
            web: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('下一页'));
      await tester.pumpAndSettle();
      expect(find.text('2–3 / 3'), findsOneWidget);
      final button = find.ancestor(
        of: find.byTooltip('下一页'),
        matching: find.byType(IconButton),
      );
      expect(tester.widget<IconButton>(button).onPressed, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      source.close();
    },
  );
  testWidgets('loaded chapter enables page controls and saves current page', (
    tester,
  ) async {
    late Library library;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      library = Library(await SharedPreferences.getInstance());
      await library.load();
    });
    final comic = library.samples.first;
    final source = Dm5Source(
      client: MockClient(
        (_) async => http.Response(
          "var newImgs=['https://images.cdndm5.com/1.jpg','https://images.cdndm5.com/2.jpg'];",
          200,
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPage(
          comic: comic,
          chapter: const Chapter('/m1/', '第1话'),
          library: library,
          source: source,
          web: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget);
    await tester.tap(find.byTooltip('下一页'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    expect(library.record(comic)!.page, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();
    expect(tester.takeException(), isNull);
    source.close();
  });
}
