import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/ui/sliver_handoff.dart';

void main() {
  testWidgets(
    'virtual catalog handoff is reversible, interrupts from its pose and never paints two lists',
    (tester) async {
      var selected = 'a', reduced = false, builds = 0, taps = 0;
      late StateSetter change;
      Widget grid(String id) => SliverGrid(
        delegate: SliverChildBuilderDelegate((_, i) {
          builds++;
          return GestureDetector(
            onTap: () => taps++,
            child: ColoredBox(
              key: ValueKey('$id-$i'),
              color: Colors.green,
              child: Text('$id-$i'),
            ),
          );
        }, childCount: 553),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisExtent: 80,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              change = setState;
              return MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(disableAnimations: reduced),
                child: CustomScrollView(
                  slivers: [
                    SliverHandoff(identity: selected, sliver: grid(selected)),
                  ],
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(builds, lessThan(40));
      change(() => selected = 'b');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 35));
      double alpha() => tester
          .widget<SliverFadeTransition>(find.byType(SliverFadeTransition))
          .opacity
          .value;
      final before = alpha();
      expect(before, inExclusiveRange(0, 1));
      await tester.tap(find.byKey(const ValueKey('a-0')), warnIfMissed: false);
      expect(taps, 0);
      change(() => selected = 'c');
      await tester.pump();
      expect(alpha(), before);
      change(() => selected = 'a');
      await tester.pump();
      expect(alpha(), before);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('a-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('b-0')), findsNothing);
      expect(find.byKey(const ValueKey('c-0')), findsNothing);
      change(() => selected = 'b');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 95));
      expect(find.byKey(const ValueKey('a-0')), findsNothing);
      expect(find.byKey(const ValueKey('b-0')), findsOneWidget);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('b-0')));
      expect(taps, 1);
      reduced = true;
      change(() => selected = 'c');
      await tester.pump();
      expect(alpha(), 1);
      expect(find.byKey(const ValueKey('c-0')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
