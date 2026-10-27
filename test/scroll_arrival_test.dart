import 'package:manxia/ui/paper_leaf.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/ui/scroll_arrival.dart';

void main() {
  for (final reduced in [false, true]) {
    testWidgets(
      'catalog reveal starts only when scrolled into view, reduced=$reduced',
      (tester) async {
        final controller = ScrollController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(800, 600),
                disableAnimations: reduced,
              ),
              child: Scaffold(
                body: SingleChildScrollView(
                  controller: controller,
                  child: Column(
                    children: [
                      const SizedBox(height: 900),
                      ScrollArrival(
                        identity: 'scroll-$reduced',
                        child: const SizedBox(
                          width: 180,
                          height: 200,
                          child: Text('new comic'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final leaf = find.descendant(
          of: find.byType(ScrollArrival),
          matching: find.byType(PaperLeaf),
        );
        expect(tester.widget<PaperLeaf>(leaf).amount, reduced ? 0 : .10);
        controller.jumpTo(700);
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        final midway = tester.widget<PaperLeaf>(leaf).amount;
        expect(midway, lessThan(.10));
        if (!reduced) expect(midway, greaterThan(0));
        await tester.pumpAndSettle();
        expect(tester.widget<PaperLeaf>(leaf).amount, 0);
        controller.jumpTo(0);
        await tester.pumpAndSettle();
        controller.jumpTo(700);
        await tester.pump();
        expect(tester.widget<PaperLeaf>(leaf).amount, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
