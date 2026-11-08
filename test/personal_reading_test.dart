import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/library.dart';
import 'package:manxia/data/reading_journal.dart';
import 'package:manxia/data/personal_review.dart';
import 'features_test.dart' as fixtures;

ReadingRecord point(int page, int at, {String chapter = '/chapter/'}) =>
    ReadingRecord(
      comic: fixtures.comic,
      chapterPath: chapter,
      chapterTitle: chapter,
      page: page,
      total: 100,
      updatedAt: at,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'ratings and short reviews survive reload, backup merge and clearing',
    () async {
      final library = await fixtures.library();
      await library.setReview(fixtures.comic, 4, '  好看，值得再读。  ');
      final reloaded = Library(library.prefs);
      await reloaded.load();
      expect(reloaded.rating(fixtures.comic), 4);
      expect(reloaded.reviewText(fixtures.comic), '好看，值得再读。');
      final backup = library.backup();
      final another = await fixtures.library();
      await another.restore(backup);
      expect(another.rating(fixtures.comic), 4);
      await another.setReview(fixtures.comic, null, '');
      expect(another.rating(fixtures.comic), isNull);
      expect(another.reviewText(fixtures.comic), isEmpty);
      expect(
        () => another.setReview(fixtures.comic, 6, ''),
        throwsArgumentError,
      );
      expect(
        () => another.setReview(fixtures.comic, 1, 'x' * 501),
        throwsArgumentError,
      );
    },
  );
  test(
    'review length matches the editor for emoji and joined characters',
    () async {
      final library = await fixtures.library();
      final text = '👩‍🚀' * 500;
      await library.setReview(fixtures.comic, 5, text);
      expect(library.reviewText(fixtures.comic), text);
      expect(
        () => library.setReview(fixtures.comic, 5, '$text好'),
        throwsArgumentError,
      );
    },
  );
  test(
    'a chapter or distant jump retains origin and destination after reload',
    () async {
      final library = await fixtures.library();
      await library.save(point(3, 100));
      await library.save(point(4, 200));
      await library.save(point(50, 300));
      await library.save(point(2, 400, chapter: '/next/'));
      final reloaded = Library(library.prefs);
      await reloaded.load();
      expect(
        reloaded.journal
            .forComic(fixtures.comic)
            .map((p) => (p.chapterPath, p.page)),
        containsAll([('/chapter/', 4), ('/chapter/', 50), ('/next/', 2)]),
      );
      final backup = library.backup();
      await reloaded.removeHistory(fixtures.comic);
      await reloaded.restore(backup);
      expect(reloaded.journal.forComic(fixtures.comic), isEmpty);
    },
  );
  test(
    'recoverable positions retain newest duplicate and only twenty per book',
    () {
      final journal = ReadingJournal();
      for (var i = 0; i < 30; i++) {
        journal.remember(point(i, i + 1), force: true);
      }
      journal.remember(point(29, 1), force: true);
      expect(journal.forComic(fixtures.comic), hasLength(20));
      expect(journal.forComic(fixtures.comic).first.updatedAt, 30);
      expect(journal.forComic(fixtures.comic).last.page, 10);
    },
  );
  test(
    'reimported statistics are idempotent; device counters add and pages deduplicate',
    () async {
      final library = await fixtures.library();
      library.journal.device = 'a';
      library.journal.add(
        point(3, 100),
        4000,
        DateTime(2026, 11, 8),
        seen: true,
      );
      final remote = ReadingJournal()..device = 'b';
      remote.add(point(3, 100), 6000, DateTime(2026, 11, 8), seen: true);
      library.journal.merge(remote.toJson(), {});
      final backup = library.backup();
      await library.restore(backup);
      await library.restore(backup);
      final totals = ReadingTotals(library.journal);
      expect(totals.milliseconds, 10000);
      expect(totals.pages, 1);
      library.journal.clearStatistics(200);
      library.journal.merge(backup['journal'], {});
      expect(ReadingTotals(library.journal).milliseconds, 0);
    },
  );
  test(
    'monotonic reading time excludes loading, background, covered routes and prolonged idle',
    () {
      var time = 0;
      final journal = ReadingJournal();
      final clock = ReadingClock(
        elapsed: () => time,
        now: () => DateTime(2026, 11, 8).add(Duration(milliseconds: time)),
        onSlice: (r, ms, at, seen) => journal.add(r, ms, at, seen: seen),
      );
      clock.update(null, active: false);
      time = 10000;
      clock.update(point(3, time), active: true);
      time = 15000;
      clock.update(point(3, time), active: false);
      time = 65000;
      clock.update(point(3, time), active: true);
      time = 265000;
      clock.update(point(3, time), active: true);
      expect(ReadingTotals(journal).milliseconds, 95000);
      expect(ReadingTotals(journal).pages, 1);
      clock.update(point(4, time), active: true, interaction: true);
      time += 1000;
      clock.update(null, active: false);
      expect(
        ReadingTotals(journal).pages,
        1,
        reason: 'a one-second page visit is not a read page',
      );
      expect(ReadingTotals(journal).milliseconds, 96000);
    },
  );
  test('reading time is split at local midnight', () {
    var time = 0;
    final journal = ReadingJournal();
    final start = DateTime(2026, 11, 7, 23, 59, 59);
    final clock = ReadingClock(
      elapsed: () => time,
      now: () => start.add(Duration(milliseconds: time)),
      onSlice: (r, ms, at, seen) => journal.add(r, ms, at, seen: seen),
    );
    clock.update(point(0, 0), active: true);
    time = 2000;
    clock.update(point(0, 2000), active: false);
    expect(ReadingTotals(journal).byDay, {
      '2026-11-07': 1000,
      '2026-11-08': 1000,
    });
  });
  test('a decoded spread counts both pages without doubling reading time', () {
    final journal = ReadingJournal();
    journal.add(
      point(1, 100),
      5000,
      DateTime(2026, 11, 8),
      seen: true,
      visiblePages: 2,
    );
    journal.add(
      point(1, 200),
      3000,
      DateTime(2026, 11, 8),
      seen: true,
      visiblePages: 2,
    );
    final totals = ReadingTotals(journal);
    expect(totals.pages, 2);
    expect(totals.milliseconds, 8000);
  });
}
