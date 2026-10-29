import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:manxia/main.dart';
import 'package:manxia/data/library.dart';
import 'package:manxia/ui/settings_page.dart';
import 'package:manxia/ui/localized_text.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'discovery_page_test.dart' show capture;

void main() {
  setUpAll(() async {
    if (Platform.environment['MANXIA_CAPTURE_DIR'] != null) {
      await (FontLoader('ArchiveSerif')..addFont(
            rootBundle.load('assets/fonts/SourceHanSerifCN-Regular.otf'),
          ))
          .load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
  });
  for (final language in ['zh_CN', 'zh_TW', 'en']) {
    testWidgets(
      'settings hierarchy survives rapid scroll, remount and enlarged text: $language',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        late Library state;
        await tester.runAsync(() async {
          SharedPreferences.setMockInitialValues({});
          state = Library(await SharedPreferences.getInstance());
          await state.load();
          await state.setOption('startTab', 3);
          await state.setOption('language', language);
          await state.setOption('textScale', language == 'zh_CN' ? 1.0 : 1.5);
        });
        final locale = language == 'en'
            ? const Locale('en')
            : Locale('zh', language == 'zh_TW' ? 'TW' : 'CN');
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: ManxiaApp(library: state),
          ),
        );
        await tester.pumpAndSettle();
        await capture(tester, key, 'settings-home-$language');
        expect(find.byType(SettingsPage), findsOneWidget);
        expect(find.byType(SwitchListTile), findsNothing);
        await tester.tap(find.text(translate('外观与动效', locale)));
        await tester.pumpAndSettle();
        expect(find.byType(SettingsSection), findsOneWidget);
        final expansion = find.byKey(
          const PageStorageKey('settings-navigation-expanded'),
        );
        final settingsScroll = find
            .descendant(
              of: find.byKey(
                const PageStorageKey('settings-section-appearance'),
              ),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(
          find.text(translate('底部入口与顺序', locale)),
          200,
          scrollable: settingsScroll,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(translate('底部入口与顺序', locale)));
        await tester.pumpAndSettle();
        expect(find.byType(ReorderableListView), findsOneWidget);
        await capture(tester, key, 'settings-navigation-$language');
        for (var i = 0; i < 6; i++) {
          await tester.flingFrom(
            const Offset(180, 650),
            const Offset(0, -1300),
            6500,
          );
          await tester.pump(const Duration(milliseconds: 30));
          expect(tester.takeException(), isNull);
        }
        await tester.pumpAndSettle();
        for (var i = 0; i < 6; i++) {
          await tester.flingFrom(
            const Offset(180, 200),
            const Offset(0, 1300),
            6500,
          );
          await tester.pump(const Duration(milliseconds: 30));
          expect(tester.takeException(), isNull);
        }
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          expansion,
          200,
          scrollable: settingsScroll,
        );
        expect(find.byType(ReorderableListView), findsOneWidget);
        expect(
          tester.widget<ExpansionTile>(expansion).key,
          const PageStorageKey('settings-navigation-expanded'),
        );
        await tester.scrollUntilVisible(
          find.text(translate('语言与可读性', locale)),
          200,
          scrollable: settingsScroll,
        );
        await tester.tap(find.text(translate('语言与可读性', locale)));
        await tester.pumpAndSettle();
        expect(find.text(translate('界面语言', locale)), findsOneWidget);
        await capture(tester, key, 'settings-accessibility-$language');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
