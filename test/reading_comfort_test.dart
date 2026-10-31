import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/dm5_source.dart';
import 'package:manxia/data/library.dart';
import 'package:manxia/data/offline_library.dart';
import 'package:manxia/data/reading_progress.dart';
import 'package:manxia/ui/localized_text.dart';
import 'package:manxia/ui/reader_page.dart';
import 'features_test.dart' as fixtures;
import 'reader_test.dart' show cacheReaderImages, settleFirstFrame;

void main() {
  testWidgets(
    'catalog keyboard leaves the reading viewport fixed and keeps search above the keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      late Library library;
      await tester.runAsync(() async {
        library = await fixtures.library();
        await cacheReaderImages(library);
      });
      final source = Dm5Source(
        client: MockClient(
          (_) async => http.Response(
            "var newImgs=['https://images.cdndm5.com/1.jpg'];",
            200,
          ),
        ),
      );
      addTearDown(() {
        source.close();
        OfflineLibrary.instance?.source.close();
        OfflineLibrary.instance = null;
      });
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderPage(
            comic: library.samples.first,
            chapter: const Chapter('/one/', 'One'),
            chapters: const [Chapter('/one/', 'One')],
            library: library,
            source: source,
            web: false,
          ),
        ),
      );
      await settleFirstFrame(tester);
      final viewport = tester.getRect(find.byType(PageView).first);
      await tester.tap(find.byTooltip(translate('章节与书签', const Locale('en'))));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(PageView).first), viewport);
      expect(tester.getRect(find.byType(TextField)).bottom, lessThan(544));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'chapter end records completion and cross-chapter undo restores the exact page',
    (tester) async {
      late Library library;
      await tester.runAsync(() async {
        library = await fixtures.library();
        await library.setOption('warmNextChapter', false);
        await cacheReaderImages(library);
      });
      final source = Dm5Source(
        client: MockClient(
          (_) async => http.Response(
            "var newImgs=['https://images.cdndm5.com/1.jpg','https://images.cdndm5.com/2.jpg'];",
            200,
          ),
        ),
      );
      addTearDown(() {
        source.close();
        OfflineLibrary.instance?.source.close();
        OfflineLibrary.instance = null;
      });
      final comic = library.samples.first;
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderPage(
            comic: comic,
            chapter: const Chapter('/one/', 'One'),
            chapters: const [Chapter('/one/', 'One'), Chapter('/two/', 'Two')],
            initialPage: 1,
            library: library,
            source: source,
            web: false,
          ),
        ),
      );
      await settleFirstFrame(tester);
      String label(String key) => translate(key, const Locale('en'));
      await tester.tap(find.text(label('本章读完')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label('读完并继续下一章')));
      await settleFirstFrame(tester);
      expect(library.chapterRead(comic, '/one/'), true);
      expect(library.record(comic)!.chapterPath, '/two/');
      await tester.tap(find.text(label('返回上一章')));
      await settleFirstFrame(tester);
      expect(library.record(comic)!.chapterPath, '/one/');
      expect(library.record(comic)!.page, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'one-hand preset moves chrome down without changing the reading viewport',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late Library library;
      await tester.runAsync(() async {
        library = await fixtures.library();
        await cacheReaderImages(library);
      });
      final source = Dm5Source(
        client: MockClient(
          (_) async => http.Response(
            "var newImgs=['https://images.cdndm5.com/1.jpg','https://images.cdndm5.com/2.jpg'];",
            200,
          ),
        ),
      );
      addTearDown(() {
        source.close();
        OfflineLibrary.instance?.source.close();
        OfflineLibrary.instance = null;
      });
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderPage(
            comic: library.samples.first,
            chapter: const Chapter('/one/', 'One'),
            library: library,
            source: source,
            web: false,
          ),
        ),
      );
      await settleFirstFrame(tester);
      final viewport = tester.getRect(find.byType(PageView).first);
      await tester.tap(find.byTooltip(translate('阅读设置', const Locale('en'))));
      await tester.pumpAndSettle();
      final selector = find.byWidgetPredicate(
        (w) => w is DropdownButtonFormField<String> && w.initialValue == 'auto',
      );
      tester.widget<DropdownButtonFormField<String>>(selector).onChanged!(
        'left',
      );
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(ReaderPage))).pop();
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(PageView).first), viewport);
      expect(
        tester
            .getCenter(find.byTooltip(translate('返回目录', const Locale('en'))))
            .dy,
        greaterThan(422),
      );
      expect(library.record(library.samples.first)!.page, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
