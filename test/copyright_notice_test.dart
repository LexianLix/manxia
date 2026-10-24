import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/dm5_source.dart';
import 'package:manxia/data/library.dart';
import 'package:manxia/ui/detail_page.dart';

void main() {
  const comic = Comic(
    path: '/manhua-removed/',
    title: 'Removed',
    cover: 'offline:absent',
  );
  for (final cached in [false, true]) {
    testWidgets('explicit copyright removal is visible with cached=$cached', (
      tester,
    ) async {
      late Library library;
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        library = Library(await SharedPreferences.getInstance());
        await library.load();
      });
      final old = Dm5Source.offlineDetail;
      addTearDown(() => Dm5Source.offlineDetail = old);
      Dm5Source.offlineDetail = (_) async => cached
          ? const ComicDetail(comic, [Chapter('/m1/', 'Downloaded')])
          : null;
      final source = Dm5Source(
        client: MockClient(
          (_) async => http.Response(
            '<p class="detail-main-info-title">Removed</p><div class="warning-bar">应版权方要求，已移除作品链接</div>',
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          ),
        ),
      );
      addTearDown(source.close);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: DetailPage(
            comic: comic,
            library: library,
            source: source,
            web: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('当前书源没有版权，无法提供在线章节'), findsWidgets);
      if (cached) {
        final button = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, '阅读已下载章节'),
        );
        expect(button.onPressed, isNotNull);
        expect(find.textContaining('已下载章节仍可离线阅读'), findsOneWidget);
      } else {
        final button = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, '书源没有版权'),
        );
        expect(button.onPressed, isNull);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
