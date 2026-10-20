import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/dm5_source.dart';
import 'package:manxia/data/library.dart';
import 'package:manxia/ui/reader_page.dart';

void main() {
  testWidgets('loaded chapter enables page controls and saves current page', (
    tester,
  ) async {
    late Library library;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      library = Library(await SharedPreferences.getInstance());
      await library.load();
    });
    final comic = library.samples.first;
    final source = Dm5Source(
      client: MockClient(
        (_) async => http.Response(
          "var newImgs=['https://images.cdndm5.com/1.jpg','https://images.cdndm5.com/2.jpg'];",
          200,
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPage(
          comic: comic,
          chapter: const Chapter('/m1/', '第1话'),
          library: library,
          source: source,
          web: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget);
    await tester.tap(find.byTooltip('下一页'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    expect(library.record(comic)!.page, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();
    expect(tester.takeException(), isNull);
    source.close();
  });
}
