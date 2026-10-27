import 'package:manxia/ui/paper_leaf.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/library.dart';
import 'package:manxia/data/dm5_source.dart';
import 'package:manxia/main.dart';
import 'package:manxia/ui/book_object.dart';
import 'package:manxia/ui/living_shelf.dart';
import 'package:manxia/ui/retained_pages.dart';
import 'package:manxia/ui/room_motion.dart';
import 'package:manxia/ui/collection_motion.dart';
import 'package:manxia/ui/detail_page.dart';
import 'package:manxia/ui/glass_navigation.dart';
import 'package:manxia/ui/app_shell.dart';
import 'package:manxia/ui/collection_target.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() {
  for (final width in [390.0, 1800.0]) {
    testWidgets(
      'collection lands on the rendered shelf entry at width $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        late Library library;
        await tester.runAsync(() async {
          SharedPreferences.setMockInitialValues({});
          library = Library(await SharedPreferences.getInstance());
          await library.load();
          await library.setOption('navigation', [1, 3, 0]);
        });
        const comic = Comic(
          path: '/anchor/',
          title: 'Anchor',
          cover: 'offline:anchor',
        );
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Builder(
              builder: (context) => Scaffold(
                body: Stack(
                  children: [
                    AppShell(library: library, web: false),
                    Align(
                      alignment: Alignment.topRight,
                      child: TextButton(
                        onPressed: () => collectWithMotion(
                          context,
                          comic,
                          library,
                          false,
                          origin: Rect.fromLTWH(width - 150, 100, 100, 150),
                        ),
                        child: const Text('Collect'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final target = tester.getCenter(find.byKey(shelfAnchor(library)));
        await tester.tap(find.text('Collect'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 435));
        final arrived = tester.getCenter(find.byType(ComicCover).last);
        expect((arrived - target).distance, lessThan(4));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('collection flies to the actual reordered shelf slot', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late Library library;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      library = Library(await SharedPreferences.getInstance());
      await library.load();
      await library.setOption('navigation', [1, 3, 0]);
    });
    const comic = Comic(
      path: '/reordered/',
      title: 'Shelf target',
      cover: 'offline:target',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () =>
                    collectWithMotion(context, comic, library, false),
                child: const Text('Collect'),
              ),
            ),
            bottomNavigationBar: FrostedNavigation(
              selectedIndex: 0,
              onSelected: (_) {},
              destinations: [
                roomDestinations[1],
                roomDestinations[3],
                roomDestinations[0],
              ],
            ),
          ),
        ),
      ),
    );
    final destination = tester.getCenter(
      find.byKey(const ValueKey('navigation-icon-0')),
    );
    await tester.tap(find.text('Collect'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 415));
    expect(
      tester.getCenter(find.byType(ComicCover)).dx,
      closeTo(destination.dx, 4),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ComicCover), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'a failed directory explains the disabled button and retries into reading',
    (tester) async {
      late Library library;
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        library = Library(await SharedPreferences.getInstance());
        await library.load();
      });
      final first = Completer<ComicDetail>();
      final second = Completer<ComicDetail>();
      final source = _RetryDetail([first.future, second.future]);
      addTearDown(source.close);
      const comic = Comic(
        path: '/retry/',
        title: 'Retry',
        cover: 'offline:retry',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: DetailPage(
            comic: comic,
            library: library,
            source: source,
            web: false,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('正在读取章节目录…'), findsOneWidget);
      first.completeError(SourceException('未能识别章节目录'));
      await tester.pumpAndSettle();
      FilledButton start() => tester.widget<FilledButton>(
        find.byWidgetPredicate((w) => w is FilledButton).first,
      );
      expect(start().onPressed, isNull);
      expect(find.text('章节暂不可用'), findsOneWidget);
      expect(find.text('原站暂未提供章节'), findsNothing);
      await tester.ensureVisible(find.text('重试读取目录'));
      await tester.tap(find.text('重试读取目录'));
      await tester.pump();
      // The retiring retry button is still painted but cannot submit again.
      await tester.tap(find.text('重试读取目录'), warnIfMissed: false);
      expect(source.call, 2);
      second.complete(const ComicDetail(comic, [Chapter('/m1/', '第1话')]));
      await tester.pumpAndSettle();
      expect(start().onPressed, isNotNull);
      expect(find.text('重试读取目录'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'wide detail keeps the book landing point fixed while metadata arrives',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late Library library;
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        library = Library(await SharedPreferences.getInstance());
        await library.load();
      });
      const comic = Comic(
        path: '/landing/',
        title: 'Book',
        cover: 'offline:motion',
      );
      final pending = Completer<ComicDetail>();
      final source = _DeferredDetail(pending);
      await tester.pumpWidget(
        MaterialApp(
          home: DetailPage(
            comic: comic,
            library: library,
            source: source,
            web: false,
          ),
        ),
      );
      await tester.pump();
      // Detail should settle on the actual cover, not a permanently open
      // decorative inner page. Keep its landing point stable as data arrives.
      final cover = find.byWidgetPredicate((w) => w is ComicCover);
      expect(cover, findsOneWidget);
      expect(find.byType(BookObject), findsNothing);
      final landing = tester.getRect(cover);
      pending.complete(
        ComicDetail(
          Comic(
            path: comic.path,
            cover: comic.cover,
            title: 'A long book title ' * 7,
            author: 'Author',
            tags: List.generate(12, (i) => 'Tag $i'),
            description: 'A full synopsis. ' * 100,
          ),
          const [],
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(cover), landing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      source.close();
    },
  );
  testWidgets('removing a book cancels its unfinished collection flight', (
    tester,
  ) async {
    late Library library;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      library = Library(await SharedPreferences.getInstance());
      await library.load();
    });
    const comic = Comic(
      path: '/collect-motion/',
      title: 'Collected book',
      cover: 'offline:motion',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  collectWithMotion(context, comic, library, false),
              child: const Text('Toggle'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Toggle'));
    await tester.pump(const Duration(milliseconds: 60));
    expect(library.contains(comic), isTrue);
    expect(find.byType(ComicCover), findsOneWidget);
    await tester.tap(find.text('Toggle'));
    await tester.pump();
    expect(library.contains(comic), isFalse);
    expect(find.byType(ComicCover), findsNothing);
    await tester.tap(find.text('Toggle'));
    await tester.tap(find.text('Toggle'));
    await tester.pump();
    expect(library.contains(comic), isFalse);
    expect(find.byType(ComicCover), findsNothing);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('rapid page changes preserve every visible page pose', (
    tester,
  ) async {
    var selected = 0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (_, setState) {
            update = setState;
            return RetainedPages(
              index: selected,
              builder: (index) => Center(
                child: Text('Scene $index', key: ValueKey('scene-$index')),
              ),
            );
          },
        ),
      ),
    );
    double opacity(int index) =>
        1 -
        tester
            .widget<PaperLeaf>(
              find
                  .ancestor(
                    of: find.byKey(ValueKey('scene-$index')),
                    matching: find.byType(PaperLeaf),
                  )
                  .first,
            )
            .amount;
    for (final next in [1, 2, 0, 2, 1]) {
      final visible = <int, (double, Offset)>{
        for (final i in [0, 1, 2])
          if (find.byKey(ValueKey('scene-$i')).evaluate().isNotEmpty)
            i: (
              opacity(i),
              tester.getTopLeft(find.byKey(ValueKey('scene-$i'))),
            ),
      };
      update(() => selected = next);
      await tester.pump();
      for (final entry in visible.entries) {
        if (entry.value.$1 < .001) continue;
        expect(opacity(entry.key), closeTo(entry.value.$1, .001));
        expect(
          (tester.getTopLeft(find.byKey(ValueKey('scene-${entry.key}'))) -
                  entry.value.$2)
              .distance,
          lessThan(.01),
        );
      }
      await tester.pump(const Duration(milliseconds: 70));
    }
    await tester.pumpAndSettle();
    expect(find.text('Scene 1').hitTestable(), findsOneWidget);
    expect(find.text('Scene 0'), findsNothing);
    expect(find.text('Scene 2'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid shelf arrow taps keep the last requested destination', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late Library library;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      library = Library(await SharedPreferences.getInstance());
      await library.load();
      for (final book in library.samples) {
        await library.toggle(book);
      }
    });
    await tester.pumpWidget(ManxiaApp(library: library));
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byTooltip('下一本'));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.tap(find.byTooltip('上一本'));
    await tester.pumpAndSettle();
    expect(find.text('03 / 07'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a book flight reverses safely before opening completes', (
    tester,
  ) async {
    const comic = Comic(
      path: '/motion/',
      title: 'Motion book',
      cover: 'offline:motion',
    );
    final navigator = GlobalKey<NavigatorState>();
    Widget book() =>
        const BookFlight(child: BookObject(comic, web: false, number: 4));
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomLeft,
            child: SizedBox(
              width: 150,
              height: 210,
              child: GestureDetector(
                onTap: () => navigator.currentState!.push(
                  PageRouteBuilder<void>(
                    opaque: false,
                    transitionDuration: RoomMotion.book,
                    reverseTransitionDuration: RoomMotion.bookReturn,
                    pageBuilder: (_, _, _) => Scaffold(
                      body: Center(
                        child: SizedBox(width: 200, height: 280, child: book()),
                      ),
                    ),
                    transitionsBuilder: (_, animation, _, child) =>
                        OpenBookTransition(
                          animation: animation,
                          comic: comic,
                          web: false,
                          child: child,
                        ),
                  ),
                ),
                child: book(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(BookFlight));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 130));
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byType(BookFlight), findsOneWidget);
    expect(navigator.currentState!.canPop(), isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

class _DeferredDetail extends Dm5Source {
  _DeferredDetail(this.pending);
  final Completer<ComicDetail> pending;
  @override
  Future<ComicDetail> detail(Comic comic) => pending.future;
}

class _RetryDetail extends Dm5Source {
  _RetryDetail(this.results);
  final List<Future<ComicDetail>> results;
  int call = 0;
  @override
  Future<ComicDetail> detail(Comic comic) => results[call++];
}
