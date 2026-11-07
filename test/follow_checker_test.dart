import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/dm5_source.dart';
import 'package:manxia/data/follow_updates.dart';
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
    'updates continue at the oldest unread addition and read marks can be undone',
    () async {
      final library = await fixtures.library();
      await library.toggle(fixtures.comic);
      await library.recordFollow(
        ComicDetail(fixtures.comic, const [Chapter('/one/', 'One')]),
      );
      final current = ComicDetail(fixtures.comic, const [
        Chapter('/three/', 'Three'),
        Chapter('/two/', 'Two'),
        Chapter('/one/', 'One'),
      ]);
      await library.recordFollow(current);
      expect(
        library.unreadFollowChapters(current).map((chapter) => chapter.path),
        ['/two/', '/three/'],
      );
      await library.setChapterRead(fixtures.comic, '/two/', true);
      expect(library.updates[fixtures.comic.path]!['changed'], true);
      await library.setChapterRead(fixtures.comic, '/three/', true);
      expect(library.updates[fixtures.comic.path]!['changed'], false);
      await library.setChapterRead(fixtures.comic, '/two/', false);
      expect(library.updates[fixtures.comic.path]!['changed'], true);
      expect(library.unreadFollowChapters(current).single.path, '/two/');
      await library.markUpdatesRead([fixtures.comic.path]);
      await library.recordFollow(current);
      expect(library.updates[fixtures.comic.path]!['changed'], false);
      expect(library.unreadFollowChapters(current), isEmpty);
    },
  );
  test(
    'baseline has no fake updates; new chapters retain a direct unread flag',
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
      expect(library.updates[fixtures.comic.path]!['changed'], false);
      await library.recordFollow(next, at: DateTime(2026, 10, 31, 20));
      expect(library.updates[fixtures.comic.path]!['changed'], true);
      expect(library.updates[fixtures.comic.path]!['latest'], 'Three');
      expect(library.meta(fixtures.comic).containsKey('followEvents'), false);
      await library.recordFollow(next, at: DateTime(2026, 11, 1));
      await library.recordFollow(first);
      expect(library.updates[fixtures.comic.path]!['changed'], true);
      await library.recordFollow(next);
      expect(library.updates[fixtures.comic.path]!['changed'], true);
      await library.markUpdatesRead([fixtures.comic.path]);
      expect(library.updates[fixtures.comic.path]!['changed'], false);
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
      expect(library.updates[fixtures.comic.path]!['changed'], true);
      await library.markUpdatesRead([fixtures.comic.path]);
      await library.recordFollow(
        ComicDetail(fixtures.comic, const [
          Chapter('/x/', 'X'),
          Chapter('/y/', 'Y'),
        ]),
      );
      expect(library.updates[fixtures.comic.path]!['changed'], false);
    },
  );

  test(
    'direct update state reloads and old metadata remains compatible with backup',
    () async {
      final library = await fixtures.library();
      await library.toggle(fixtures.comic);
      library.updates[fixtures.comic.path] = {
        'fingerprint': '/old/',
        'changed': false,
      };
      await library.setMeta(fixtures.comic, {
        'followEvents': [
          {'id': 'legacy', 'observedAt': 1, 'chapters': []},
        ],
      });
      await library.recordFollow(
        ComicDetail(fixtures.comic, const [Chapter('/new/', 'New')]),
      );
      await library.setMeta(fixtures.comic, {'followPinned': true});
      final reloaded = Library(library.prefs);
      await reloaded.load();
      expect(reloaded.updates[fixtures.comic.path]!['changed'], true);
      final backup = library.backup();
      final restored = await fixtures.library();
      await restored.restore(backup);
      expect(restored.meta(fixtures.comic)['followEvents'][0]['id'], 'legacy');
      expect(restored.meta(fixtures.comic)['followPinned'], true);
      await restored.toggle(fixtures.comic);
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
      expect(library.updates[fixtures.comic.path]!['changed'], false);
      await FollowChecker.check(library, source, onlyDue: true);
      expect(
        source.calls,
        1,
        reason: 'Repeated foreground checks must not refetch a recent catalog',
      );
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
