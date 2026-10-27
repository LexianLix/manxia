import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:manxia/main.dart';
import 'package:manxia/ui/localized_text.dart';
import 'package:manxia/data/library.dart';

void main() {
  for (final locale in [const Locale('en'), const Locale('zh', 'TW')]) {
    testWidgets('$locale and larger type remain usable on a compact screen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late Library library;
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        library = Library(await SharedPreferences.getInstance());
        await library.load();
        await library.setOption(
          'language',
          locale.languageCode == 'en' ? 'en' : 'zh_TW',
        );
        await library.setOption('textScale', 1.5);
        await library.setOption('highContrast', true);
      });
      await tester.pumpWidget(ManxiaApp(library: library));
      await tester.pumpAndSettle();
      expect(find.text(translate('我的书架', locale)), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip(translate('设置', locale)));
      await tester.pumpAndSettle();
      expect(find.text(translate('偏好设置', locale)), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
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
        for (final book in library.samples) {
          await library.toggle(book);
        }
      });
      await tester.pumpWidget(ManxiaApp(library: library));
      await tester.pumpAndSettle();
      expect(find.text('演示书架'), findsNothing);
      expect(library.favorites, hasLength(7));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('下一本'));
      await tester.pumpAndSettle();
      expect(find.text('02 / 07'), findsOneWidget);
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
      await tester.tap(find.text('外观与动效'));
      await tester.pumpAndSettle();
      expect(find.text('夜间阅读室'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(Switch).at(1));
      await tester.pumpAndSettle();
      expect(library.dark, true);
      expect(tester.takeException(), isNull);
    });
  }
}
