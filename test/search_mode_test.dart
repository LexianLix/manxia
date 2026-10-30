import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/dm5_source.dart';
import 'package:manxia/data/library.dart';
import 'package:manxia/ui/search_page.dart';
import 'package:manxia/ui/app_shell.dart';
import 'features_test.dart' as fixtures;

class _SearchSource extends Dm5Source {
  final pending = Completer<List<Comic>>();
  @override
  Future<List<Comic>> search(String query) => pending.future;
  @override
  Future<String> fetchPage(String path, {bool desktop = false}) async =>
      '<ul><li><div class="book-list-cover"><a title="Author result" href="/manhua-author/"><img src="https://images.cdndm5.com/cover.jpg"></a></div></li></ul>';
}

void main() {
  testWidgets(
    'switching to author search rejects the older title-search reply',
    (tester) async {
      late Library library;
      await tester.runAsync(() async {
        library = await fixtures.library();
      });
      final source = _SearchSource();
      addTearDown(source.close);
      await tester.pumpWidget(
        MaterialApp(
          home: ComicSearchPage(
            library: library,
            source: source,
            web: false,
            onOpen: (_) {},
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Test');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Author'));
      await tester.pumpAndSettle();
      source.pending.complete([
        const Comic(path: '/manhua-stale/', title: 'Stale', cover: ''),
      ]);
      await tester.pumpAndSettle();
      expect(
        tester.widget<ComicGrid>(find.byType(ComicGrid)).books.single.path,
        '/manhua-author/',
      );
      expect(find.text('Stale'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
