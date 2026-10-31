import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/dm5_source.dart';
import 'package:manxia/data/follow_calendar.dart';
import 'package:manxia/data/library.dart';
import 'package:manxia/data/reading_progress.dart';
import 'features_test.dart' as fixtures;

class _Source extends Dm5Source {
  bool failing = false;
  int calls = 0;
  @override
  Future<ComicDetail> detail(Comic comic) async {
    calls++;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (failing) throw SourceException('offline');
    return ComicDetail(comic, const [
      Chapter('/two/', 'Two'),
      Chapter('/one/', 'One'),
    ]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'baseline has no fake updates; new chapters retain observation date and deduplicate',
    () async {
      final library = await fixtures.library();
      await library.toggle(fixtures.comic);
      final first = ComicDetail(fixtures.comic, const [
        Chapter('/one/', 'One'),
      ]);
      final next = ComicDetail(fixtures.comic, const [
        Chapter('/three/', 'Three'),
        Chapter('/two/', 'Two'),
        Chapter('/one/', 'One'),
      ]);
      await library.recordFollow(first, at: DateTime(2026, 10, 29));
      expect(library.followEvents, isEmpty);
      await library.recordFollow(next, at: DateTime(2026, 10, 31, 20));
      expect(library.followEvents, hasLength(1));
      final event = library.followEvents.single;
      expect(event.observedAt, DateTime(2026, 10, 31, 20));
      expect(event.chapters.map((c) => c.path), ['/three/', '/two/']);
      expect(event.value.containsKey('publishedAt'), false);
      await library.recordFollow(next, at: DateTime(2026, 11, 1));
      await library.recordFollow(first);
      await library.recordFollow(next);
      expect(library.followEvents, hasLength(1));
      expect(library.eventUnread(event), true);
      await library.markEventRead(event, true);
      expect(library.eventUnread(event), false);
      await library.markEventRead(event, false);
      expect(library.chapterRead(fixtures.comic, '/two/'), false);
    },
  );

  test(
    'middle catalog additions are found and full catalog replacement is not invented as new content',
    () async {
      final library = await fixtures.library();
      await library.toggle(fixtures.comic);
      await library.recordFollow(
        ComicDetail(fixtures.comic, const [
          Chapter('/2/', '2'),
          Chapter('/1/', '1'),
        ]),
      );
      await library.recordFollow(
        ComicDetail(fixtures.comic, const [
          Chapter('/2/', '2'),
          Chapter('/extra/', 'Extra'),
          Chapter('/1/', '1'),
        ]),
      );
      expect(library.followEvents.single.chapters.single.path, '/extra/');
      await library.recordFollow(
        ComicDetail(fixtures.comic, const [
          Chapter('/x/', 'X'),
          Chapter('/y/', 'Y'),
        ]),
      );
      expect(library.followEvents, hasLength(1));
    },
  );

  test(
    'legacy update state migrates; journal and focus survive reload and backup',
    () async {
      final library = await fixtures.library();
      await library.toggle(fixtures.comic);
      library.updates[fixtures.comic.path] = {
        'fingerprint': '/old/',
        'changed': false,
      };
      await library.recordFollow(
        ComicDetail(fixtures.comic, const [Chapter('/new/', 'New')]),
      );
      await library.setMeta(fixtures.comic, {'followPinned': true});
      final reloaded = Library(library.prefs);
      await reloaded.load();
      expect(reloaded.followEvents, hasLength(1));
      final backup = library.backup();
      final restored = await fixtures.library();
      await restored.restore(backup);
      expect(restored.followEvents.single.chapters.single.path, '/new/');
      expect(restored.meta(fixtures.comic)['followPinned'], true);
      await restored.toggle(fixtures.comic);
      expect(restored.followEvents, isEmpty);
      expect(
        restored.metadata[fixtures.comic.path]!['followEvents'],
        isNotEmpty,
      );
    },
  );

  test(
    'overlapping checks share work and failures preserve records and baseline',
    () async {
      final library = await fixtures.library();
      await library.toggle(fixtures.comic);
      final source = _Source();
      addTearDown(source.close);
      await Future.wait([
        FollowChecker.check(library, source),
        FollowChecker.check(library, source),
      ]);
      expect(source.calls, 1);
      expect(library.followEvents, isEmpty);
      final prior = library.updates[fixtures.comic.path]!['fingerprint'];
      source.failing = true;
      expect(await FollowChecker.check(library, source), 1);
      expect(library.updates[fixtures.comic.path]!['fingerprint'], prior);
      expect(library.updates[fixtures.comic.path]!['checkError'], 'offline');
      source.failing = false;
      await FollowChecker.check(library, source, failedOnly: true);
      expect(library.updates[fixtures.comic.path]!['checkError'], isNull);
    },
  );
}
