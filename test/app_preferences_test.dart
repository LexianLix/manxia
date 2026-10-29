import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:manxia/main.dart';
import 'package:manxia/data/library.dart';
import 'package:manxia/data/comic.dart';

void main() {
  testWidgets(
    'saving reading progress preserves app configuration while preferences still apply',
    (tester) async {
      late Library library;
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        library = Library(await SharedPreferences.getInstance());
        await library.load();
      });
      await tester.pumpWidget(ManxiaApp(library: library));
      await tester.pumpAndSettle();
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      await library.save(
        const ReadingRecord(
          comic: Comic(path: '/test/', title: 'Test', cover: ''),
          chapterPath: '/c/',
          chapterTitle: 'Chapter',
          page: 2,
          total: 10,
          updatedAt: 1,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<MaterialApp>(find.byType(MaterialApp)), same(app));
      expect(library.history.single.page, 2);
      await library.setting('dark', true);
      await tester.pumpAndSettle();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
      await library.setOption('language', 'en');
      await tester.pumpAndSettle();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
        const Locale('en'),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
