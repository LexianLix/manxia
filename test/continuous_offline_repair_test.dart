import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/dm5_source.dart';
import 'package:manxia/data/library.dart';
import 'package:manxia/data/offline_library.dart';
import 'package:manxia/platform/blob_store.dart';
import 'package:manxia/ui/continuous_strip.dart';
import 'package:manxia/ui/reader_surfaces.dart';
import 'package:manxia/ui/reader_page.dart';
import 'features_test.dart' as fixtures;

class _RepairLibrary extends OfflineLibrary {
  _RepairLibrary(super.library, super.source, this.blobs, this.image)
    : super(store: blobs);
  final MemoryBlobStore blobs;
  final Uint8List image;
  int calls = 0;
  @override
  Future<void> repairPage(String address) async {
    calls++;
    await blobs.write(address.substring(8), image);
  }
}

class _OfflineSource extends Dm5Source {
  @override
  Future<List<String>> pages(String path) async => ['offline:missing'];
}

void main() {
  testWidgets('reader first-screen retry repairs the failed offline page', (
    tester,
  ) async {
    late Library library;
    late Uint8List png;
    await tester.runAsync(() async {
      library = await fixtures.library();
      png = (await rootBundle.load(
        'assets/characters/xiaxia/idle.png',
      )).buffer.asUint8List();
    });
    final source = _OfflineSource(), store = MemoryBlobStore();
    final offline = _RepairLibrary(library, source, store, png);
    const chapter = Chapter('/offline-repair/', '修复章节');
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: ReaderPage(
          comic: fixtures.comic,
          chapter: chapter,
          chapters: const [chapter],
          library: library,
          source: source,
          web: false,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('重新加载').first);
    for (var i = 0; i < 3; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
    }
    await tester.pumpAndSettle();
    expect(offline.calls, 1);
    expect(library.record(fixtures.comic)?.chapterPath, chapter.path);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    offline.dispose();
    source.close();
    library.dispose();
    OfflineLibrary.instance = null;
  });
  testWidgets(
    'continuous offline page retries the requested file and paints it',
    (tester) async {
      late Library library;
      late Uint8List png;
      await tester.runAsync(() async {
        library = await fixtures.library();
        png = (await rootBundle.load(
          'assets/characters/xiaxia/idle.png',
        )).buffer.asUint8List();
      });
      final source = Dm5Source(),
          store = MemoryBlobStore(),
          control = ReaderControl();
      final offline = _RepairLibrary(library, source, store, png);
      var ready = false;
      const chapter = Chapter('/offline-repair/', '修复章节');
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(
            body: ContinuousStrip(
              chapter: chapter,
              urls: const ['offline:missing'],
              catalog: const [chapter],
              source: source,
              control: control,
              startPage: 0,
              position: 0,
              web: false,
              onPosition: (_, _, _, _) {},
              onReady: () => ready = true,
              onInitialError: (_) {},
              onRestart: (_) {},
              active: true,
              warm: false,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
      expect(find.text('重新加载图片'), findsOneWidget);
      await tester.tap(find.text('重新加载图片'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)),
      );
      await tester.pumpAndSettle();
      expect(offline.calls, 1);
      expect(store.data['missing'], png);
      expect(ready, isTrue);
      expect(find.text('重新加载图片'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      offline.dispose();
      control.dispose();
      source.close();
      library.dispose();
      OfflineLibrary.instance = null;
    },
  );
}
