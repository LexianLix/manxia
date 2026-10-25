import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:manxia/data/dm5_source.dart';
import 'package:manxia/data/library.dart';
import 'package:manxia/data/offline_library.dart';
import 'package:manxia/platform/blob_store.dart';
import 'package:manxia/ui/reader_layout.dart';
import 'package:manxia/ui/reader_surfaces.dart';

void main() {
  setUpAll(() async {
    if (Platform.environment['MANXIA_CAPTURE_DIR'] == null) return;
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  testWidgets('layout reversal retains the painted layers, page and zoom', (
    tester,
  ) async {
    final f = await _Fixture.start(tester);
    f.control.go(1);
    await _decode(tester);
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    viewer.transformationController!.value = Matrix4.identity()
      ..translateByDouble(-30, -40, 0, 1)
      ..scaleByDouble(1.6, 1.6, 1, 1);
    await tester.pump();
    await f.capture(tester, '01-horizontal');
    f.mode = 'vertical';
    await f.build(tester);
    await _decode(tester, settle: false);
    await tester.pump(const Duration(milliseconds: 35));
    await f.capture(tester, '02-changing');
    final before = _opacities(tester);
    expect(before.length, 2);
    expect(before.every((v) => v > 0 && v < 1), isTrue);
    f.mode = 'page';
    await f.build(tester);
    final after = _opacities(tester);
    expect(after.take(2), orderedEquals(before));
    await _decode(tester);
    expect(find.byType(PagedSurface), findsOneWidget);
    expect(f.page, 1);
    expect(
      tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!
          .value
          .getMaxScaleOnAxis(),
      closeTo(1.6, .001),
    );
    await f.capture(tester, '03-reversed');
    f.mode = 'strip';
    await f.build(tester);
    await _decode(tester);
    f.control.go(2);
    await _decode(tester);
    f.mode = 'page';
    await f.build(tester);
    await _decode(tester);
    expect(f.page, 2);
    expect(
      tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!
          .value
          .getMaxScaleOnAxis(),
      1,
      reason: 'Zoom from an earlier page must not be applied to another page.',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'strip position survives a round trip when the page is unchanged',
    (tester) async {
      final f = await _Fixture.start(tester, mode: 'strip', position: .3);
      expect(f.fraction, closeTo(.3, .015));
      f.mode = 'page';
      await f.build(tester);
      await _decode(tester);
      expect(f.page, 0);
      f.mode = 'strip';
      await f.build(tester);
      await _decode(tester);
      expect(f.fraction, closeTo(.3, .015));
      await f.capture(tester, '04-strip-restored');
      f.control.go(1, position: .25);
      await _decode(tester);
      expect(f.page, 1);
      expect(f.fraction, closeTo(.25, .015));
      f.mode = 'vertical';
      await f.build(tester);
      await _decode(tester);
      expect(f.page, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final cancel in [false, true]) {
    testWidgets('a spread waits for its second image; cancel=$cancel', (
      tester,
    ) async {
      final f = await _Fixture.start(tester, delayed: true, startPage: 1);
      final original = tester.state(find.byType(PagedSurface));
      f.paired = true;
      await f.build(tester);
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(PagedSurface), findsNWidgets(2));
      expect(_opacities(tester), [1, 0]);
      expect(f.ready, 1);
      await f.capture(tester, '05-waiting-spread-$cancel');
      if (cancel) {
        f.paired = false;
        await f.build(tester);
        expect(tester.state(find.byType(PagedSurface)), same(original));
      }
      f.store.waiting.complete(await f.store.read('page1'));
      await _decode(tester);
      expect(find.byType(PagedSurface), findsOneWidget);
      expect(
        tester.widget<PagedSurface>(find.byType(PagedSurface)).doublePage,
        !cancel,
      );
      expect(f.page, 1);
      expect(f.ready, 1);
      await f.capture(tester, '06-spread-$cancel');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a failed spread keeps the old page and can retry', (
    tester,
  ) async {
    final f = await _Fixture.start(tester, delayed: true, startPage: 1);
    f.paired = true;
    await f.build(tester);
    f.store.waiting.complete(null);
    await _decode(tester, settle: false);
    await tester.pump(const Duration(milliseconds: 300));
    expect(_opacities(tester), [1, 0]);
    expect(find.text('新布局图片未就绪，点击重试'), findsOneWidget);
    f.store.retry = true;
    await tester.tap(find.text('新布局图片未就绪，点击重试'));
    await _decode(tester);
    expect(find.text('新布局图片未就绪，点击重试'), findsNothing);
    expect(find.byType(PagedSurface), findsOneWidget);
    expect(f.page, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reduced motion commits ready layouts directly and disposes pending work',
    (tester) async {
      final f = await _Fixture.start(tester);
      f.mode = 'vertical';
      await f.build(tester);
      await _decode(tester, settle: false);
      await tester.pump(const Duration(milliseconds: 20));
      f.reduced = true;
      await f.build(tester);
      await tester.pump();
      expect(_opacities(tester), [1]);
      f.mode = 'strip';
      await f.build(tester);
      await _decode(tester);
      expect(find.byType(PagedSurface), findsNothing);
      expect(find.byType(StripSurface), findsOneWidget);
      f.mode = 'page';
      await f.build(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    },
  );
}

List<double> _opacities(WidgetTester tester) => tester
    .widgetList<Opacity>(
      find.descendant(
        of: find.byType(ReaderLayout),
        matching: find.byType(Opacity),
      ),
    )
    .map((o) => o.opacity)
    .toList();

class _Store extends MemoryBlobStore {
  final waiting = Completer<Uint8List?>();
  bool retry = false;
  @override
  Future<Uint8List?> read(String key) => key == 'wait'
      ? retry
            ? super.read('page1')
            : waiting.future
      : super.read(key);
}

class _Fixture {
  final boundary = GlobalKey();
  final control = ReaderControl();
  final store = _Store();
  String mode = 'page';
  bool paired = false, reduced = false, delayed = false;
  int page = 0, ready = 0, startPage = 0;
  double fraction = 0, position = 0;
  static Future<_Fixture> start(
    WidgetTester tester, {
    String mode = 'page',
    double position = 0,
    bool delayed = false,
    int startPage = 0,
  }) async {
    final f = _Fixture()
      ..mode = mode
      ..position = position
      ..delayed = delayed
      ..startPage = startPage;
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      final library = Library(await SharedPreferences.getInstance());
      await library.load();
      final source = Dm5Source();
      OfflineLibrary(library, source, store: f.store);
      addTearDown(source.close);
      for (var p = 0; p < 3; p++) {
        final recorder = ui.PictureRecorder(), paint = Paint();
        final canvas = Canvas(recorder);
        canvas.drawColor(const Color(0xffeee9dd), BlendMode.src);
        for (var i = 0; i < 4; i++) {
          paint.color = [
            const Color(0xff47775e),
            const Color(0xff466c9f),
            const Color(0xffad765e),
          ][p].withValues(alpha: .4 + i * .15);
          canvas.drawRect(Rect.fromLTWH(15, 15 + i * 200, 330, 185), paint);
        }
        final picture = recorder.endRecording(),
            image = await picture.toImage(360, 820);
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.png,
        ))!.buffer.asUint8List();
        await f.store.write('page$p', bytes);
        picture.dispose();
        image.dispose();
      }
    });
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      if (!f.store.waiting.isCompleted) f.store.waiting.complete(null);
      f.control.dispose();
      OfflineLibrary.instance = null;
    });
    await f.build(tester);
    await _decode(tester);
    expect(f.ready, 1);
    return f;
  }

  Future<void> build(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
        child: child!,
      ),
      home: Scaffold(
        backgroundColor: const Color(0xff111512),
        body: RepaintBoundary(
          key: boundary,
          child: ReaderLayout(
            urls: [
              'offline:page0',
              'offline:page1',
              delayed ? 'offline:wait' : 'offline:page2',
            ],
            web: false,
            mode: mode,
            rtl: false,
            paired: paired,
            startPage: startPage,
            position: position,
            control: control,
            onPosition: (p, f) {
              page = p;
              fraction = f;
            },
            onReady: () => ready++,
            onLoadError: () {},
            paper: false,
            crop: 0,
            autoCrop: false,
            decodeWidth: 1000,
            speed: 0,
          ),
        ),
      ),
    ),
  );

  Future<void> capture(WidgetTester tester, String name) async {
    final directory = Platform.environment['MANXIA_CAPTURE_DIR'];
    if (directory == null) return;
    await tester.runAsync(() async {
      await Directory(directory).create(recursive: true);
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '$directory/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }
}

Future<void> _decode(WidgetTester tester, {bool settle = true}) async {
  await tester.pump();
  if (settle) await tester.pump(const Duration(milliseconds: 300));
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
  });
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
  if (settle) await tester.pumpAndSettle();
}
