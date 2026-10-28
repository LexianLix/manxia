import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/library.dart';
import 'package:manxia/ui/living_shelf.dart';
import 'package:manxia/ui/book_object.dart';

void main() {
  testWidgets(
    'a flick coasts and a new touch interrupts at the rendered pose',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late Library library;
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        library = Library(await SharedPreferences.getInstance());
        await library.load();
      });
      var reduced = false;
      late StateSetter update;
      final books = List.generate(
        7,
        (i) => Comic(
          path: '/orbit-$i/',
          title: 'Book $i',
          cover: 'offline:orbit-$i',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, set) {
              update = set;
              return MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(disableAnimations: reduced),
                child: Scaffold(
                  body: LivingShelf(
                    books: books,
                    library: library,
                    web: false,
                    onOpen: (_) {},
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final first = find.byWidgetPredicate(
        (w) => w is BookObject && w.comic.path == books.first.path,
      );
      final all = tester.widgetList<BookObject>(find.byType(BookObject));
      expect(all.length, 7);
      expect(all.every((b) => b.exposure == 1 && b.flattening > .5), isTrue);
      await tester.fling(
        find.byKey(const ValueKey('shelf-orbit')),
        const Offset(230, 0),
        2600,
      );
      await tester.pump(const Duration(milliseconds: 150));
      final during = tester.getCenter(first);
      await tester.pump(const Duration(milliseconds: 250));
      expect((tester.getCenter(first) - during).distance, greaterThan(8));
      final touch = await tester.startGesture(const Offset(190, 140));
      await tester.pump();
      final stopped = tester.getCenter(first);
      await tester.pump(const Duration(milliseconds: 120));
      expect(tester.getCenter(first), stopped);
      await touch.moveBy(const Offset(-45, 0));
      await touch.moveBy(const Offset(-30, 0));
      await tester.pump();
      expect((tester.getCenter(first) - stopped).distance, greaterThan(2));
      await touch.cancel();
      await tester.pumpAndSettle();
      await tester.fling(
        find.byKey(const ValueKey('shelf-orbit')),
        const Offset(-230, 0),
        2600,
      );
      await tester.pump(const Duration(milliseconds: 100));
      update(() => reduced = true);
      await tester.pump();
      final reducedPose = tester.getCenter(first);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.getCenter(first), reducedPose);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'tilt responds to settings and stops while hidden, reduced or backgrounded',
    (tester) async {
      final calls = <String>[];
      const sensor = MethodChannel(
        'dev.fluttercommunity.plus/sensors/accelerometer',
      );
      const methods = MethodChannel('dev.fluttercommunity.plus/sensors/method');
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(sensor, (call) async {
        calls.add(call.method);
        return null;
      });
      messenger.setMockMethodCallHandler(methods, (_) async => null);
      addTearDown(() {
        messenger.setMockMethodCallHandler(sensor, null);
        messenger.setMockMethodCallHandler(methods, null);
      });
      late Library library;
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        library = Library(await SharedPreferences.getInstance());
        await library.load();
      });
      var visible = true, reduced = false;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (c, set) {
              update = set;
              return MediaQuery(
                data: MediaQuery.of(c).copyWith(disableAnimations: reduced),
                child: TickerMode(
                  enabled: visible,
                  child: ListenableBuilder(
                    listenable: library,
                    builder: (_, _) => Scaffold(
                      body: SingleChildScrollView(
                        child: LivingShelf(
                          books: const [
                            Comic(
                              path: '/tilt/',
                              title: 'Shelf',
                              cover: 'offline:tilt',
                            ),
                          ],
                          library: library,
                          web: false,
                          onOpen: (_) {},
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      await library.setOption('tilt', true);
      await tester.pumpAndSettle();
      expect(calls, ['listen']);
      await library.setOption('tilt', false);
      await tester.pumpAndSettle();
      expect(calls, ['listen', 'cancel']);
      await library.setOption('tilt', true);
      await tester.pumpAndSettle();
      update(() => visible = false);
      await tester.pump();
      await tester.pump();
      expect(calls.last, 'cancel');
      update(() => visible = true);
      await tester.pumpAndSettle();
      expect(calls.last, 'listen');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(calls.last, 'cancel');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(calls.last, 'listen');
      update(() => reduced = true);
      await tester.pumpAndSettle();
      expect(calls.last, 'cancel');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
