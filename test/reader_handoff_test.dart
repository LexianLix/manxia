import 'dart:async';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/dm5_source.dart';
import 'package:manxia/data/library.dart';
import 'package:manxia/data/offline_library.dart';
import 'package:manxia/platform/blob_store.dart';
import 'package:manxia/ui/reader_page.dart';
import 'package:manxia/ui/reader_surfaces.dart';
import 'package:manxia/ui/room_motion.dart';
import 'package:manxia/ui/localized_text.dart';

const comic = Comic(
  path: '/handoff-reader/',
  title: 'Reader',
  cover: 'offline:old',
);
const a = Chapter('/old/', 'Old chapter'), b = Chapter('/new/', 'New chapter');
const c = Chapter('/third/', 'Third chapter');
void main() {
  testWidgets(
    'warmth changes the reading canvas and can be reset without changing the page',
    (tester) async {
      final f = await _Fixture.start(tester);
      Future<Uint8List> centerPixel() async {
        late Uint8List value;
        await tester.runAsync(() async {
          final render =
              f.boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await render.toImage(pixelRatio: 1);
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!.buffer.asUint8List();
          final at = ((image.height ~/ 2) * image.width + image.width ~/ 2) * 4;
          value = Uint8List.fromList(bytes.sublist(at, at + 4));
          image.dispose();
        });
        return value;
      }

      final neutral = await centerPixel();
      await tester.tap(find.byTooltip('阅读设置'));
      await tester.pumpAndSettle();
      final warmth = find
          .ancestor(of: find.text('护眼暖色'), matching: find.byType(Column))
          .first;
      final slider = find
          .descendant(of: warmth, matching: find.byType(Slider))
          .first;
      await tester.ensureVisible(slider);
      tester.widget<Slider>(slider).onChanged!(.8);
      await tester.pumpAndSettle();
      expect(f.library.readerOptions(comic)['warmth'], .8);
      final tint = find.byKey(const ValueKey('reader-warmth'));
      expect(tint, findsOneWidget);
      expect(tester.widget<ColoredBox>(tint).color.a, greaterThan(0));
      await f.capture(tester, 'reader-warmth-settings');
      Navigator.of(tester.element(find.byType(BottomSheet))).pop();
      await tester.pumpAndSettle();
      final warm = await centerPixel();
      expect(warm[0], greaterThan(neutral[0] + 20));
      await f.capture(tester, 'reader-warmth-page');
      await tester.tap(find.byTooltip('阅读设置'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(slider);
      tester.widget<Slider>(slider).onChanged!(0);
      await tester.pumpAndSettle();
      expect(tester.widget<ColoredBox>(tint).color.a, 0);
      Navigator.of(tester.element(find.byType(BottomSheet))).pop();
      await tester.pumpAndSettle();
      expect(await centerPixel(), neutral);
      await f.capture(tester, 'reader-neutral-page');
      expect(f.library.record(comic)!.page, 0);
      expect(tester.takeException(), isNull);
    },
  );
  setUpAll(() async {
    await (FontLoader('ArchiveSerif')..addFont(
          rootBundle.load('assets/fonts/SourceHanSerifCN-Regular.otf'),
        ))
        .load();
    if (Platform.environment['MANXIA_CAPTURE_DIR'] == null) return;
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final locale in [const Locale('zh', 'TW'), const Locale('en')]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('localized reader settings fit a phone: $locale x$scale', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final f = await _Fixture.start(
          tester,
          locale: locale,
          textScale: scale,
        );
        String label(String text) => translate(text, locale);
        await tester.tap(find.byTooltip(label('阅读设置')));
        await tester.pumpAndSettle();
        expect(find.text(label('横向')), findsOneWidget);
        expect(find.text(label('连续条漫')), findsOneWidget);
        expect(find.text(label('竖向')), findsOneWidget);
        for (final text in ['横向', '连续条漫', '竖向']) {
          final translated = label(text);
          final paragraph = tester.renderObject<RenderParagraph>(
            find.text(translated),
          );
          expect(
            paragraph.getBoxesForSelection(
              TextSelection(baseOffset: 0, extentOffset: translated.length),
            ),
            hasLength(1),
            reason: 'Mode labels must remain readable without splitting words.',
          );
        }
        expect(find.text(label('护眼暖色')), findsOneWidget);
        await f.capture(tester, 'localized-settings-$locale-$scale');
        expect(tester.takeException(), isNull);
        await tester.tap(find.text(label('连续条漫')));
        await _decode(tester);
        expect(f.library.readerOptions(comic)['mode'], 'strip');
        expect(find.text(label('自动滚动速度（0 为关闭）')), findsOneWidget);
        Navigator.of(tester.element(find.byType(BottomSheet))).pop();
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip(label('章节与书签')));
        await tester.pumpAndSettle();
        expect(find.text(label('章节目录')), findsOneWidget);
        expect(find.text(label('我的书签')), findsOneWidget);
        await f.capture(tester, 'localized-catalog-$locale-$scale');
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final reduced in [false, true]) {
    testWidgets(
      'phone reader sheets share motion and preserve the page; reduced=$reduced',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final f = await _Fixture.start(tester, reduced: reduced);
        await tester.tap(find.byTooltip('阅读设置'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        final sheet = ModalRoute.of(tester.element(find.byType(BottomSheet)))!;
        expect(
          sheet.transitionDuration,
          reduced ? Duration.zero : RoomMotion.page,
        );
        expect(
          sheet.reverseTransitionDuration,
          reduced ? Duration.zero : RoomMotion.feedback,
        );
        await f.capture(tester, 'settings-enter-$reduced');
        await tester.pumpAndSettle();
        await f.capture(tester, 'settings-phone-$reduced');
        await tester.tap(find.text('连续条漫'));
        await _decode(tester);
        expect(find.byType(StripSurface), findsOneWidget);
        expect(f.library.readerOptions(comic)['mode'], 'strip');
        final top = tester.getTopLeft(find.byType(BottomSheet));
        await tester.dragFrom(
          top + const Offset(195, 15),
          const Offset(0, 650),
        );
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
        expect(f.library.record(comic)!.page, 0);
        await tester.tap(find.byTooltip('章节与书签'));
        await tester.pumpAndSettle();
        await f.capture(tester, 'catalog-phone-$reduced');
        await tester.tap(find.text('我的书签'));
        await tester.pumpAndSettle();
        expect(find.text('还没有书签，点击阅读器右上角添加。'), findsOneWidget);
        Navigator.of(tester.element(find.byType(BottomSheet))).pop();
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('添加书签'));
        await tester.pumpAndSettle();
        await f.capture(tester, 'bookmark-phone-$reduced');
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'a wide spread waits for both initial images before replacing the previous record',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = await _Fixture.start(
        tester,
        initial: b,
        initialPage: 1,
        waitInitial: false,
      );
      f.source.next.complete([
        'offline:unused',
        'offline:new',
        'offline:third',
      ]);
      f.store.next.complete(f.bytes);
      await tester.pump();
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump(const Duration(milliseconds: 250));
      expect(f.library.record(comic)!.chapterPath, a.path);
      f.store.third.complete(f.bytes);
      await _decode(tester);
      expect(f.library.record(comic)!.chapterPath, b.path);
      expect(f.library.record(comic)!.page, 1);
      expect(find.text('2–3 / 3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final mode in ['page', 'strip']) {
    testWidgets(
      '$mode reduced-motion handoff commits the decoded page without moving its viewport',
      (tester) async {
        final f = await _Fixture.start(tester, mode: mode, reduced: true);
        await tester.tap(find.text('下一章'));
        await tester.pump();
        f.source.next.complete(['offline:new']);
        f.store.next.complete(f.bytes);
        await _decode(tester);
        expect(f.library.record(comic)!.chapterPath, b.path);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'a prepared strip restores its fractional position before appearing',
    (tester) async {
      final f = await _Fixture.start(
        tester,
        mode: 'strip',
        initial: b,
        initialPage: 0,
        initialPosition: .3,
        waitInitial: false,
      );
      f.source.next.complete(['offline:new']);
      await tester.pump();
      final prepared = find.byType(StripSurface);
      final state = tester.state(prepared);
      f.store.next.complete(f.bytes);
      await _decode(tester);
      expect(tester.state(prepared), same(state));
      expect(f.library.record(comic)!.chapterPath, b.path);
      expect(f.library.record(comic)!.position, closeTo(.3, .01));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'a later catalog selection wins over an earlier chapter response',
    (tester) async {
      final f = await _Fixture.start(tester, catalog: const [a, b, c]);
      await tester.tap(find.text('下一章'));
      await tester.pump();
      await tester.tap(find.byTooltip('章节与书签'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Third chapter'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(f.source.pending, hasLength(2));
      f.source.pending.first.complete(['offline:new']);
      f.source.pending.last.complete(['offline:third']);
      f.store.third.complete(f.bytes);
      await _decode(tester);
      expect(f.library.record(comic)!.chapterPath, c.path);
      expect(
        find.byWidgetPredicate(
          (w) => w is PagePicture && w.url == 'offline:new',
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'prepared chapter keeps its decoded surface when becoming visible',
    (tester) async {
      final f = await _Fixture.start(tester);
      await tester.tap(find.text('下一章'));
      await tester.pump();
      f.source.next.complete(['offline:new']);
      await tester.pump();
      final prepared = find.byWidgetPredicate(
        (w) => w is PagedSurface && w.urls.first == 'offline:new',
      );
      expect(prepared, findsOneWidget);
      final state = tester.state(prepared);
      f.store.next.complete(f.bytes);
      await _decode(tester);
      expect(tester.state(prepared), same(state));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('a decoded next chapter commits only after it is presented', (
    tester,
  ) async {
    if (Platform.environment['MANXIA_CAPTURE_DIR'] != null) {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    final f = await _Fixture.start(tester);
    await f.capture(tester, 'current');
    await tester.tap(find.text('下一章'));
    await tester.pump();
    f.source.next.complete(['offline:new']);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await f.capture(tester, 'preparing');
    expect(f.library.record(comic)!.chapterPath, a.path);
    f.store.next.complete(f.bytes);
    if (Platform.environment['MANXIA_CAPTURE_DIR'] == null) {
      await _decode(tester);
    } else {
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 25));
        await f.capture(tester, 'blend-$i');
      }
      await tester.pumpAndSettle();
    }
    expect(f.library.record(comic)!.chapterPath, b.path);
    await f.capture(tester, 'committed');
    expect(
      find.byWidgetPredicate((w) => w is PagePicture && w.url == 'offline:old'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'a ready third chapter waits for the visible blend without resetting its poses',
    (tester) async {
      final f = await _Fixture.start(tester, catalog: const [a, b, c]);
      await tester.tap(find.text('下一章'));
      await tester.pump();
      f.source.next.complete(['offline:new']);
      f.store.next.complete(f.bytes);
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 25));
      double alpha() => tester
          .widgetList<Opacity>(
            find.ancestor(
              of: find.byWidgetPredicate(
                (w) => w is PagePicture && w.url == 'offline:new',
              ),
              matching: find.byType(Opacity),
            ),
          )
          .fold(1.0, (value, layer) => value * layer.opacity);
      for (var i = 0; i < 8 && alpha() == 0; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 16));
        });
        await tester.pump(const Duration(milliseconds: 16));
      }
      final before = alpha();
      expect(before, inExclusiveRange(0, 1));
      await tester.tap(find.text('下一章'));
      await tester.pump();
      f.source.next.complete(['offline:third']);
      f.store.third.complete(f.bytes);
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
      expect(alpha(), closeTo(before, .001));
      await _decode(tester);
      expect(f.library.record(comic)!.chapterPath, c.path);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'cancelled image preparation cannot commit when its late frame arrives',
    (tester) async {
      final f = await _Fixture.start(tester);
      await tester.tap(find.text('下一章'));
      await tester.pump();
      f.source.next.complete(['offline:new']);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.text('继续当前章'));
      await tester.pumpAndSettle();
      f.store.next.complete(f.bytes);
      await _decode(tester);
      expect(f.library.record(comic)!.chapterPath, a.path);
      expect(
        find.byWidgetPredicate(
          (w) => w is PagePicture && w.url == 'offline:old',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('a failed request keeps the old frame and a retry can complete', (
    tester,
  ) async {
    final f = await _Fixture.start(tester);
    await tester.tap(find.text('下一章'));
    await tester.pump();
    f.source.next.completeError(SourceException('网络暂时不可用'));
    await tester.pumpAndSettle();
    expect(f.library.record(comic)!.chapterPath, a.path);
    expect(
      find.byWidgetPredicate((w) => w is PagePicture && w.url == 'offline:old'),
      findsOneWidget,
    );
    await tester.tap(find.text('重试'));
    await tester.pump();
    f.source.next.complete(['offline:new']);
    f.store.next.complete(f.bytes);
    await _decode(tester);
    expect(f.library.record(comic)!.chapterPath, b.path);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'a corrupt next image keeps the old chapter and can be cancelled',
    (tester) async {
      final f = await _Fixture.start(tester);
      await tester.tap(find.text('下一章'));
      await tester.pump();
      f.source.next.complete(['offline:new']);
      f.store.next.complete(Uint8List.fromList([1, 2, 3]));
      await _decode(tester);
      expect(find.text('这一章的首屏图片加载失败，可以重试。'), findsOneWidget);
      expect(f.library.record(comic)!.chapterPath, a.path);
      await tester.tap(find.text('继续当前章'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  for (final waitForImage in [false, true]) {
    testWidgets(
      waitForImage
          ? 'new chapter is not saved before its actual image is ready'
          : 'previous decoded page remains while the next chapter request waits',
      (tester) async {
        late Library library;
        final source = _Pages();
        final store = _Store();
        await tester.runAsync(() async {
          SharedPreferences.setMockInitialValues({});
          library = Library(await SharedPreferences.getInstance());
          await library.load();
          OfflineLibrary(library, source, store: store);
          final recorder = ui.PictureRecorder();
          ui.Canvas(
            recorder,
          ).drawColor(const ui.Color(0xff47775e), ui.BlendMode.src);
          final picture = recorder.endRecording();
          final image = await picture.toImage(120, 180);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await store.write('old', bytes!.buffer.asUint8List());
          image.dispose();
          picture.dispose();
        });
        addTearDown(() {
          if (!store.next.isCompleted) store.next.complete(null);
          for (final value in source.pending) {
            if (!value.isCompleted) value.complete([]);
          }
          source.close();
          OfflineLibrary.instance = null;
        });
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: ReaderPage(
              comic: comic,
              chapter: a,
              chapters: const [a, b],
              library: library,
              source: source,
              web: false,
            ),
          ),
        );
        await tester.pump();
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        expect(library.record(comic)!.chapterPath, a.path);
        await tester.tap(find.text('下一章'));
        await tester.pump();
        if (waitForImage) {
          source.next.complete(['offline:new']);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
        }
        if (waitForImage) {
          expect(
            library.record(comic)!.chapterPath,
            a.path,
            reason: 'A list of URLs is not a decoded new page',
          );
        } else {
          expect(
            find.byWidgetPredicate(
              (w) => w is PagePicture && w.url == 'offline:old',
            ),
            findsOneWidget,
          );
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}

class _Store extends MemoryBlobStore {
  final next = Completer<Uint8List?>();
  final third = Completer<Uint8List?>();
  @override
  Future<Uint8List?> read(String key) => key == 'new'
      ? next.future
      : key == 'third'
      ? third.future
      : super.read(key);
}

class _Pages extends Dm5Source {
  final calls = <String>[];
  final pending = <Completer<List<String>>>[];
  Completer<List<String>> get next => pending.last;
  @override
  Future<List<String>> pages(String path) async {
    calls.add(path);
    if (path == a.path) return ['offline:old'];
    final response = Completer<List<String>>();
    pending.add(response);
    return response.future;
  }
}

class _Fixture {
  _Fixture(this.library, this.source, this.store, this.bytes, this.boundary);
  final GlobalKey boundary;
  final Library library;
  final _Pages source;
  final _Store store;
  final Uint8List bytes;
  static Future<_Fixture> start(
    WidgetTester tester, {
    String mode = 'page',
    bool reduced = false,
    List<Chapter> catalog = const [a, b],
    Chapter initial = a,
    int? initialPage,
    double initialPosition = 0,
    bool waitInitial = true,
    Locale locale = const Locale('zh', 'CN'),
    double textScale = 1,
  }) async {
    final source = _Pages(), store = _Store();
    final boundary = GlobalKey();
    late Library library;
    late Uint8List bytes;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      library = Library(await SharedPreferences.getInstance());
      await library.load();
      await library.setReaderOption(comic, 'mode', mode);
      if (initial.path != a.path) {
        await library.save(
          const ReadingRecord(
            comic: comic,
            chapterPath: '/old/',
            chapterTitle: 'Old chapter',
            page: 0,
            total: 1,
            updatedAt: 1,
          ),
        );
      }
      OfflineLibrary(library, source, store: store);
      final recorder = ui.PictureRecorder();
      ui.Canvas(
        recorder,
      ).drawColor(const ui.Color(0xff47775e), ui.BlendMode.src);
      final picture = recorder.endRecording();
      final image = await picture.toImage(120, 180);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      bytes = data!.buffer.asUint8List();
      await store.write('old', bytes);
      image.dispose();
      picture.dispose();
      final blueRecorder = ui.PictureRecorder();
      ui.Canvas(
        blueRecorder,
      ).drawColor(const ui.Color(0xff466c9f), ui.BlendMode.src);
      final blue = blueRecorder.endRecording();
      final frame = await blue.toImage(120, 180);
      bytes = (await frame.toByteData(
        format: ui.ImageByteFormat.png,
      ))!.buffer.asUint8List();
      frame.dispose();
      blue.dispose();
    });
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      if (!store.next.isCompleted) store.next.complete(null);
      if (!store.third.isCompleted) store.third.complete(null);
      for (final value in source.pending) {
        if (!value.isCompleted) value.complete([]);
      }
      source.close();
      OfflineLibrary.instance = null;
    });
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: reduced,
              textScaler: TextScaler.linear(textScale),
            ),
            child: child!,
          ),
          locale: locale,
          supportedLocales: const [
            Locale('zh', 'CN'),
            Locale('zh', 'TW'),
            Locale('en'),
          ],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: ReaderPage(
            comic: comic,
            chapter: initial,
            initialPage: initialPage,
            initialPosition: initialPosition,
            chapters: catalog,
            library: library,
            source: source,
            web: false,
          ),
        ),
      ),
    );
    if (waitInitial) {
      await _decode(tester);
    } else {
      await tester.pump();
    }
    return _Fixture(library, source, store, bytes, boundary);
  }

  Future<void> capture(WidgetTester tester, String name) async {
    final directory = Platform.environment['MANXIA_CAPTURE_DIR'];
    if (directory == null) return;
    await tester.runAsync(() async {
      await Directory(directory).create(recursive: true);
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: 1),
          bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '$directory/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }
}

Future<void> _decode(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pumpAndSettle();
}
