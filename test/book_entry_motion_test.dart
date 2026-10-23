import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/dm5_source.dart';
import 'package:manxia/data/library.dart';
import 'package:manxia/data/offline_library.dart';
import 'package:manxia/platform/blob_store.dart';
import 'package:manxia/ui/app_shell.dart';
import 'package:manxia/ui/comic_image.dart';
import 'package:manxia/ui/cover_arrival.dart';
import 'package:manxia/ui/book_object.dart';
import 'package:manxia/ui/book_link.dart';
import 'package:manxia/ui/living_shelf.dart';
import 'package:manxia/ui/room_motion.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'each grid book supplies a unique flight even for repeated comics',
    (tester) async {
      const comic = Comic(
        path: '/manhua-motion/',
        title: 'Book',
        cover: 'offline:missing',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ComicGrid(
              books: const [comic, comic],
              web: false,
              onOpen: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final heroes = tester.widgetList<Hero>(find.byType(Hero)).toList();
      expect(heroes, hasLength(2));
      expect(heroes.map((h) => h.tag).toSet(), hasLength(2));
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'decoded cover keeps paper placeholder during its first arrival',
    (tester) async {
      late OfflineLibrary offline;
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        final library = Library(await SharedPreferences.getInstance());
        await library.load();
        final store = MemoryBlobStore();
        offline = OfflineLibrary(library, Dm5Source(), store: store);
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder).drawRect(
          const ui.Rect.fromLTWH(0, 0, 12, 18),
          ui.Paint()..color = const ui.Color(0xff47775e),
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(12, 18);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await store.write('arrival-regression', bytes!.buffer.asUint8List());
        image.dispose();
        picture.dispose();
      });
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 120,
              height: 180,
              child: ComicImage('offline:arrival-regression', web: false),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 60));
      });
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      await tester.pump();
      expect(
        tester.widget<CoverArrival>(find.byType(CoverArrival)).ready,
        isTrue,
      );
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.image_outlined), findsNothing);
      await tester.pumpWidget(const SizedBox());
      offline.source.close();
      OfflineLibrary.instance = null;
    },
  );
  testWidgets(
    'a grid occurrence opens a hinged flight and returns safely midway',
    (tester) async {
      const comic = Comic(
        path: '/manhua-flight/',
        title: 'Flight book',
        cover: 'offline:missing-flight',
      );
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: Builder(
            builder: (context) => Scaffold(
              body: ComicGrid(
                books: const [comic, comic],
                web: false,
                onOpen: (book) {
                  final tag = BookLink.takeTag(context, book);
                  navigator.currentState!.push(
                    PageRouteBuilder<void>(
                      opaque: false,
                      transitionDuration: RoomMotion.book,
                      reverseTransitionDuration: RoomMotion.bookReturn,
                      pageBuilder: (_, _, _) => Scaffold(
                        body: Center(
                          child: SizedBox(
                            width: 200,
                            height: 280,
                            child: BookFlight(
                              tag: tag,
                              child: const BookObject(
                                comic,
                                web: false,
                                opening: 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                      transitionsBuilder: (_, animation, _, child) =>
                          OpenBookTransition(
                            animation: animation,
                            comic: comic,
                            web: false,
                            child: child,
                          ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(InkWell).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 260));
      expect(
        tester
            .widgetList<BookObject>(find.byType(BookObject))
            .any((b) => b.opening > 0 && b.opening < 1),
        isTrue,
      );
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(navigator.currentState!.canPop(), isFalse);
      expect(find.byType(Hero), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('reduced motion keeps grid covers immediate without a flight', (
    tester,
  ) async {
    const comic = Comic(
      path: '/reduced/',
      title: 'Reduced',
      cover: 'offline:missing-reduced',
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Scaffold(
          body: ComicGrid(books: const [comic], web: false, onOpen: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Hero), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
