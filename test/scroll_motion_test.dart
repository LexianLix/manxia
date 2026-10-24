import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/ui/room_scroll.dart';

void main() {
  testWidgets(
    'edge release and a new drag keep the current scroll pose; reduced motion clamps',
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      var reduced = false;
      late StateSetter change;
      await tester.pumpWidget(
        MaterialApp(
          scrollBehavior: const RoomScrollBehavior(),
          home: StatefulBuilder(
            builder: (context, update) {
              change = update;
              return MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(disableAnimations: reduced),
                child: Scaffold(
                  body: ListView.builder(
                    controller: scroll,
                    itemExtent: 90,
                    itemCount: 100,
                    itemBuilder: (_, i) => Text('Item $i'),
                  ),
                ),
              );
            },
          ),
        ),
      );
      Future<TestGesture> pull() async {
        final gesture = await tester.startGesture(const Offset(200, 200));
        await gesture.moveBy(const Offset(0, 40));
        await tester.pump();
        await gesture.moveBy(const Offset(0, 160));
        await tester.pump();
        return gesture;
      }

      final first = await pull();
      expect(scroll.offset, lessThan(-10));
      final pose = scroll.offset;
      await first.up();
      await tester.pump();
      expect(scroll.offset, closeTo(pose, .01));
      await tester.pump(const Duration(milliseconds: 40));
      expect(scroll.offset.abs(), lessThan(pose.abs()));
      final nextPose = scroll.offset;
      final second = await tester.startGesture(const Offset(200, 300));
      await tester.pump();
      expect(scroll.offset, closeTo(nextPose, .01));
      await second.moveBy(const Offset(0, -40));
      await tester.pump();
      await second.moveBy(const Offset(0, -60));
      await tester.pump();
      expect(scroll.offset, greaterThan(nextPose));
      await second.cancel();
      await tester.pumpAndSettle();
      scroll.jumpTo(0);
      change(() => reduced = true);
      await tester.pumpAndSettle();
      final third = await pull();
      expect(scroll.offset, 0);
      await third.up();
      await tester.pumpAndSettle();
      expect(scroll.offset, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
