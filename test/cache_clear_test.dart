import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:manxia/data/dm5_source.dart';
import 'package:manxia/ui/advanced_settings.dart';
import 'features_test.dart' as fixtures;

void main() {
  testWidgets(
    'temporary cache clearing requires confirmation and retains library data',
    (tester) async {
      final library = await fixtures.library();
      await library.toggle(fixtures.comic);
      await library.save(fixtures.record(3, 10));
      final offline = jsonEncode([
        {'id': 'retained', 'status': 'complete'},
      ]);
      await library.prefs.setString('offline.v1', offline);
      final source = Dm5Source();
      addTearDown(source.close);
      final calls = <String>[];
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: AdvancedSettings(
                    library: library,
                    source: source,
                    web: true,
                    section: 'storage',
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final clear = find.text('Clear temporary image cache');
          await tester.ensureVisible(clear);
          await tester.tap(clear);
          await tester.pumpAndSettle();
          expect(calls, isEmpty);
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          expect(calls, isEmpty);
          await tester.tap(clear);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Clear'));
          await tester.pumpAndSettle();
          expect(calls, ['GET', 'POST']);
          expect(library.favorites.single.path, fixtures.comic.path);
          expect(library.record(fixtures.comic)!.page, 3);
          expect(library.prefs.getString('offline.v1'), offline);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
        () => MockClient((request) async {
          expect(request.url.path, '/api/cache');
          calls.add(request.method);
          return http.Response('{"bytes":1048576}', 200);
        }),
      );
    },
  );
}
