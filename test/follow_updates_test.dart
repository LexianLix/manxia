import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/dm5_source.dart';
import 'package:manxia/data/discovery.dart';
import 'package:manxia/data/library.dart';
import 'package:manxia/ui/discovery_page.dart';
import 'package:manxia/ui/localized_text.dart';
import 'discovery_page_test.dart' as fixtures;

class _FollowSource extends Dm5Source {
  _FollowSource(this.snapshot);
  final Discovery snapshot;
  bool failing = true;
  final calls = <String>[];
  @override
  Future<Discovery> discover() async => snapshot;
  @override
  Future<ComicDetail> detail(Comic book) async {
    calls.add(book.path);
    if (failing && book.path == snapshot.books[1].path) {
      throw SourceException('offline');
    }
    return ComicDetail(book, const [Chapter('/new-chapter/', 'New')]);
  }
}

void main() {
  testWidgets(
    'follow updates retain unread state, support batch read and retry only failed books',
    (tester) async {
      late Library library;
      late Discovery snapshot;
      await tester.runAsync(() async {
        library = await fixtures.library();
        snapshot = await fixtures.snapshot();
        for (final book in snapshot.books.take(2)) {
          await library.toggle(book);
        }
        library.updates[snapshot.books.first.path] = {
          'fingerprint': '/old/',
          'changed': false,
        };
      });
      final source = _FollowSource(snapshot);
      addTearDown(source.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DiscoveryPage(
                library: library,
                source: source,
                web: false,
                onOpen: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pumpAndSettle();
      String label(String text) => translate(text, const Locale('en'));
      await tester.tap(find.text(label('更新')));
      await tester.pumpAndSettle();
      final check = find.text(label('检查更新'));
      await tester.ensureVisible(check);
      await tester.tap(check);
      await tester.pumpAndSettle();
      expect(library.updates[snapshot.books.first.path]!['changed'], true);
      expect(
        library.updates[snapshot.books[1].path]!['checkError'],
        contains('offline'),
      );
      await tester.ensureVisible(find.text(label('全部标为已读')));
      await tester.tap(find.text(label('全部标为已读')));
      await tester.pumpAndSettle();
      expect(library.updates[snapshot.books.first.path]!['changed'], false);
      source.failing = false;
      await tester.ensureVisible(find.text(label('重试检查失败')));
      await tester.tap(find.text(label('重试检查失败')));
      await tester.pumpAndSettle();
      expect(
        source.calls.where((p) => p == snapshot.books.first.path),
        hasLength(1),
      );
      expect(
        source.calls.where((p) => p == snapshot.books[1].path),
        hasLength(2),
      );
      expect(library.updates[snapshot.books[1].path]!['checkError'], isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
