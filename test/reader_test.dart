import 'dart:ui' as ui;
import 'package:manxia/data/offline_library.dart';
import 'package:manxia/platform/blob_store.dart';
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
  tearDown(() {
    OfflineLibrary.instance?.source.close();
    OfflineLibrary.instance = null;
  });
  testWidgets(
    'quick repeated next-page taps retain every intent and reverse continuously',
    (tester) async {
      late Library library;
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        library = Library(await SharedPreferences.getInstance());
        await library.load();
        await cacheReaderImages(library);
      });
      final comic = library.samples.first;
      final source = Dm5Source(
        client: MockClient(
          (_) async => http.Response(
            "var newImgs=[${List.generate(6, (i) => "'https://images.cdndm5.com/${i + 1}.jpg'").join(',')}];",
            200,
          ),
        ),
      );
      addTearDown(source.close);
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
      await settleFirstFrame(tester);
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byTooltip('下一页'));
        await tester.pump(const Duration(milliseconds: 30));
      }
      await settleFirstFrame(tester);
      expect(
        find.text('4 / 6'),
        findsOneWidget,
        reason:
            'Three taps must not collapse into one target while the first page is moving.',
      );
      await tester.tap(find.byTooltip('上一页'));
      await tester.pump(const Duration(milliseconds: 45));
      final controller = tester
          .widget<PageView>(find.byType(PageView))
          .controller!;
      final pose = controller.page!;
      await tester.tap(find.byTooltip('下一页'));
      await tester.pump();
      expect(controller.page, closeTo(pose, .001));
      await settleFirstFrame(tester);
      expect(find.text('4 / 6'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'interrupting reader chrome keeps the page viewport and progress fixed',
    (tester) async {
      late Library library;
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        library = Library(await SharedPreferences.getInstance());
        await library.load();
        await cacheReaderImages(library);
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
      await settleFirstFrame(tester);
      await tester.tap(find.byTooltip('下一页'));
      await settleFirstFrame(tester);
      final viewport = tester.getRect(find.byType(PagedSurface));
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump(const Duration(milliseconds: 70));
        expect(tester.getRect(find.byType(PagedSurface)), viewport);
      }
      await settleFirstFrame(tester);
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
        await cacheReaderImages(library);
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
      await settleFirstFrame(tester);
      expect(find.text('4–5 / 6'), findsOneWidget);
      await tester.tap(find.byTooltip('下一页'));
      await settleFirstFrame(tester);
      expect(find.text('6 / 6'), findsOneWidget);
      await tester.tap(find.byTooltip('上一页'));
      await settleFirstFrame(tester);
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
        await cacheReaderImages(library);
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
      await settleFirstFrame(tester);
      await tester.tap(find.byTooltip('下一页'));
      await settleFirstFrame(tester);
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
      await cacheReaderImages(library);
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
    await settleFirstFrame(tester);
    expect(find.text('1 / 2'), findsOneWidget);
    await tester.tap(find.byTooltip('下一页'));
    await settleFirstFrame(tester);
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

// These regressions require decoded images. A URL list with mocked HTTP400
// images must not be mistaken for a successfully presented reading chapter.
Future<void> cacheReaderImages(Library library) async {
  final source = Dm5Source();
  final store = MemoryBlobStore();
  final offline = OfflineLibrary(library, source, store: store);
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const ui.Color(0xff47775e), ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(120, 180);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  for (var i = 1; i <= 6; i++) {
    final url = 'https://images.cdndm5.com/$i.jpg', key = 'reader-frame-$i';
    await store.write(key, bytes!.buffer.asUint8List());
    offline.entries.add({
      'comic': {'cover': url},
      'coverKey': key,
    });
  }
  image.dispose();
  picture.dispose();
}

Future<void> settleFirstFrame(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  await tester.pumpAndSettle();
}
