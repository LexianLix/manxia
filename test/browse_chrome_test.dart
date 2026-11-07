import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/ui/browse_chrome.dart';
import 'package:manxia/ui/glass_navigation.dart';

void main() {
  for (final reduced in [false, true]) {
    testWidgets(
      'dock folds left, reverses and remains usable; reduced=$reduced',
      (tester) async {
        tester.view.physicalSize = const Size(390, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final chrome = BrowseChrome();
        var selected = 0;
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(390, 700),
                disableAnimations: reduced,
              ),
              child: Scaffold(
                extendBody: true,
                body: NotificationListener<ScrollNotification>(
                  onNotification: chrome.observe,
                  child: ListView(
                    children: [
                      for (var i = 0; i < 40; i++)
                        SizedBox(height: 60, child: Text('第$i本')),
                    ],
                  ),
                ),
                bottomNavigationBar: BrowseNavigation(
                  chrome: chrome,
                  selectedIndex: 0,
                  destinations: roomDestinations.take(4).toList(),
                  onSelected: (i) => selected = i,
                  highQuality: false,
                  haptics: false,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final dock = find.byKey(const ValueKey('browse-dock'));
        final expanded = tester.getRect(dock);
        await tester.drag(find.byType(ListView), const Offset(0, -180));
        await tester.pumpAndSettle();
        expect(chrome.value, isTrue);
        expect(tester.getRect(dock).width, 52);
        expect(tester.getRect(dock).left, 16);
        await tester.drag(find.byType(ListView), const Offset(0, 12));
        await tester.pumpAndSettle();
        expect(
          chrome.value,
          isTrue,
          reason: 'small reversals must not flash the dock open',
        );
        await tester.tap(find.byTooltip('展开导航 · 书架'));
        await tester.pumpAndSettle();
        expect(tester.getRect(dock), expanded);
        chrome.value = true;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 75));
        final midway = tester.getSize(dock).width;
        chrome.expand();
        await tester.pump();
        if (!reduced) expect(tester.getSize(dock).width, closeTo(midway, .1));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('发现'));
        await tester.pumpAndSettle();
        expect(selected, 1);
        await tester.fling(find.byType(ListView), const Offset(0, -250), 3000);
        await tester.pump(const Duration(milliseconds: 300));
        expect(chrome.value, isTrue);
        await tester.tap(find.byTooltip('展开导航 · 书架'));
        await tester.pumpAndSettle();
        expect(
          chrome.value,
          isFalse,
          reason:
              'remaining inertia must not immediately fold a manually expanded dock',
        );
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .jumpTo(0);
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView), const Offset(0, 800));
        await tester.pumpAndSettle();
        expect(chrome.value, isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        chrome.dispose();
      },
    );
  }

  testWidgets('scroll edges reveal backdrop while center pixels stay intact', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(300, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: key,
          child: Stack(
            children: [
              const Positioned.fill(child: ColoredBox(color: Colors.blue)),
              Positioned.fill(
                child: BrowseEdges(
                  child: SingleChildScrollView(
                    child: Container(height: 1200, color: Colors.red),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -150),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final image =
          await (key.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      final data = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      int channel(int x, int y, int c) => data[(y * image.width + x) * 4 + c];
      expect(channel(150, 1, 2), greaterThan(150));
      expect(channel(150, 200, 0), greaterThan(240));
      expect(channel(150, 200, 2), 54);
      expect(channel(150, 398, 2), greaterThan(150));
      image.dispose();
    });
    expect(tester.takeException(), isNull);
  });
}
