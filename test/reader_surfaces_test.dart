import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:manxia/data/library.dart';
import 'package:manxia/data/dm5_source.dart';
import 'package:manxia/data/offline_library.dart';
import 'package:manxia/platform/blob_store.dart';
import 'package:manxia/ui/reader_surfaces.dart';

Future<Uint8List> longImage() async {
  final pixels = Uint8List(200 * 1200 * 4);
  for (var i = 0; i < pixels.length; i += 4) {
    pixels[i] = 80;
    pixels[i + 1] = 120;
    pixels[i + 2] = 100;
    pixels[i + 3] = 255;
  }
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    200,
    1200,
    ui.PixelFormat.rgba8888,
    done.complete,
  );
  final image = await done.future;
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  testWidgets(
    'retrying a failed page immediately shows a single loading state',
    (tester) async {
      final source = Dm5Source();
      final store = _RetryStore();
      late Uint8List bytes;
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        final library = Library(await SharedPreferences.getInstance());
        await library.load();
        OfflineLibrary(library, source, store: store);
        bytes = await longImage();
      });
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        if (!store.retry.isCompleted) store.retry.complete(null);
        source.close();
        OfflineLibrary.instance = null;
      });
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(
            body: PagePicture('offline:retry-page', web: false, strip: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('重新加载图片'), findsOneWidget);
      await tester.tap(find.text('重新加载图片'));
      await tester.pump();
      expect(find.text('重新加载图片'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      store.retry.complete(bytes);
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('重新加载图片'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  test('white margin detector trims borders and retains the center', () {
    final bytes = Uint8List(100 * 100 * 4)..fillRange(0, 40000, 255);
    for (var y = 10; y < 90; y++) {
      for (var x = 10; x < 90; x++) {
        final p = (y * 100 + x) * 4;
        bytes[p] = 0;
        bytes[p + 1] = 0;
        bytes[p + 2] = 0;
      }
    }
    expect(
      detectWhiteMargins(bytes, 100, 100),
      const Rect.fromLTRB(10, 10, 90, 90),
    );
  });
  testWidgets(
    'continuous strip restores a position inside a long page and follows jumps',
    (tester) async {
      late List<String> urls;
      late Dm5Source source;
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        final library = Library(await SharedPreferences.getInstance());
        await library.load();
        source = Dm5Source();
        final offline = OfflineLibrary(
          library,
          source,
          store: MemoryBlobStore(),
        );
        await offline.initialize();
        final bytes = await longImage();
        await offline.importImages(
          'test',
          List.generate(4, (i) => (name: '$i.png', bytes: bytes)),
        );
        urls = (await offline.pages(
          offline.entries.single['chapter']['path'],
        ))!;
      });
      final control = ReaderControl();
      var page = -1;
      double fraction = -1;
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 400,
            height: 600,
            child: StripSurface(
              urls: urls,
              web: false,
              startPage: 1,
              position: .3,
              control: control,
              onPosition: (p, f) {
                page = p;
                fraction = f;
              },
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      expect(page, 1);
      expect(fraction, closeTo(.3, .02));
      control.go(3);
      await tester.pumpAndSettle();
      expect(page, 3);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      control.dispose();
      source.close();
      OfflineLibrary.instance = null;
      Dm5Source.offlinePages = null;
      Dm5Source.offlineDetail = null;
    },
  );
}

class _RetryStore extends MemoryBlobStore {
  int reads = 0;
  final retry = Completer<Uint8List?>();
  @override
  Future<Uint8List?> read(String key) async =>
      ++reads == 1 ? null : retry.future;
}
