import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/main.dart';
import 'package:manxia/ui/glass_navigation.dart';
import 'package:manxia/data/library.dart';
import 'features_test.dart' as fixtures;

void main() {
  for (final size in [
    const Size(411, 731),
    const Size(390, 844),
    const Size(844, 390),
  ]) {
    testWidgets('shelf actions stay above navigation at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late Library library;
      await tester.runAsync(() async {
        library = await fixtures.library();
        await library.toggle(fixtures.comic);
        await library.save(fixtures.record(3, 10));
        library.updates[fixtures.comic.path] = {
          'checkedAt': DateTime.now().millisecondsSinceEpoch,
        };
      });
      await tester.pumpWidget(ManxiaApp(library: library));
      await tester.pumpAndSettle();
      final action = find.byKey(const ValueKey('shelf-read'));
      if (size.width == 411) {
        expect(
          tester.getRect(action).bottom,
          lessThan(tester.getRect(find.byType(FrostedNavigation)).top),
          reason:
              'A standard short-screen shelf should show its main action on arrival',
        );
      }
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(action).bottom,
        lessThan(tester.getRect(find.byType(FrostedNavigation)).top),
        reason:
            'The main reading action must not be painted behind the floating bar',
      );
      expect(action.hitTestable(), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      library.dispose();
    });
  }
}
