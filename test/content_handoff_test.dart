import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/ui/content_handoff.dart';

void main() {
  testWidgets(
    'text handoffs never overlap and invisible controls cannot be activated',
    (tester) async {
      var value = 'Old', taps = 0, reduced = false;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(disableAnimations: reduced),
                child: Center(
                  child: ContentHandoff(
                    child: TextButton(
                      key: ValueKey(value),
                      onPressed: () => taps++,
                      child: Text(value),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      update(() => value = 'New');
      await tester.pump();
      await tester.tap(find.text('New'), warnIfMissed: false);
      expect(taps, 0);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 30));
        final fades = tester.widgetList<FadeTransition>(
          find.descendant(
            of: find.byType(ContentHandoff),
            matching: find.byType(FadeTransition),
          ),
        );
        expect(
          fades.where((w) => w.opacity.value > .001).length,
          lessThanOrEqualTo(1),
        );
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text('New'));
      expect(taps, 1);
      reduced = true;
      update(() => value = 'Instant');
      await tester.pump();
      await tester.tap(find.text('Instant'));
      expect(taps, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
