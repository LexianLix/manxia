import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:manxia/data/library.dart';
import 'package:manxia/main.dart';

void main() {
  testWidgets(
    'returning to the shelf preserves its scene instead of loading it again',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late Library library;
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        library = Library(await SharedPreferences.getInstance());
        await library.load();
      });
      await tester.pumpWidget(ManxiaApp(library: library));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('下一本'));
      await tester.pumpAndSettle();
      expect(find.text('05 / 07'), findsOneWidget);
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      expect(find.text('WebDAV 同步'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('WebDAV 同步'),
        450,
        scrollable: find.byType(Scrollable).last,
        maxScrolls: 20,
      );
      await tester.pumpAndSettle();
      expect(find.text('WebDAV 同步'), findsOneWidget);
      await tester.tap(find.text('书架'));
      await tester.pumpAndSettle();
      expect(find.text('05 / 07'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
