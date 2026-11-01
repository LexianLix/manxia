import 'package:manxia/ui/reading_profiles_page.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:manxia/data/character_assets.dart';
import 'package:manxia/data/character_definition.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/main.dart';
import 'package:manxia/data/library.dart';
import 'package:manxia/data/library_notice.dart';
import 'package:manxia/data/plugin_registry.dart';
import 'package:manxia/ui/companion.dart';
import 'package:manxia/ui/character_settings_page.dart';
import 'package:manxia/ui/plugin_effects_page.dart';
import 'features_test.dart' as fixtures;

void main() {
  Future<Library> setup(WidgetTester tester, {bool role = true}) async {
    late Library library;
    await tester.runAsync(() async {
      library = await fixtures.library();
      if (!role) {
        final plugin = (await PluginCatalog.bundled()).firstWhere(
          (p) => p.id == 'manxia.xiaxia',
        );
        await CharacterAssets.shared.prepare(
          CharacterDefinition(
            Map<String, dynamic>.from(plugin.contributions['character']),
          ),
          plugin.resources,
        );
      }
      if (role) {
        final plugin = (await PluginCatalog.bundled()).firstWhere(
          (p) => p.id == 'manxia.xiaxia',
        );
        await PluginRegistry(library).install(plugin);
      }
    });
    return library;
  }

  testWidgets(
    'role is opt-in; enable, quiet mode, disable and uninstall preserve books',
    (tester) async {
      final library = await setup(tester, role: false);
      await tester.runAsync(() => library.toggle(fixtures.comic));
      await tester.pumpWidget(ManxiaApp(library: library));
      await tester.pumpAndSettle();
      expect(find.byType(CompanionAvatar), findsNothing);
      final home = tester.element(find.byType(CompanionFeedback));
      Navigator.of(home).push(
        MaterialPageRoute<void>(
          builder: (_) => CharacterSettingsPage(library: library),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(find.text('安装并启用小夏'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('安装并启用小夏'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(find.text('已启用'), findsOneWidget);
      expect(find.byType(CompanionAvatar), findsNothing);
      Navigator.of(tester.element(find.byType(CharacterSettingsPage))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(CompanionAvatar), findsOneWidget);
      await library.setOption('companion', {'visible': false});
      await tester.pumpAndSettle();
      expect(find.byType(CompanionAvatar), findsNothing);
      await tester.runAsync(
        () => PluginRegistry(library).uninstall('manxia.xiaxia'),
      );
      await tester.pumpAndSettle();
      expect(library.favorites.single.path, fixtures.comic.path);
      expect(PluginRegistry(library).snapshot.character, isNull);
      await tester.pumpWidget(const SizedBox());
      library.dispose();
    },
  );
  for (final reduced in [false, true]) {
    testWidgets(
      'feedback is finite, quiet, hidden while reading and clears in background; reduced=$reduced',
      (tester) async {
        final library = await setup(tester);
        final nav = GlobalKey<NavigatorState>();
        var clicked = 0;
        var now = DateTime.now();
        await tester.pumpWidget(
          AnimatedBuilder(
            animation: library,
            builder: (_, _) => MaterialApp(
              locale: const Locale('zh', 'CN'),
              supportedLocales: const [Locale('zh', 'CN')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              navigatorKey: nav,
              builder: (c, child) => MediaQuery(
                data: MediaQuery.of(c).copyWith(disableAnimations: reduced),
                child: CompanionScope(library: library, child: child!),
              ),
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 360,
                    child: CompanionFeedback(
                      now: () => now,
                      library: library,
                      onShelf: () => clicked++,
                      onUpdates: () => clicked++,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await library.toggle(fixtures.comic);
          await Future<void>.delayed(const Duration(milliseconds: 250));
        });
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pumpAndSettle();
        expect(find.text('已放进你的书架'), findsOneWidget);
        await tester.tap(find.text('查看书架'));
        await tester.pumpAndSettle();
        expect(clicked, 1);
        expect(find.text('已放进你的书架'), findsNothing);
        library.announce(
          LibraryNotice(LibraryNoticeKind.updatesFound, at: now),
        );
        await tester.pump(const Duration(milliseconds: 250));
        expect(
          find.text('书架有新章节'),
          findsNothing,
          reason: 'quiet frequency throttles repeated feedback',
        );
        now = now.add(const Duration(seconds: 31));
        await tester.pump(const Duration(seconds: 31));
        nav.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Reading')),
          ),
        );
        await tester.pumpAndSettle();
        library.announce(
          LibraryNotice(LibraryNoticeKind.updatesFound, at: now),
        );
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.text('书架有新章节'), findsNothing);
        nav.currentState!.pop();
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pumpAndSettle();
        expect(find.text('书架有新章节'), findsOneWidget);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pumpAndSettle();
        expect(find.text('书架有新章节'), findsNothing);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        now = now.add(const Duration(seconds: 31));
        await tester.pump(const Duration(seconds: 31));
        await library.setOption('companion', {'frequency': 'off'});
        await tester.pumpAndSettle();
        library.announce(
          LibraryNotice(LibraryNoticeKind.updatesFound, at: now),
        );
        await tester.pump(const Duration(seconds: 5));
        expect(find.text('书架有新章节'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        library.dispose();
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('effect origins show automatic disable and wallpaper override', (
    tester,
  ) async {
    final library = await setup(tester);
    final plugins = await tester.runAsync(() => PluginCatalog.bundled());
    final registry = PluginRegistry(library);
    await registry.install(
      plugins!.firstWhere((p) => p.id == 'manxia.blue-hour'),
    );
    await registry.install(
      plugins.firstWhere((p) => p.id == 'manxia.warm-paper'),
    );
    await library.setOption('appearance', {
      'wallpaper': 'a' * 64,
      'follow': true,
    });
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: PluginEffectsPage(library: library),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('由背景图片配色覆盖'), findsWidgets);
    final disabled = find.text('被 暖纸书房 停用');
    await tester.ensureVisible(disabled);
    await tester.pumpAndSettle();
    expect(disabled.hitTestable(), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    library.dispose();
  });
  testWidgets('landscape large-text companion actions scroll into reach', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    final library = await setup(tester);
    await tester.runAsync(() async {
      await library.toggle(fixtures.comic);
      await library.save(fixtures.record(1, 10));
      library.updates[fixtures.comic.path] = {
        'checkedAt': DateTime.now().millisecondsSinceEpoch,
      };
      await library.setOption('language', 'en');
      await library.setOption('textScale', 1.5);
    });
    await tester.pumpWidget(ManxiaApp(library: library));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Xiaxia & companions'));
    await tester.pumpAndSettle();
    final action = find.text('Xiaxia & companions');
    await tester.ensureVisible(action);
    await tester.pumpAndSettle();
    expect(action.hitTestable(), findsOneWidget);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(find.byType(CharacterSettingsPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    library.dispose();
  });
  test('malformed restored companion preferences use safe defaults', () {
    final prefs = CompanionPreferences({'companion': true});
    expect(prefs.visible, true);
    expect(prefs.size, 'small');
  });
  testWidgets(
    'profile selection and its management menu have separate semantics',
    (tester) async {
      final library = await setup(tester, role: false);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: ReadingProfilesPage(library: library),
        ),
      );
      await tester.pumpAndSettle();
      final node = tester.getSemantics(find.byType(RadioListTile<String>).last);
      expect(node.label, '条漫');
      expect(find.byTooltip('方案操作'), findsNWidgets(3));
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
      library.dispose();
    },
  );
}
