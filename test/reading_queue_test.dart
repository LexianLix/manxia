import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/dm5_source.dart';
import 'package:manxia/data/library.dart';
import 'package:manxia/data/offline_library.dart';
import 'package:manxia/data/reading_progress.dart';
import 'package:manxia/ui/discovery_preferences_page.dart';
import 'package:manxia/ui/localized_text.dart';
import 'package:manxia/ui/reader_page.dart';
import 'package:manxia/ui/reading_queue_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'features_test.dart' as fixtures;
import 'reader_test.dart' show cacheReaderImages, settleFirstFrame;

const first = Comic(path: '/one/', title: 'First book', cover: '');
const second = Comic(path: '/two/', title: 'Second book', cover: '');
const firstChapter = Chapter('/one/1/', 'First chapter');
const secondChapter = Chapter('/two/1/', 'Second chapter');

class _QueuedSource extends Dm5Source {
  bool available = true;

  @override
  Future<ComicDetail> detail(Comic comic) async {
    if (!available) throw SourceException('Queue test unavailable');
    return ComicDetail(comic, [secondChapter]);
  }

  @override
  Future<List<String>> pages(String path) async => [
    'https://images.cdndm5.com/1.jpg',
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'queue order persists and an older backup cannot restore removals',
    () async {
      final library = await fixtures.library();
      addTearDown(library.dispose);
      await library.setQueued(first, true);
      await library.setQueued(second, true);
      await library.setQueued(first, true);
      expect(library.readingQueue.books.map((book) => book.title), [
        first.title,
        second.title,
      ]);
      final backup = library.backup();
      await library.moveQueued(second, 0);
      expect(library.readingQueue.nextAfter(second), first);
      final loaded = Library(await SharedPreferences.getInstance());
      addTearDown(loaded.dispose);
      await loaded.load();
      expect(loaded.readingQueue.books.map((book) => book.path), [
        second.path,
        first.path,
      ]);
      await loaded.setQueued(first, false);
      await loaded.restore(backup);
      expect(loaded.readingQueue.books.single.path, second.path);
      expect(loaded.readingQueue.nextAfter(second), isNull);
      final restored = Library(library.prefs);
      addTearDown(restored.dispose);
      await restored.restore(backup);
      expect(restored.readingQueue.books.map((book) => book.title), [
        first.title,
        second.title,
      ]);
    },
  );

  testWidgets('Discover action adds its book and the queue menu reorders it', (
    tester,
  ) async {
    final library = (await tester.runAsync(fixtures.library))!;
    addTearDown(library.dispose);
    await library.setQueued(second, true);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showDiscoveryInterest(context, library, first),
                child: const Text('Actions'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to Up next'));
    await tester.pumpAndSettle();
    expect(library.readingQueue.books.length, 2);
    Comic? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: ReadingQueuePage(
          library: library,
          web: false,
          onOpen: (book) => opened = book,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_horiz).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move up'));
    await tester.pumpAndSettle();
    expect(library.readingQueue.books.first.path, first.path);
    await tester.tap(find.widgetWithText(ListTile, first.title));
    expect(opened?.path, first.path);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'reader keeps the queue on failure, then replaces itself with the next book',
    (tester) async {
      late Library library;
      await tester.runAsync(() async {
        library = await fixtures.library();
        await cacheReaderImages(library);
        await library.setQueued(first, true);
        await library.setQueued(second, true);
      });
      final source = _QueuedSource()..available = false;
      addTearDown(() {
        source.close();
        library.dispose();
        OfflineLibrary.instance?.source.close();
        OfflineLibrary.instance = null;
      });
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderPage(
            comic: first,
            chapter: firstChapter,
            chapters: const [firstChapter],
            library: library,
            source: source,
            web: false,
          ),
        ),
      );
      await settleFirstFrame(tester);
      Future<void> tapNextBook() async {
        await tester.tap(find.text(translate('本章读完', const Locale('en'))));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Finish and read the next book'));
        await tester.pumpAndSettle();
      }

      await tapNextBook();
      expect(library.readingQueue.books.length, 2);
      expect(
        tester.widget<ReaderPage>(find.byType(ReaderPage)).comic.path,
        first.path,
      );
      source.available = true;
      await tapNextBook();
      await settleFirstFrame(tester);
      expect(library.readingQueue.books.single.path, second.path);
      expect(library.chapterRead(first, firstChapter.path), isTrue);
      expect(
        tester.widget<ReaderPage>(find.byType(ReaderPage)).comic.path,
        second.path,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
