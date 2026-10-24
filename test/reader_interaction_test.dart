import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:manxia/data/dm5_source.dart';
import 'package:manxia/data/library.dart';
import 'package:manxia/data/offline_library.dart';
import 'package:manxia/platform/blob_store.dart';
import 'package:manxia/ui/reader_surfaces.dart';
import 'package:manxia/ui/room_scroll.dart';

void main() {
  for (final direction in ['ltr', 'rtl', 'vertical']) {
    testWidgets(
      '$direction dragging, cancelling and retargeting retain decoded pages',
      (tester) async {
        final f = await _Fixture.start(tester, direction: direction);
        final controller = tester
            .widget<PageView>(find.byType(PageView))
            .controller!;
        final original = tester.state(
          find.byWidgetPredicate(
            (w) => w is PagePicture && w.url == f.urls.first,
          ),
        );
        final rtl = direction == 'rtl', vertical = direction == 'vertical';
        final origin = vertical
            ? const Offset(200, 640)
            : Offset(rtl ? 60 : 330, 420);
        final delta = vertical
            ? const Offset(0, -200)
            : Offset(rtl ? 180 : -180, 0);
        final gesture = await tester.startGesture(origin);
        await gesture.moveBy(delta * .2);
        await tester.pump();
        await gesture.moveBy(delta * .6);
        await tester.pump();
        expect(controller.page, inExclusiveRange(0, 1));
        if (direction != 'vertical') {
          final cover = tester.widget<PagePicture>(
            find.byWidgetPredicate(
              (w) => w is PagePicture && w.url == f.urls.first,
            ),
          );
          expect(
            cover.curl.isNegative,
            rtl,
            reason: 'The paper fold must follow the actual reading direction.',
          );
          final incoming = tester.widget<PagePicture>(
            find.byWidgetPredicate(
              (w) => w is PagePicture && w.url == f.urls[1],
            ),
          );
          expect(
            incoming.curl,
            0,
            reason:
                'Only the outgoing sheet bends; folding both pages leaves an empty gap.',
          );
          final alpha = await tester.runAsync(() async {
            final render =
                f.boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await render.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            final value = bytes!.getUint8(
              (420 * 390 + (rtl ? 120 : 270)) * 4 + 3,
            );
            image.dispose();
            return value;
          });
          expect(
            alpha,
            255,
            reason:
                'The folded paper back must cover the gap up to the incoming page.',
          );
        }
        await f.capture(tester, '$direction-drag');
        await gesture.moveBy(delta * -.5);
        await tester.pump();
        await f.capture(tester, '$direction-reverse');
        // Return near the origin before cancelling; the release velocity is zero.
        await gesture.moveTo(origin + delta * .03);
        await tester.pump(const Duration(milliseconds: 150));
        await gesture.cancel();
        await tester.pumpAndSettle();
        expect(controller.page, closeTo(0, .001));
        expect(
          tester.state(
            find.byWidgetPredicate(
              (w) => w is PagePicture && w.url == f.urls.first,
            ),
          ),
          same(original),
        );
        f.control.go(1);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        final midway = controller.page!;
        expect(midway, inExclusiveRange(0, 1));
        f.control.go(0);
        await tester.pump();
        expect(controller.page, closeTo(midway, .001));
        await tester.pumpAndSettle();
        expect(controller.page, closeTo(0, .001));
        await f.capture(tester, '$direction-settled');
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('pinch zoom keeps page fixed and enables image panning', (
    tester,
  ) async {
    final f = await _Fixture.start(tester);
    final controller = tester
        .widget<PageView>(find.byType(PageView))
        .controller!;
    final zoom = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;
    final left = await tester.startGesture(const Offset(140, 420), pointer: 1);
    final right = await tester.startGesture(const Offset(250, 420), pointer: 2);
    await tester.pump();
    await left.moveTo(const Offset(90, 420));
    await right.moveTo(const Offset(300, 420));
    await tester.pump();
    await left.moveTo(const Offset(60, 420));
    await right.moveTo(const Offset(330, 420));
    await tester.pump();
    expect(zoom.value.getMaxScaleOnAxis(), greaterThan(1.2));
    await left.up();
    await right.up();
    await tester.pumpAndSettle();
    final page = controller.page;
    final before = zoom.value.storage.toList();
    await tester.dragFrom(const Offset(240, 400), const Offset(-60, -50));
    await tester.pumpAndSettle();
    expect(controller.page, closeTo(page!, .001));
    expect(zoom.value.storage.toList(), isNot(equals(before)));
    f.control.go(1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(controller.page, closeTo(1, .001));
    expect(zoom.value.getMaxScaleOnAxis(), closeTo(1, .001));
    expect(tester.takeException(), isNull);
  });
  testWidgets('strip reduced motion jumps directly to the requested image', (
    tester,
  ) async {
    final f = await _Fixture.start(tester, strip: true, reduced: true);
    f.control.go(2);
    await tester.pump();
    await tester.pump();
    expect(f.page, 2);
    expect(f.control.target, isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'enabling reduced motion during a turn settles at the requested page',
    (tester) async {
      final f = await _Fixture.start(tester);
      final controller = tester
          .widget<PageView>(find.byType(PageView))
          .controller!;
      f.control.go(2);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(controller.page, inExclusiveRange(0, 2));
      f.update(() => f.reduced = true);
      await tester.pump();
      await tester.pump();
      expect(controller.page, closeTo(2, .001));
      expect(f.control.target, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}

class _Fixture {
  final control = ReaderControl();
  final boundary = GlobalKey();
  final urls = List.generate(4, (i) => 'offline:gesture-$i');
  late StateSetter update;
  bool reduced = false;
  int page = 0;
  static Future<_Fixture> start(
    WidgetTester tester, {
    String direction = 'ltr',
    bool strip = false,
    bool reduced = false,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final f = _Fixture()..reduced = reduced;
    final source = Dm5Source();
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      final library = Library(await SharedPreferences.getInstance());
      await library.load();
      final store = MemoryBlobStore();
      OfflineLibrary(library, source, store: store);
      for (var i = 0; i < f.urls.length; i++) {
        final recorder = ui.PictureRecorder(),
            canvasColor = [
              const Color(0xffd6e0cb),
              const Color(0xffd2dbea),
              const Color(0xffe4d3c3),
              const Color(0xffb6cbbb),
            ][i];
        final canvas = Canvas(recorder);
        const rect = Rect.fromLTWH(0, 0, 360, 640);
        canvas.drawRect(rect, Paint()..color = canvasColor);
        for (var j = 0; j < 5; j++) {
          canvas.drawRect(
            Rect.fromLTWH(20, 24 + j * 121, 320, 104),
            Paint()
              ..color = Color.lerp(
                canvasColor,
                const Color(0xff405644),
                .12 + .09 * j,
              )!,
          );
          canvas.drawLine(
            Offset(40, 50 + j * 121),
            Offset(290, 50 + j * 121),
            Paint()
              ..color = const Color(0xfff6f5ed)
              ..strokeWidth = 4,
          );
        }
        final picture = recorder.endRecording(),
            image = await picture.toImage(360, 640);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await store.write('gesture-$i', bytes!.buffer.asUint8List());
        image.dispose();
        picture.dispose();
      }
    });
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      f.control.dispose();
      source.close();
      OfflineLibrary.instance = null;
    });
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const RoomScrollBehavior(),
        debugShowCheckedModeBanner: false,
        home: StatefulBuilder(
          builder: (context, update) {
            f.update = update;
            return MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(disableAnimations: f.reduced),
              child: Scaffold(
                backgroundColor: const Color(0xff111512),
                body: RepaintBoundary(
                  key: f.boundary,
                  child: strip
                      ? StripSurface(
                          urls: f.urls,
                          web: false,
                          startPage: 0,
                          position: 0,
                          control: f.control,
                          onPosition: (p, _) => f.page = p,
                        )
                      : PagedSurface(
                          urls: f.urls,
                          web: false,
                          startPage: 0,
                          control: f.control,
                          onPosition: (p, _) => f.page = p,
                          paper: true,
                          rtl: direction == 'rtl',
                          vertical: direction == 'vertical',
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    return f;
  }

  Future<void> capture(WidgetTester tester, String name) async {
    final dir = Platform.environment['MANXIA_CAPTURE_DIR'];
    if (dir == null) return;
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pump();
    await tester.runAsync(() async {
      await Directory(dir).create(recursive: true);
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }
}
