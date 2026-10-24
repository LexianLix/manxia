import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/ui/book_object.dart';

void main() {
  testWidgets(
    'the free cover edge turns toward the reader, with the spine fixed',
    (tester) async {
      const cover = ValueKey('source-cover');
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                height: 300,
                child: CoverHinge(
                  progress: .25,
                  source: ColoredBox(key: cover, color: Colors.green),
                  destination: ColoredBox(color: Colors.blue),
                ),
              ),
            ),
          ),
        ),
      );
      final plane = tester.widget<Transform>(
        find
            .ancestor(of: find.byKey(cover), matching: find.byType(Transform))
            .first,
      );
      final matrix = plane.transform;
      // Perspective divides by w. Approaching the reader enlarges the free
      // edge (w < 1); receding into the book compresses it (w > 1).
      final freeEdgeW = matrix.entry(3, 0) * 200 + matrix.entry(3, 3);
      expect(freeEdgeW, lessThan(1));
      expect(matrix.entry(3, 3), 1);
      expect(plane.alignment, Alignment.centerLeft);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
