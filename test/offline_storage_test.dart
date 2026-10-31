import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/dm5_source.dart';
import 'package:manxia/data/offline_library.dart';
import 'package:manxia/data/reading_progress.dart';
import 'package:manxia/platform/blob_store.dart';
import 'package:manxia/ui/localized_text.dart';
import 'package:manxia/ui/offline_storage_page.dart';
import 'features_test.dart' as fixtures;

void main() {
  testWidgets(
    'read-only cleanup previews exact chapters, cancellation keeps bytes and confirmation preserves reading data',
    (tester) async {
      final library = await fixtures.library();
      await library.toggle(fixtures.comic);
      await library.save(fixtures.record(1, 10));
      await library.addBookmark(fixtures.record(1, 10), note: 'Keep');
      final source = Dm5Source(), store = MemoryBlobStore();
      final offline = OfflineLibrary(library, source, store: store);
      await offline.initialize();
      addTearDown(() {
        source.close();
        OfflineLibrary.instance = null;
        Dm5Source.offlinePages = null;
        Dm5Source.offlineDetail = null;
      });
      for (final id in ['one', 'two']) {
        await store.write(id, Uint8List.fromList([1, 2, 3]));
        offline.entries.add({
          'id': id,
          'comic': fixtures.comic.toJson(),
          'chapter': Chapter('/$id/', id).toJson(),
          'status': 'complete',
          'keys': [id],
          'bytes': 3,
          'total': 1,
          'done': 1,
        });
      }
      await library.setChapterRead(fixtures.comic, '/one/', true);
      await tester.pumpWidget(
        MaterialApp(
          home: OfflineStoragePage(
            library: library,
            offline: offline,
            comic: fixtures.comic,
          ),
        ),
      );
      await tester.pumpAndSettle();
      String label(String key, [Map<String, Object> arguments = const {}]) =>
          translate(key, const Locale('en'), arguments: arguments);
      await tester.tap(find.text(label('已读')));
      await tester.pumpAndSettle();
      expect(find.text('one'), findsOneWidget);
      expect(find.text('two'), findsNothing);
      await tester.tap(find.text(label('选择当前筛选')));
      await tester.pumpAndSettle();
      final clean = find.text(label('清理选中章节（{count}）', {'count': 1}));
      await tester.tap(clean);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(await store.read('one'), isNotNull);
      await tester.tap(find.text(label('取消')));
      await tester.pumpAndSettle();
      expect(offline.entries, hasLength(2));
      await tester.tap(clean);
      await tester.pumpAndSettle();
      await tester.tap(find.text(label('清理')));
      await tester.pumpAndSettle();
      expect(await store.read('one'), isNull);
      expect(await store.read('two'), isNotNull);
      expect(library.favorites, hasLength(1));
      expect(library.history.single.page, 1);
      expect(library.bookmarks.single['note'], 'Keep');
      expect(library.chapterRead(fixtures.comic, '/one/'), true);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
