import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:manxia/data/library.dart';
import 'package:manxia/data/comic.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'real collection replaces sample shelf and survives a fresh library instance',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final library = Library(prefs);
      await library.load();
      expect(library.demo, true);
      expect(library.books, isNotEmpty);
      final comic = library.samples.first;
      await library.toggle(comic);
      expect(library.demo, false);
      expect(library.books.map((b) => b.path), [comic.path]);
      await library.save(
        ReadingRecord(
          comic: comic,
          chapterPath: '/m1/',
          chapterTitle: '第1话',
          page: 4,
          total: 15,
          updatedAt: 1,
        ),
      );
      final restored = Library(prefs);
      await restored.load();
      expect(restored.books.single.path, comic.path);
      expect(restored.record(comic)!.page, 4);
      await restored.toggle(comic);
      expect(restored.books, isEmpty);
    },
  );
  test('broken local records do not prevent the app opening', () async {
    SharedPreferences.setMockInitialValues({
      'favorites': '{bad',
      'history': '{bad',
    });
    final library = Library(await SharedPreferences.getInstance());
    await library.load();
    expect(library.history, isEmpty);
    expect(library.favorites, isEmpty);
  });
}
