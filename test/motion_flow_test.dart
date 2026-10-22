import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/library.dart';
import 'package:manxia/data/dm5_source.dart';
import 'package:manxia/main.dart';
import 'package:manxia/ui/book_object.dart';
import 'package:manxia/ui/living_shelf.dart';
import 'package:manxia/ui/retained_pages.dart';
import 'package:manxia/ui/room_motion.dart';
import 'package:manxia/ui/collection_motion.dart';
import 'package:manxia/ui/detail_page.dart';

void main() {
  testWidgets(
    'wide detail keeps the book landing point fixed while metadata arrives',
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
      const comic = Comic(
        path: '/landing/',
        title: 'Book',
        cover: 'offline:motion',
      );
      final pending = Completer<ComicDetail>();
      final source = _DeferredDetail(pending);
      await tester.pumpWidget(
        MaterialApp(
          home: DetailPage(
            comic: comic,
            library: library,
            source: source,
            web: false,
          ),
        ),
      );
      await tester.pump();
      final landing = tester.getRect(find.byType(BookObject));
      pending.complete(
        ComicDetail(
          Comic(
            path: comic.path,
            cover: comic.cover,
            title: 'A long book title ' * 7,
            author: 'Author',
            tags: List.generate(12, (i) => 'Tag $i'),
            description: 'A full synopsis. ' * 100,
          ),
          const [],
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(BookObject)), landing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      source.close();
    },
  );
  testWidgets('removing a book cancels its unfinished collection flight', (
    tester,
  ) async {
    late Library library;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      library = Library(await SharedPreferences.getInstance());
      await library.load();
    });
    const comic = Comic(
      path: '/collect-motion/',
      title: 'Collected book',
      cover: 'offline:motion',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  collectWithMotion(context, comic, library, false),
              child: const Text('Toggle'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Toggle'));
    await tester.pump(const Duration(milliseconds: 60));
    expect(library.contains(comic), isTrue);
    expect(find.byType(ComicCover), findsOneWidget);
    await tester.tap(find.text('Toggle'));
    await tester.pump();
    expect(library.contains(comic), isFalse);
    expect(find.byType(ComicCover), findsNothing);
    await tester.tap(find.text('Toggle'));
    await tester.tap(find.text('Toggle'));
    await tester.pump();
    expect(library.contains(comic), isFalse);
    expect(find.byType(ComicCover), findsNothing);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('rapid page changes preserve every visible page pose', (
    tester,
  ) async {
    var selected = 0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (_, setState) {
            update = setState;
            return RetainedPages(
              index: selected,
              builder: (index) => Center(
                child: Text('Scene $index', key: ValueKey('scene-$index')),
              ),
            );
          },
        ),
      ),
    );
    double opacity(int index) => tester
        .widget<Opacity>(
          find
              .ancestor(
                of: find.byKey(ValueKey('scene-$index')),
                matching: find.byType(Opacity),
              )
              .first,
        )
        .opacity;
    for (final next in [1, 2, 0, 2, 1]) {
      final visible = <int, (double, Offset)>{
        for (final i in [0, 1, 2])
          if (find.byKey(ValueKey('scene-$i')).evaluate().isNotEmpty)
            i: (
              opacity(i),
              tester.getTopLeft(find.byKey(ValueKey('scene-$i'))),
            ),
      };
      update(() => selected = next);
      await tester.pump();
      for (final entry in visible.entries) {
        if (entry.value.$1 < .001) continue;
        expect(opacity(entry.key), closeTo(entry.value.$1, .001));
        expect(
          (tester.getTopLeft(find.byKey(ValueKey('scene-${entry.key}'))) -
                  entry.value.$2)
              .distance,
          lessThan(.01),
        );
      }
      await tester.pump(const Duration(milliseconds: 70));
    }
    await tester.pumpAndSettle();
    expect(find.text('Scene 1').hitTestable(), findsOneWidget);
    expect(find.text('Scene 0'), findsNothing);
    expect(find.text('Scene 2'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid shelf arrow taps keep the last requested destination', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late Library library;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      library = Library(await SharedPreferences.getInstance());
      await library.load();
      for (final book in library.samples) {
        await library.toggle(book);
      }
    });
    await tester.pumpWidget(ManxiaApp(library: library));
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byTooltip('下一本'));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.tap(find.byTooltip('上一本'));
    await tester.pumpAndSettle();
    expect(find.text('06 / 07'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a book flight reverses safely before opening completes', (
    tester,
  ) async {
    const comic = Comic(
      path: '/motion/',
      title: 'Motion book',
      cover: 'offline:motion',
    );
    final navigator = GlobalKey<NavigatorState>();
    Widget book() =>
        const BookFlight(child: BookObject(comic, web: false, number: 4));
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomLeft,
            child: SizedBox(
              width: 150,
              height: 210,
              child: GestureDetector(
                onTap: () => navigator.currentState!.push(
                  PageRouteBuilder<void>(
                    opaque: false,
                    transitionDuration: RoomMotion.book,
                    reverseTransitionDuration: RoomMotion.bookReturn,
                    pageBuilder: (_, _, _) => Scaffold(
                      body: Center(
                        child: SizedBox(width: 200, height: 280, child: book()),
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
                ),
                child: book(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(BookFlight));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 130));
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byType(BookFlight), findsOneWidget);
    expect(navigator.currentState!.canPop(), isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

class _DeferredDetail extends Dm5Source {
  _DeferredDetail(this.pending);
  final Completer<ComicDetail> pending;
  @override
  Future<ComicDetail> detail(Comic comic) => pending.future;
}
