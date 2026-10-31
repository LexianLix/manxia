import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/dm5_source.dart';
import 'package:manxia/data/follow_calendar.dart';
import 'package:manxia/data/library.dart';
import 'package:manxia/ui/follow_calendar_page.dart';
import 'package:manxia/ui/localized_text.dart';
import 'features_test.dart' as fixtures;

void main() {
  testWidgets(
    'calendar read queue and focus remain consistent through actions',
    (tester) async {
      late Library library;
      await tester.runAsync(() async {
        library = await fixtures.library();
        await library.toggle(fixtures.comic);
        await library.recordFollow(
          ComicDetail(fixtures.comic, const [Chapter('/one/', 'One')]),
        );
        await library.recordFollow(
          ComicDetail(fixtures.comic, const [
            Chapter('/two/', 'Two'),
            Chapter('/one/', 'One'),
          ]),
        );
      });
      final source = Dm5Source();
      addTearDown(source.close);
      await tester.pumpWidget(
        MaterialApp(
          home: FollowCalendarPage(
            library: library,
            source: source,
            web: false,
            onOpen: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      String label(String s) => translate(s, const Locale('en'));
      await tester.tap(find.text(label('待读')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(label('标为已读')));
      await tester.tap(find.text(label('标为已读')));
      await tester.pumpAndSettle();
      expect(library.eventUnread(library.followEvents.single), false);
      expect(find.text(label('暂时没有待读新章')), findsOneWidget);
      await tester.ensureVisible(find.text(label('管理关注')));
      await tester.tap(find.text(label('管理关注')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      expect(library.meta(fixtures.comic)['followPinned'], true);
      Navigator.of(tester.element(find.byType(CheckboxListTile))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text(label('特别关注')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(label('标为未读')));
      await tester.tap(find.text(label('标为未读')));
      await tester.pumpAndSettle();
      expect(library.eventUnread(library.followEvents.single), true);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
