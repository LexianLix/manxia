import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/library.dart';
import 'package:manxia/data/reading_progress.dart';
import 'features_test.dart' as fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'chapter completion, optional archive and backup retain the personal library',
    () async {
      final library = await fixtures.library();
      await library.toggle(fixtures.comic);
      await library.save(fixtures.record(2, 10));
      await library.rememberChapters(fixtures.comic, const [
        Chapter('/a/', 'A'),
        Chapter('/b/', 'B'),
      ]);
      await library.setChapterRead(fixtures.comic, '/a/', true);
      await library.setChapterRead(fixtures.comic, '/b/', true);
      expect(library.readChapterCount(fixtures.comic), 2);
      expect(library.archived(fixtures.comic), false);
      await library.setOption('autoArchiveRead', true);
      await library.setChapterRead(fixtures.comic, '/b/', true);
      expect(library.archived(fixtures.comic), true);
      await library.rememberChapters(fixtures.comic, const [
        Chapter('/a/', 'A'),
        Chapter('/b/', 'B'),
        Chapter('/c/', 'C'),
      ]);
      expect(library.archived(fixtures.comic), false);
      expect(library.readChapterCount(fixtures.comic), 2);
      expect(library.favorites, hasLength(1));
      expect(library.record(fixtures.comic)!.page, 2);
      final backup = library.backup();
      final restored = Library(library.prefs)..loadFeatures();
      expect(restored.chapterRead(fixtures.comic, '/a/'), true);
      expect(
        (backup['metadata'] as Map)[fixtures.comic.path]['readChapters']['/b/'],
        true,
      );
      await library.setChapterRead(fixtures.comic, '/a/', false);
      expect(library.archived(fixtures.comic), false);
    },
  );
}
