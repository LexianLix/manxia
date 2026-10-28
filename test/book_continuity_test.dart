import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/ui/book_object.dart';
import 'package:manxia/ui/room_motion.dart';

void main() {
  testWidgets(
    'the shelf cover keeps opening until it hands off to the flat cover',
    (tester) async {
      const comic = Comic(
        path: '/continuity/',
        title: 'Book',
        cover: 'offline:absent',
      );
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                height: 300,
                child: BookFlight(
                  child: BookObject(comic, web: false, flattening: .58),
                ),
              ),
            ),
          ),
        ),
      );
      nav.currentState!.push(
        PageRouteBuilder<void>(
          transitionDuration: RoomMotion.book,
          pageBuilder: (_, _, _) => const Scaffold(
            body: Center(
              child: SizedBox(
                width: 160,
                height: 240,
                child: DetailCover(comic, web: false),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(
        tester
            .widgetList<BookObject>(find.byType(BookObject))
            .single
            .flattening,
        closeTo(.58, .001),
        reason: 'Take off with the actual shelf cover proportions.',
      );
      double opening() =>
          tester.widgetList<BookObject>(find.byType(BookObject)).single.opening;
      await tester.pump(const Duration(milliseconds: 300));
      final before = opening();
      await tester.pump(const Duration(milliseconds: 240));
      expect(
        opening(),
        greaterThanOrEqualTo(before),
        reason:
            'An outward opening must not close again before its landing cover appears.',
      );
      await tester.pumpAndSettle();
      nav.currentState!.pop();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
