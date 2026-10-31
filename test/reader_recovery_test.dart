import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/dm5_source.dart';
import 'package:manxia/data/library.dart';
import 'package:manxia/data/offline_library.dart';
import 'package:manxia/ui/reader_page.dart';
import 'package:manxia/ui/reader_surfaces.dart';
import 'package:manxia/ui/localized_text.dart';
import 'features_test.dart' as fixtures;
import 'reader_test.dart' show cacheReaderImages, settleFirstFrame;

class _Refreshing extends Dm5Source {
  int calls = 0;
  bool reordered = false;
  @override
  Future<List<String>> networkPages(String path) async {
    calls++;
    final pages = [
      'https://images.cdndm5.com/1.jpg?token=${calls == 1 ? 'old' : 'fresh'}',
      'https://images.cdndm5.com/2.jpg?token=${calls == 1 ? 'old' : 'fresh'}',
    ];
    return reordered ? pages.reversed.toList() : pages;
  }
}

class _Warming extends Dm5Source {
  final calls = <String>[];
  @override
  Future<List<String>> networkPages(String path) async {
    calls.add(path);
    return ['https://images.cdndm5.com/${path == '/one/' ? 1 : 2}.jpg'];
  }
}

void main() {
  testWidgets(
    'reader expiry refresh keeps its page and bounds automatic retries',
    (tester) async {
      late Library library;
      await tester.runAsync(() async {
        library = await fixtures.library();
        await cacheReaderImages(library);
        for (final token in ['old', 'fresh']) {
          for (var i = 1; i <= 2; i++) {
            OfflineLibrary.instance!.entries.add({
              'comic': {
                'cover': 'https://images.cdndm5.com/$i.jpg?token=$token',
              },
              'coverKey': 'reader-frame-$i',
            });
          }
        }
      });
      final source = _Refreshing();
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
            initialPage: 1,
            library: library,
            source: source,
            web: false,
          ),
        ),
      );
      await settleFirstFrame(tester);
      tester.widget<PagedSurface>(find.byType(PagedSurface).last).onImageError!(
        0,
        NetworkImageLoadException(
          statusCode: 403,
          uri: Uri.parse('https://images.cdndm5.com/2.jpg?token=old'),
        ),
      );
      await settleFirstFrame(tester);
      expect(source.calls, 2);
      expect(library.record(library.samples.first)!.page, 1);
      final refreshed = tester.widget<PagedSurface>(
        find.byType(PagedSurface).last,
      );
      refreshed.onImageError!(
        1,
        NetworkImageLoadException(
          statusCode: 403,
          uri: Uri.parse('https://images.cdndm5.com/2.jpg?token=fresh'),
        ),
      );
      await tester.pumpAndSettle();
      expect(source.calls, 2);
      refreshed.onRetryPage!(1);
      await settleFirstFrame(tester);
      expect(source.calls, 3);
      expect(library.record(library.samples.first)!.page, 1);
      source.reordered = true;
      tester.widget<PagedSurface>(find.byType(PagedSurface).last).onRetryPage!(
        1,
      );
      await tester.pumpAndSettle();
      expect(library.record(library.samples.first)!.page, 1);
      await tester.tap(find.text(translate('从本章开头重新加载', const Locale('en'))));
      await settleFirstFrame(tester);
      expect(source.calls, 5);
      expect(library.record(library.samples.first)!.page, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'next chapter preparation never moves progress and is reused on navigation',
    (tester) async {
      late Library library;
      await tester.runAsync(() async {
        library = await fixtures.library();
        await cacheReaderImages(library);
      });
      final source = _Warming();
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
            chapters: const [Chapter('/one/', 'One'), Chapter('/two/', 'Two')],
            library: library,
            source: source,
            web: false,
          ),
        ),
      );
      await settleFirstFrame(tester);
      expect(source.calls, ['/one/', '/two/']);
      expect(library.record(library.samples.first)!.chapterPath, '/one/');
      await tester.tap(find.text(translate('下一章', const Locale('en'))));
      await settleFirstFrame(tester);
      expect(source.calls, ['/one/', '/two/']);
      expect(library.record(library.samples.first)!.chapterPath, '/two/');
      await tester.pumpWidget(const SizedBox());
    },
  );
}
