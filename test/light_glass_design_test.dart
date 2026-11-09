import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:manxia/main.dart';
import 'package:manxia/data/appearance.dart';
import 'package:manxia/data/library.dart';
import 'package:manxia/ui/browse_chrome.dart';
import 'package:manxia/ui/plugins_page.dart';
import 'package:manxia/ui/personalization_settings.dart';

Future<Library> prepare(Map<String, dynamic> options) async {
  SharedPreferences.setMockInitialValues({});
  final library = Library(await SharedPreferences.getInstance());
  await library.load();
  library.options.addAll(options);
  return library;
}

void main() {
  test('wallpaper accents never tint the neutral reading surface', () {
    for (final dark in [false, true]) {
      expect(
        RoomAppearance.surface(Colors.green, dark),
        RoomAppearance.surface(Colors.deepPurple, dark),
      );
    }
  });
  testWidgets('four default tabs keep plugins accessible from preferences', (
    tester,
  ) async {
    final library = (await tester.runAsync(() => prepare({})))!;
    await tester.pumpWidget(ManxiaApp(library: library));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<BrowseNavigation>(find.byType(BrowseNavigation))
          .destinations
          .map((d) => d.id),
      [0, 1, 4, 3],
    );
    final scheme = Theme.of(
      tester.element(find.byType(Scaffold).first),
    ).colorScheme;
    expect(scheme.surface, const Color(0xfff5f5f7));
    expect(scheme.primary, const Color(0xff303238));
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('插件商城'));
    await tester.tap(find.text('插件商城'));
    await tester.pumpAndSettle();
    expect(find.byType(PluginsPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    library.dispose();
  });
  testWidgets('a legacy plugin start tab and manual navigation remain valid', (
    tester,
  ) async {
    final library = (await tester.runAsync(() => prepare({'startTab': 5})))!;
    await tester.pumpWidget(ManxiaApp(library: library));
    // Asset-backed plugin catalogs finish on the real IO loop. The presence
    // of the legacy destination must not depend on settling its loader.
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(PluginsPage), findsOneWidget);
    await tester.runAsync(
      () => library.setOption('navigation', [0, 1, 4, 5, 3]),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(navigationIds(library), [0, 1, 4, 5, 3]);
    await tester.pumpWidget(const SizedBox());
    library.dispose();
  });
}
