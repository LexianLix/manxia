import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/dm5_source.dart';
import 'package:manxia/data/personal_review.dart';
import 'package:manxia/data/reading_journal.dart';
import 'package:manxia/ui/personal_review.dart';
import 'package:manxia/ui/reading_positions.dart';
import 'package:manxia/ui/reading_stats_page.dart';
import 'features_test.dart' as fixtures;

void main() {
  testWidgets(
    'review editor saves explicitly, dismiss keeps saved text, clear needs saving',
    (tester) async {
      final library = (await tester.runAsync(fixtures.library))!;
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          supportedLocales: const [Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Scaffold(
            body: PersonalReviewTile(library: library, comic: fixtures.comic),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('personal-review')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Rate 4 stars'));
      await tester.enterText(
        find.byKey(const ValueKey('review-text')),
        'Worth rereading',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('save-review')));
      await tester.tap(find.byKey(const ValueKey('save-review')));
      await tester.pumpAndSettle();
      expect(library.rating(fixtures.comic), 4);
      expect(library.reviewText(fixtures.comic), 'Worth rereading');
      await tester.tap(find.byKey(const ValueKey('personal-review')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('review-text')),
        'Discard me',
      );
      await tester.ensureVisible(find.byTooltip('Close'));
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(library.reviewText(fixtures.comic), 'Worth rereading');
      await tester.tap(find.byKey(const ValueKey('personal-review')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Clear contents'));
      await tester.tap(find.text('Clear contents'));
      await tester.tap(find.byKey(const ValueKey('save-review')));
      await tester.pumpAndSettle();
      expect(library.rating(fixtures.comic), isNull);
      expect(library.reviewText(fixtures.comic), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      library.dispose();
    },
  );
  testWidgets(
    'statistics clear retains rating, reading history and recovery points',
    (tester) async {
      final library = (await tester.runAsync(fixtures.library))!;
      final source = Dm5Source();
      final r = fixtures.record(3, DateTime.now().millisecondsSinceEpoch);
      await library.save(r);
      await library.setReview(fixtures.comic, 5, '喜欢');
      library.journal.add(r, 65000, DateTime.now(), seen: true);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: ReadingStatsPage(library: library, source: source, web: false),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 分钟'), findsWidgets);
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清空阅读统计'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清空'));
      await tester.pumpAndSettle();
      expect(ReadingTotals(library.journal).milliseconds, 0);
      expect(library.rating(fixtures.comic), 5);
      expect(library.history, hasLength(1));
      expect(library.journal.forComic(fixtures.comic), hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      library.dispose();
      source.close();
    },
  );
  testWidgets(
    'position selection waits for the sheet and does not overwrite progress itself',
    (tester) async {
      final library = (await tester.runAsync(fixtures.library))!;
      final latest = fixtures.record(12, DateTime.now().millisecondsSinceEpoch);
      await library.save(fixtures.record(3, 100));
      await library.save(latest, checkpoint: true);
      ReadingRecord? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  selected = await selectReadingPosition(
                    context,
                    library,
                    fixtures.comic,
                  );
                },
                child: const Text('restore'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('restore'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reading-position-1')));
      await tester.pumpAndSettle();
      expect(selected?.page, 3);
      expect(library.record(fixtures.comic)?.page, 12);
      expect(find.byKey(const ValueKey('reading-position-1')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      library.dispose();
    },
  );
}
