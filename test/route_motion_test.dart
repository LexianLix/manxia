import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/ui/room_motion.dart';

void main() {
  testWidgets(
    'ordinary routes coordinate depth, reverse without a pose reset and honor reduced motion',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      final boundary = GlobalKey();
      final directory = Platform.environment['MANXIA_CAPTURE_DIR'];
      var reduced = false;
      late StateSetter update;
      if (directory != null) {
        await tester.runAsync(() async {
          await (FontLoader('ArchiveSerif')..addFont(
                rootBundle.load('assets/fonts/SourceHanSerifCN-Regular.otf'),
              ))
              .load();
          await Directory(directory).create(recursive: true);
        });
      }
      Widget page(String id) => Scaffold(
        key: ValueKey(id),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  id == 'home' ? '我的漫匣' : '阅读设置',
                  style: const TextStyle(fontSize: 32),
                ),
                const Divider(height: 50),
                for (final label in ['阅读方向', '翻页方式', '背景颜色', '工具栏收起'])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Text(label),
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return MaterialApp(
                navigatorKey: navigator,
                debugShowCheckedModeBanner: false,
                theme: ThemeData(
                  fontFamily: 'ArchiveSerif',
                  pageTransitionsTheme: const PageTransitionsTheme(
                    builders: {TargetPlatform.android: RoomPageTransitions()},
                  ),
                ),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(disableAnimations: reduced),
                  child: child!,
                ),
                home: page('home'),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> capture(String name) async {
        if (directory == null) return;
        await tester.runAsync(() async {
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await render.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '$directory/$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      void push() => navigator.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => page('settings')),
      );
      push();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final home = find.byKey(const ValueKey('home'));
      final settings = find.byKey(const ValueKey('settings'));
      expect(tester.getTopLeft(home).dy, lessThan(0));
      expect(
        tester
            .widget<Opacity>(
              find.ancestor(of: settings, matching: find.byType(Opacity)).first,
            )
            .opacity,
        inExclusiveRange(0, 1),
      );
      await capture('route-forward-50');
      final before = tester
          .widget<Opacity>(
            find.ancestor(of: settings, matching: find.byType(Opacity)).first,
          )
          .opacity;
      navigator.currentState!.pop();
      await tester.pump();
      expect(
        tester
            .widget<Opacity>(
              find.ancestor(of: settings, matching: find.byType(Opacity)).first,
            )
            .opacity,
        before,
      );
      await capture('route-reverse-start');
      await tester.pumpAndSettle();
      expect(settings, findsNothing);
      expect(tester.getTopLeft(home), Offset.zero);
      push();
      await tester.pump();
      for (var i = 0; i < 7; i++) {
        await tester.pump(const Duration(milliseconds: 40));
        await capture('route-open-$i');
      }
      await tester.pumpAndSettle();
      navigator.currentState!.pop();
      await tester.pump();
      for (var i = 0; i < 7; i++) {
        await tester.pump(const Duration(milliseconds: 40));
        await capture('route-close-$i');
      }
      await tester.pumpAndSettle();
      update(() => reduced = true);
      await tester.pump();
      push();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(tester.getTopLeft(settings), Offset.zero);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
