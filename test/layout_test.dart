import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:manxia/main.dart';
import 'package:manxia/data/library.dart';

void main() {
  for (final width in [390.0, 754.0, 1440.0]) {
    testWidgets('shelf and preferences fit a $width pixel viewport', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
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
      expect(find.text('演示书架'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('下一本'));
      await tester.pumpAndSettle();
      expect(find.text('05 / 07'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('切换封面网格'));
      await tester.pumpAndSettle();
      expect(library.grid, true);
      expect(tester.takeException(), isNull);
      if (width >= 1000) {
        await tester.tap(find.text('偏好设置'));
      } else {
        await tester.tap(find.text('设置'));
      }
      await tester.pumpAndSettle();
      expect(find.text('夜间阅读室'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(library.dark, true);
      expect(tester.takeException(), isNull);
    });
  }
}
