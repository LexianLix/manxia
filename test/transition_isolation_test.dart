import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/main.dart';
import 'package:manxia/ui/room_motion.dart';
import 'package:manxia/ui/retained_pages.dart';
import 'package:manxia/ui/offline_page.dart';
import 'package:manxia/ui/plugins_page.dart';
import 'package:manxia/ui/app_shell.dart';
import 'package:manxia/ui/living_shelf.dart';
import 'package:manxia/data/library.dart';
import 'package:manxia/data/dm5_source.dart';
import 'features_test.dart' as fixtures;

Future<List<int>> pixel(
  WidgetTester tester,
  GlobalKey key,
  int x,
  int y,
) async {
  late List<int> result;
  await tester.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage();
    final bytes = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    final offset = (y * image.width + x) * 4;
    result = bytes.sublist(offset, offset + 4);
    image.dispose();
  });
  return result;
}

Widget ink(Color color) => Scaffold(
  body: Stack(
    children: [
      Positioned(
        left: 80,
        top: 180,
        width: 200,
        height: 100,
        child: ColoredBox(color: color),
      ),
    ],
  ),
);
bool mixed(List<int> rgba) => rgba[0] - rgba[1] > 8 && rgba[2] - rgba[1] > 8;

void main() {
  test('route fade-through has equal, reversible content handoffs', () {
    expect(RoomMotion.routeCovered(.2), closeTo(.6, .0001));
    expect(RoomMotion.routeEnter(.8), closeTo(.6, .0001));
    for (var i = 0; i <= 100; i++) {
      final p = i / 100;
      expect(RoomMotion.routeEnter(p) * RoomMotion.routeCovered(p), 0);
      expect(RoomMotion.routeEnter(p), RoomMotion.routeCovered(1 - p));
    }
  });
  for (final reduced in [false, true]) {
    testWidgets(
      'return from a normal route to a book route isolates both content layers (reduced: $reduced)',
      (tester) async {
        final key = GlobalKey(), nav = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              navigatorKey: nav,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(disableAnimations: reduced),
                child: child!,
              ),
              theme: ThemeData(
                scaffoldBackgroundColor: Colors.transparent,
                pageTransitionsTheme: const PageTransitionsTheme(
                  builders: {TargetPlatform.android: RoomPageTransitions()},
                ),
              ),
              home: const Scaffold(),
            ),
          ),
        );
        nav.currentState!.push(
          PageRouteBuilder<void>(
            pageBuilder: (_, a, b) => ink(const Color(0xffff0000)),
            transitionsBuilder: (_, a, b, child) => OpenBookTransition(
              animation: a,
              secondaryAnimation: b,
              comic: fixtures.comic,
              web: false,
              child: child,
            ),
          ),
        );
        await tester.pumpAndSettle();
        nav.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => ink(const Color(0xff0000ff))),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 110));
        expect(mixed(await pixel(tester, key, 180, 230)), false);
        await tester.pumpAndSettle();
        nav.currentState!.pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 160));
        expect(mixed(await pixel(tester, key, 180, 230)), false);
        await tester.pumpAndSettle();
      },
    );
  }
  testWidgets(
    'updates appear on the shelf without calendar or redundant download actions',
    (tester) async {
      late Library library;
      await tester.runAsync(() async {
        library = await fixtures.library();
        await library.toggle(fixtures.comic);
        library.updates[fixtures.comic.path] = {
          'changed': true,
          'latest': '第2话',
          'checkedAt': DateTime.now().millisecondsSinceEpoch,
        };
      });
      await tester.pumpWidget(ManxiaApp(library: library));
      await tester.pumpAndSettle();
      expect(find.byTooltip('追漫日历'), findsNothing);
      expect(find.text('有更新 1'), findsOneWidget);
      expect(find.text('有更新 · 第2话'), findsWidgets);
      await library.markUpdatesRead([fixtures.comic.path]);
      await tester.pumpAndSettle();
      expect(find.text('有更新 1'), findsNothing);
      expect(library.contains(fixtures.comic), true);
      await tester.tap(find.byTooltip('下载'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('刷新任务'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      library.dispose();
    },
  );
  testWidgets(
    'covered app pages do not rebuild in response to reading metadata',
    (tester) async {
      late dynamic library;
      await tester.runAsync(() async {
        library = await fixtures.library();
        await library.setOption('startTab', 3);
      });
      await tester.pumpWidget(ManxiaApp(library: library));
      await tester.pumpAndSettle();
      final nav = Navigator.of(tester.element(find.byType(AppShell)));
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Reader')),
        ),
      );
      await tester.pumpAndSettle();
      var rebuilds = 0;
      debugOnRebuildDirtyWidget = (element, _) {
        if (element.findAncestorWidgetOfExactType<AppShell>() != null) {
          rebuilds++;
        }
      };
      addTearDown(() => debugOnRebuildDirtyWidget = null);
      await library.setMeta(fixtures.comic, {'note': 'Reading changed'});
      await tester.pump();
      expect(
        rebuilds,
        0,
        reason:
            'A hidden shelf must not parse and lay out after each reading-position save',
      );
      debugOnRebuildDirtyWidget = null;
      nav.pop();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      library.dispose();
    },
  );
  testWidgets('transparent routes never superimpose page ink on push or return', (
    tester,
  ) async {
    final key = GlobalKey(), nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          navigatorKey: nav,
          theme: ThemeData(
            scaffoldBackgroundColor: Colors.transparent,
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: {TargetPlatform.android: RoomPageTransitions()},
            ),
          ),
          builder: (_, child) => ColoredBox(color: Colors.black, child: child!),
          home: ink(const Color(0xffff0000)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    nav.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => ink(const Color(0xff0000ff))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(
      mixed(await pixel(tester, key, 180, 230)),
      false,
      reason:
          'Incoming and covered page text must not be legible in the same pixels',
    );
    await tester.pumpAndSettle();
    nav.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(
      mixed(await pixel(tester, key, 180, 230)),
      false,
      reason: 'Returning must not blend two transparent content layers',
    );
    await tester.pumpAndSettle();
  });
  testWidgets('retained tab transitions never superimpose two pages', (
    tester,
  ) async {
    final key = GlobalKey();
    var selected = 0;
    late StateSetter change;
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          theme: ThemeData(scaffoldBackgroundColor: Colors.transparent),
          home: ColoredBox(
            color: Colors.black,
            child: StatefulBuilder(
              builder: (_, set) {
                change = set;
                return RetainedPages(
                  index: selected,
                  builder: (i) => ink(
                    i == 0 ? const Color(0xffff0000) : const Color(0xff0000ff),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    change(() => selected = 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(mixed(await pixel(tester, key, 180, 230)), false);
  });
  testWidgets(
    'download and plugin headers do not paint a pale strip over wallpaper',
    (tester) async {
      late dynamic library;
      await tester.runAsync(() async {
        library = await fixtures.library();
        await library.setOption('startTab', 3);
      });
      await tester.pumpWidget(ManxiaApp(library: library));
      await tester.pumpAndSettle();
      final theme = tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!;
      final source = Dm5Source();
      addTearDown(source.close);
      for (final page in [
        OfflinePage(library: library, source: source, web: false),
        PluginsPage(library: library),
      ]) {
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              theme: theme,
              home: ColoredBox(color: const Color(0xffff0000), child: page),
            ),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
        await tester.pumpAndSettle();
        final rgba = await pixel(tester, key, 3, 12);
        expect(
          rgba[1],
          lessThan(5),
          reason: 'An embedded page header must preserve the shared wallpaper',
        );
        expect(rgba[2], lessThan(5));
      }
      await tester.pumpWidget(const SizedBox());
      library.dispose();
    },
  );
  testWidgets(
    'hidden visited pages are not rebuilt for each active page update',
    (tester) async {
      var selected = 0, revision = 0;
      late StateSetter change;
      final builds = <int, int>{};
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (_, set) {
              change = set;
              return RetainedPages(
                index: selected,
                builder: (i) {
                  builds[i] = (builds[i] ?? 0) + 1;
                  return Text('$i $revision');
                },
              );
            },
          ),
        ),
      );
      change(() => selected = 1);
      await tester.pumpAndSettle();
      builds.clear();
      for (var i = 0; i < 10; i++) {
        change(() => revision++);
        await tester.pump();
      }
      expect(
        builds[0] ?? 0,
        0,
        reason:
            'Hidden discovery/shelf trees must not recompute during active page updates',
      );
      expect(builds[1], 10);
    },
  );
}
