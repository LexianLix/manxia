import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/dm5_source.dart';
import 'package:manxia/data/library.dart';
import 'package:manxia/ui/detail_page.dart';

void main() {
  testWidgets(
    'detail catalog keeps virtual layout through reverse, rapid retarget and group changes',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late Library library;
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        library = Library(await SharedPreferences.getInstance());
        await library.load();
      });
      final source = _Catalog();
      addTearDown(source.close);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: DetailPage(
            comic: _Catalog.comic,
            library: library,
            source: source,
            web: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('章节目录'));
      await tester.pumpAndSettle();
      expect(find.text('第1话'), findsOneWidget);
      int rendered() => tester
          .widgetList<OutlinedButton>(find.byType(OutlinedButton))
          .where((w) => w.key is ValueKey<String>)
          .length;
      expect(rendered(), lessThan(60));
      await tester.tap(find.byTooltip('切换倒序'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      await tester.tap(find.byTooltip('切换正序'));
      await tester.pumpAndSettle();
      expect(find.text('第1话'), findsOneWidget);
      expect(find.text('第535话'), findsNothing);
      final headerY = tester.getTopLeft(find.text('章节目录')).dy;
      await tester.tap(find.widgetWithText(ChoiceChip, '番外'));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('章节目录')).dy, closeTo(headerY, .5));
      expect(find.text('番外1'), findsOneWidget);
      expect(find.text('第1话'), findsNothing);
      expect(rendered(), lessThan(60));
      library.motion = false;
      await tester.tap(find.byTooltip('切换倒序'));
      await tester.pump();
      expect(find.text('番外18'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

class _Catalog extends Dm5Source {
  static const comic = Comic(
    path: '/virtual-catalog/',
    title: 'Catalog',
    cover: 'offline:catalog',
  );
  @override
  Future<ComicDetail> detail(Comic _) async => ComicDetail(comic, [
    for (var i = 535; i > 0; i--) Chapter('/m$i/', '第$i话'),
    for (var i = 18; i > 0; i--) Chapter('/extra$i/', '番外$i', group: '番外'),
  ]);
}
