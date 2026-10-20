import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/ui/book_object.dart';

void main() {
  testWidgets(
    'book motion reuses recorded artwork and book changes invalidate it',
    (tester) async {
      final focus = ValueNotifier(0.0);
      addTearDown(focus.dispose);
      var number = 1;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return Center(
                child: SizedBox(
                  width: 200,
                  height: 300,
                  child: ValueListenableBuilder<double>(
                    valueListenable: focus,
                    builder: (_, value, _) => BookObject(
                      const Comic(
                        path: '/test/',
                        title: 'Cached book',
                        cover: 'offline:test',
                      ),
                      web: false,
                      number: number,
                      exposure: value,
                      light: value / 2,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      final paint = find.descendant(
        of: find.byType(BookObject),
        matching: find.byType(CustomPaint),
      );
      Object artwork() =>
          (tester.widget<CustomPaint>(paint).painter as dynamic).artwork
              as Object;
      final initial = artwork();
      for (final value in [.1, .3, .7, 1.0, .8, .2]) {
        focus.value = value;
        await tester.pump();
        expect(identical(artwork(), initial), isTrue);
      }
      update(() => number = 2);
      await tester.pump();
      expect(identical(artwork(), initial), isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
