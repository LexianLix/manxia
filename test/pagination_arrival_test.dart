import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/dm5_source.dart';
import 'package:manxia/data/library.dart';
import 'package:manxia/data/source_catalog.dart';
import 'package:manxia/ui/book_link.dart';
import 'package:manxia/ui/source_browser.dart';

const first = Comic(path: '/first/', title: 'First', cover: 'offline:first');
const second = Comic(
  path: '/second/',
  title: 'Second',
  cover: 'offline:second',
);
void main() {
  for (final reduced in [false, true]) {
    testWidgets(
      'pagination reveals only added books and retains existing state (reduced=$reduced)',
      (tester) async {
        late Library library;
        await tester.runAsync(() async {
          SharedPreferences.setMockInitialValues({});
          library = Library(await SharedPreferences.getInstance());
          await library.load();
        });
        final source = _Source();
        addTearDown(source.close);
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(disableAnimations: reduced),
                child: Scaffold(
                  body: CustomScrollView(
                    slivers: [
                      SourceBrowser(
                        source: source,
                        library: library,
                        web: false,
                        onOpen: (_) {},
                        initialPath: '/hot/',
                        sliver: true,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final old = find.byWidgetPredicate(
          (w) => w is BookLink && w.comic.path == first.path,
        );
        final oldState = tester.state(old);
        await tester.ensureVisible(find.text('加载更多'));
        await tester.tap(find.text('加载更多'));
        await tester.pump();
        source.pending.complete([first, second, second]);
        await tester.pump();
        final added = find.byWidgetPredicate(
          (w) => w is BookLink && w.comic.path == second.path,
        );
        expect(
          added,
          findsOneWidget,
          reason: 'Duplicates must not become duplicate animated entries.',
        );
        Opacity opacity(Finder f) => tester.widget<Opacity>(
          find.ancestor(of: f, matching: find.byType(Opacity)).first,
        );
        expect(opacity(old).opacity, 1);
        expect(tester.state(old), same(oldState));
        if (reduced) {
          expect(opacity(added).opacity, 1);
        } else {
          expect(opacity(added).opacity, 0);
          await tester.pump(const Duration(milliseconds: 100));
          expect(opacity(added).opacity, inExclusiveRange(0, 1));
        }
        await tester.pumpAndSettle();
        expect(opacity(added).opacity, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}

class _Source extends Dm5Source {
  final pending = Completer<List<Comic>>();
  @override
  Future<SourceCatalog> catalog(String path) async => SourceCatalog(
    books: const [first],
    sorts: {},
    statuses: {},
    parameters: {'pagesize': '2'},
  );
  @override
  Future<List<Comic>> catalogNext(Map<String, String> specs, int page) =>
      pending.future;
}
