import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/ui/chapter_catalog.dart';

void main() {
  testWidgets(
    'a long catalog starts at the current chapter, filters and returns to it lazily',
    (tester) async {
      final chapters = List.generate(
        2000,
        (i) => Chapter('/m$i/', 'Chapter $i'),
      );
      Chapter? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChapterCatalog(
              chapters: chapters,
              current: '/m1500/',
              onSelected: (c) => selected = c,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Chapter 1500'), findsOneWidget);
      expect(find.byType(ListTile).evaluate().length, lessThan(50));
      await tester.enterText(find.byType(TextField), 'Chapter 1999');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Chapter 1999'));
      expect(selected!.path, '/m1999/');
      await tester.tap(find.byIcon(Icons.my_location_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Chapter 1500'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
