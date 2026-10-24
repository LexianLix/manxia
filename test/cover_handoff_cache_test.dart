import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/dm5_source.dart';
import 'package:manxia/data/library.dart';
import 'package:manxia/data/offline_library.dart';
import 'package:manxia/platform/blob_store.dart';
import 'package:manxia/ui/comic_image.dart';
import 'package:manxia/ui/book_object.dart';
import 'package:manxia/ui/cover_arrival.dart';

void main() {
  testWidgets(
    'a presented cover stays decoded on the first flat and 3D flight frame',
    (tester) async {
      late OfflineLibrary offline;
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        final library = Library(await SharedPreferences.getInstance());
        await library.load();
        final store = MemoryBlobStore();
        offline = OfflineLibrary(library, Dm5Source(), store: store);
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(Colors.green, BlendMode.src);
        final picture = recorder.endRecording(),
            image = await picture.toImage(128, 192);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await store.write('handoff-cover', bytes!.buffer.asUint8List());
        image.dispose();
        picture.dispose();
      });
      addTearDown(() {
        offline.source.close();
        OfflineLibrary.instance = null;
      });
      const comic = Comic(
        path: '/cover-handoff/',
        title: 'Cover',
        cover: 'offline:handoff-cover',
      );
      Widget cover(Key key) => SizedBox(
        width: 200,
        height: 300,
        child: ComicImage(comic.cover, key: key, web: false, cacheWidth: 512),
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: cover(const ValueKey('original')))),
      );
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 60));
        });
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(
        tester.widget<CoverArrival>(find.byType(CoverArrival)).ready,
        true,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                cover(const ValueKey('flight')),
                const SizedBox(
                  width: 200,
                  height: 300,
                  child: BookObject(comic, web: false, animateCover: false),
                ),
              ],
            ),
          ),
        ),
      );
      expect(
        find.byType(CoverArrival),
        findsOneWidget,
        reason:
            'A warm flight must not spend its first frame in FutureBuilder waiting.',
      );
      expect(
        tester.widget<CoverArrival>(find.byType(CoverArrival)).ready,
        true,
      );
      final dynamic painter = tester
          .widget<CustomPaint>(
            find.descendant(
              of: find.byType(BookObject),
              matching: find.byType(CustomPaint),
            ),
          )
          .painter;
      expect(
        painter.artwork.hasCover,
        true,
        reason:
            'The binding must also have the presented bitmap on its first frame.',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 1));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      expect(tester.takeException(), isNull);
    },
  );
}
