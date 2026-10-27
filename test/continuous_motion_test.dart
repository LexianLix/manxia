import 'package:manxia/ui/paper_leaf.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/ui/retained_pages.dart';
import 'package:manxia/ui/glass_navigation.dart';
import 'package:manxia/ui/book_object.dart';
import 'package:manxia/ui/room_motion.dart';
import 'package:manxia/data/comic.dart';

void main() {
  testWidgets(
    'changing page order during a drag cannot select a removed destination',
    (tester) async {
      var order = [0, 1, 2, 3];
      late StateSetter update;
      final selected = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (c, set) {
              update = set;
              return Scaffold(
                body: RetainedPages(
                  index: 0,
                  order: order,
                  onSelected: selected.add,
                  builder: (i) => Center(child: Text('Page $i')),
                ),
              );
            },
          ),
        ),
      );
      final gesture = await tester.startGesture(const Offset(650, 250));
      await gesture.moveTo(const Offset(180, 250));
      await tester.pump();
      update(() => order = [0, 4, 5, 3]);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(selected, isEmpty);
      expect(find.text('Page 0').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('page direction follows destination order rather than IDs', (
    tester,
  ) async {
    var selected = 5;
    late StateSetter change;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, update) {
            change = update;
            return Scaffold(
              body: RetainedPages(
                index: selected,
                order: const [0, 1, 4, 5, 3],
                builder: (i) => ColoredBox(
                  key: ValueKey('ordered-page-$i'),
                  color: Colors.white,
                ),
              ),
            );
          },
        ),
      ),
    );
    change(() => selected = 3);
    await tester.pump();
    expect(
      tester
          .widget<PaperLeaf>(
            find
                .ancestor(
                  of: find.byKey(const ValueKey('ordered-page-3')),
                  matching: find.byType(PaperLeaf),
                )
                .first,
          )
          .reverse,
      isTrue,
    );
    await tester.pumpAndSettle();
    change(() => selected = 5);
    await tester.pump();
    expect(
      tester
          .widget<PaperLeaf>(
            find
                .ancestor(
                  of: find.byKey(const ValueKey('ordered-page-5')),
                  matching: find.byType(PaperLeaf),
                )
                .first,
          )
          .reverse,
      isFalse,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'page follows the finger, cancelled drag returns, and committed drag settles',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var selected = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, update) => Scaffold(
              body: RetainedPages(
                index: selected,
                order: const [0, 4],
                onSelected: (v) => update(() => selected = v),
                builder: (i) => ColoredBox(
                  key: ValueKey('page-$i'),
                  color: Colors.white,
                  child: Center(child: Text('Page $i')),
                ),
              ),
            ),
          ),
        ),
      );
      final first = tester.getTopLeft(find.byKey(const ValueKey('page-0')));
      final gesture = await tester.startGesture(const Offset(330, 300));
      await gesture.moveTo(const Offset(170, 300));
      await tester.pump();
      expect(selected, 0);
      expect(
        tester
            .widget<PaperLeaf>(
              find
                  .ancestor(
                    of: find.byKey(const ValueKey('page-0')),
                    matching: find.byType(PaperLeaf),
                  )
                  .first,
            )
            .amount,
        inExclusiveRange(0, 1),
      );
      expect(find.byKey(const ValueKey('page-4')), findsOneWidget);
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(selected, 0);
      expect(tester.getTopLeft(find.byKey(const ValueKey('page-0'))), first);
      await tester.dragFrom(const Offset(330, 300), const Offset(-220, 0));
      await tester.pumpAndSettle();
      expect(selected, 4);
      expect(find.text('Page 4').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'liquid navigation preserves both volumes during rapid retargeting',
    (tester) async {
      var selected = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, update) => Scaffold(
              bottomNavigationBar: FrostedNavigation(
                selectedIndex: selected,
                haptics: false,
                onSelected: (v) => update(() => selected = v),
              ),
            ),
          ),
        ),
      );
      WaterDropPainter painter() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<WaterDropPainter>()
          .single;
      await tester.tap(find.byTooltip('Settings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final before = painter();
      expect((before.head - before.tail).abs(), greaterThan(1));
      expect(
        before.contour().contains(
          Offset((before.head + before.tail) / 2, before.centerY),
        ),
        true,
      );
      await tester.tap(find.byTooltip('Library'));
      await tester.pump();
      expect(painter().head, closeTo(before.head, .01));
      expect(painter().tail, closeTo(before.tail, .01));
      await tester.pumpAndSettle();
      expect((painter().head - painter().tail).abs(), lessThan(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'book turns through intermediate poses and stays open after landing',
    (tester) async {
      const comic = Comic(
        path: '/turn/',
        title: 'Paper book',
        cover: 'offline:turn',
      );
      final nav = GlobalKey<NavigatorState>();
      Widget book(double opening) => SizedBox(
        width: 200,
        height: 280,
        child: BookFlight(
          child: BookObject(comic, web: false, opening: opening),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          home: Scaffold(
            body: GestureDetector(
              onTap: () => nav.currentState!.push(
                PageRouteBuilder<void>(
                  transitionDuration: RoomMotion.book,
                  reverseTransitionDuration: RoomMotion.bookReturn,
                  pageBuilder: (_, _, _) =>
                      Scaffold(body: Center(child: book(1))),
                ),
              ),
              child: book(0),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(BookObject));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 380));
      expect(
        tester
            .widgetList<BookObject>(find.byType(BookObject))
            .any((b) => b.opening > .1 && b.opening < .9),
        true,
      );
      await tester.pumpAndSettle();
      expect(tester.widget<BookObject>(find.byType(BookObject)).opening, 1);
      nav.currentState!.pop();
      await tester.pumpAndSettle();
      expect(tester.widget<BookObject>(find.byType(BookObject)).opening, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
