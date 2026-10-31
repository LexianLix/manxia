import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/dm5_source.dart';
import 'package:manxia/data/offline_library.dart';
import 'package:manxia/platform/blob_store.dart';
import 'package:manxia/ui/continuous_strip.dart';
import 'package:manxia/ui/reader_surfaces.dart';
import 'package:manxia/ui/localized_text.dart';
import 'features_test.dart' as fixtures;
import 'reader_surfaces_test.dart' show longImage;

class _Source extends Dm5Source {
  _Source(this.urls);
  final List<String> urls;
  Completer<List<String>>? previous;
  bool failNext = false;
  final calls = <String>[];
  @override
  Future<List<String>> pages(String path) async {
    calls.add(path);
    if (path == '/c0/' && previous != null) return previous!.future;
    if (failNext) throw SourceException('offline');
    return urls;
  }
}

Future<List<String>> prepare(WidgetTester tester) async {
  late List<String> urls;
  await tester.runAsync(() async {
    final library = await fixtures.library();
    final offline = OfflineLibrary(
      library,
      Dm5Source(),
      store: MemoryBlobStore(),
    );
    await offline.initialize();
    final bytes = await longImage();
    await offline.importImages(
      'Stream',
      List.generate(4, (i) => (name: '$i.png', bytes: bytes)),
    );
    urls = (await offline.pages(offline.entries.single['chapter']['path']))!;
  });
  return urls;
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 30));
  }
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() {
    OfflineLibrary.instance?.dispose();
    OfflineLibrary.instance?.source.close();
    OfflineLibrary.instance = null;
  });
  testWidgets(
    'prepending a chapter retains the exact long-image anchor and current chapter',
    (tester) async {
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final urls = await prepare(tester), control = ReaderControl();
      final source = _Source(urls)..previous = Completer<List<String>>();
      addTearDown(source.close);
      String path = '';
      int page = -1;
      double fraction = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ContinuousStrip(
            chapter: const Chapter('/c1/', 'One'),
            urls: urls,
            catalog: const [Chapter('/c0/', 'Zero'), Chapter('/c1/', 'One')],
            source: source,
            control: control,
            startPage: 1,
            position: .3,
            web: false,
            onPosition: (c, _, p, f) {
              path = c.path;
              page = p;
              fraction = f;
            },
            onReady: () {},
            onInitialError: (e) => fail('$e'),
            onRestart: (_) {},
            active: true,
          ),
        ),
      );
      await settle(tester);
      expect(path, '/c1/');
      expect(page, 1);
      expect(fraction, closeTo(.3, .015));
      expect(source.calls, ['/c0/']);
      source.previous!.complete(urls);
      await settle(tester);
      expect(path, '/c1/');
      expect(page, 1);
      expect(fraction, closeTo(.3, .015));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      control.dispose();
    },
  );
  testWidgets(
    'forward/back navigation reports chapter-local pages and keeps a bounded window',
    (tester) async {
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final urls = await prepare(tester),
          control = ReaderControl(),
          source = _Source(urls);
      addTearDown(source.close);
      String path = '';
      int page = -1;
      final chapters = List.generate(12, (i) => Chapter('/c$i/', 'Chapter $i'));
      await tester.pumpWidget(
        MaterialApp(
          home: ContinuousStrip(
            chapter: chapters.first,
            urls: urls,
            catalog: chapters,
            source: source,
            control: control,
            startPage: 0,
            position: 0,
            web: false,
            onPosition: (c, _, p, _) {
              path = c.path;
              page = p;
            },
            onReady: () {},
            onInitialError: (e) => fail('$e'),
            onRestart: (_) {},
            active: true,
          ),
        ),
      );
      await settle(tester);
      expect(path, '/c0/');
      for (var i = 0; i < 8; i++) {
        final list = tester.widget<ScrollablePositionedList>(
          find.byType(ScrollablePositionedList),
        );
        list.itemScrollController!.jumpTo(index: list.itemCount - 2);
        await settle(tester);
        expect(list.itemCount, lessThanOrEqualTo(37));
      }
      expect(path, isNot('/c0/'));
      expect(page, inInclusiveRange(0, 3));
      final latest = tester.widget<ScrollablePositionedList>(
        find.byType(ScrollablePositionedList),
      );
      expect(latest.itemCount, lessThanOrEqualTo(27));
      latest.itemScrollController!.jumpTo(index: 2);
      await settle(tester);
      expect(page, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      control.dispose();
    },
  );
  testWidgets(
    'neighbor failure retains the visible page and only retries on request',
    (tester) async {
      final urls = await prepare(tester),
          control = ReaderControl(),
          source = _Source(urls)..failNext = true;
      addTearDown(source.close);
      int page = -1;
      await tester.pumpWidget(
        MaterialApp(
          home: ContinuousStrip(
            chapter: const Chapter('/c0/', 'Zero'),
            urls: urls,
            catalog: const [Chapter('/c0/', 'Zero'), Chapter('/c1/', 'One')],
            source: source,
            control: control,
            startPage: 3,
            position: 0,
            web: false,
            onPosition: (_, _, p, _) => page = p,
            onReady: () {},
            onInitialError: (e) => fail('$e'),
            onRestart: (_) {},
            active: true,
          ),
        ),
      );
      await settle(tester);
      expect(page, 3);
      expect(source.calls, ['/c1/']);
      await settle(tester);
      expect(source.calls, ['/c1/']);
      source.failNext = false;
      final list = tester.widget<ScrollablePositionedList>(
        find.byType(ScrollablePositionedList),
      );
      list.itemScrollController!.jumpTo(index: list.itemCount - 1);
      await settle(tester);
      await tester.tap(find.text(translate('邻章准备失败，点此重试', const Locale('en'))));
      await settle(tester);
      expect(source.calls.where((c) => c == '/c1/'), hasLength(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      control.dispose();
    },
  );
}
