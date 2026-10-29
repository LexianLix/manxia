import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/data/frame_monitor.dart';
import 'package:manxia/ui/smoothness_page.dart';
import 'package:manxia/ui/localized_text.dart';

void main() {
  setUpAll(() async {
    if (Platform.environment['MANXIA_CAPTURE_DIR'] == null) return;
    await (FontLoader(
      'RoomSans',
    )..addFont(rootBundle.load('assets/fonts/NotoSansSC.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en'),
  ]) {
    testWidgets(
      'recording survives leaving its page and returns a readable report: $locale',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final monitor = FrameMonitor.shared;
        addTearDown(monitor.stop);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              locale: locale,
              supportedLocales: [locale],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              theme: ThemeData(fontFamily: 'RoomSans'),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(1.5)),
                child: child!,
              ),
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SmoothnessPage(),
                      ),
                    ),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final start = find.text(translate('开始 20 秒检测', locale));
        await tester.ensureVisible(start);
        await tester.tap(start);
        await tester.pumpAndSettle();
        Navigator.of(tester.element(find.byType(SmoothnessPage))).pop();
        await tester.pumpAndSettle();
        expect(monitor.recording, true);
        final frame = ui.FrameTiming(
          vsyncStart: 0,
          buildStart: 0,
          buildFinish: 2000,
          rasterStart: 2000,
          rasterFinish: 5000,
          rasterFinishWallTime: 5000,
        );
        monitor.ingest([frame]);
        monitor.ingest([frame]);
        monitor.stop();
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.text(translate('记录帧数', locale)), findsOneWidget);
        expect(tester.takeException(), isNull);
        final directory = Platform.environment['MANXIA_CAPTURE_DIR'];
        if (directory != null) {
          await tester.runAsync(() async {
            await Directory(directory).create(recursive: true);
            final render =
                boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await render.toImage();
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            await File(
              '$directory/smoothness-$locale.png',
            ).writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
