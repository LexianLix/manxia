import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/dm5_source.dart';
import 'package:manxia/data/library.dart';
import 'package:manxia/ui/advanced_settings.dart';

void main() {
  testWidgets(
    'an installed current release is reported as up to date without a download prompt',
    (tester) async {
      PackageInfo.setMockInitialValues(
        appName: 'Manxia',
        packageName: 'io.manxia.manxia',
        version: '0.3.8',
        buildNumber: '2017',
        buildSignature: 'test',
      );
      late Library library;
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        library = Library(await SharedPreferences.getInstance());
        await library.load();
      });
      final source = _PendingSource();
      addTearDown(source.close);
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            MaterialApp(
              locale: const Locale('zh', 'CN'),
              supportedLocales: const [Locale('zh', 'CN')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              home: Scaffold(
                body: SingleChildScrollView(
                  child: AdvancedSettings(
                    library: library,
                    source: source,
                    web: false,
                    sourceOnly: true,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('检查 GitHub 更新'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byType(AlertDialog), findsNothing);
          expect(find.textContaining('已是最新'), findsWidgets);
          await tester.pumpWidget(const SizedBox());
        },
        () => MockClient(
          (_) async => http.Response(
            jsonEncode({
              'tag_name': 'v0.3.8',
              'name': 'v0.3.8',
              'body': 'notes',
              'html_url':
                  'https://github.com/LexianLix/manxia/releases/tag/v0.3.8',
              'assets': [
                {'name': 'Manxia-0.3.8-arm64-v8a.apk'},
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
    },
  );
  testWidgets('source check shows progress next to the tapped action', (
    tester,
  ) async {
    late Library library;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      library = Library(await SharedPreferences.getInstance());
      await library.load();
    });
    final source = _PendingSource();
    addTearDown(source.close);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: SingleChildScrollView(
            child: AdvancedSettings(
              library: library,
              source: source,
              web: false,
              sourceOnly: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('检查当前源'));
    await tester.pump();
    final tile = find
        .ancestor(of: find.text('检查当前源'), matching: find.byType(ListTile))
        .first;
    expect(
      find.descendant(
        of: tile,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    source.homeResult.complete([]);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('查看检查详情'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看检查详情'));
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'cancel source check is immediate and late replies cannot replace its status',
    (tester) async {
      late Library library;
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        library = Library(await SharedPreferences.getInstance());
        await library.load();
      });
      final source = _PendingSource();
      addTearDown(source.close);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(
            body: SingleChildScrollView(
              child: AdvancedSettings(
                library: library,
                source: source,
                web: false,
                sourceOnly: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('检查当前源'));
      await tester.pump();
      await tester.tap(find.byTooltip('取消检查'));
      await tester.pumpAndSettle();
      expect(find.text('检查已取消'), findsOneWidget);
      source.homeResult.complete([]);
      await tester.pumpAndSettle();
      expect(find.text('检查已取消'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'new release dialog scrolls long notes and clears check busy state before showing it',
    (tester) async {
      tester.view.physicalSize = const Size(390, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      PackageInfo.setMockInitialValues(
        appName: 'Manxia',
        packageName: 'io.manxia.manxia',
        version: '0.3.8',
        buildNumber: '2017',
        buildSignature: 'test',
      );
      late Library library;
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        library = Library(await SharedPreferences.getInstance());
        await library.load();
      });
      final source = _PendingSource();
      addTearDown(source.close);
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            MaterialApp(
              locale: const Locale('zh', 'CN'),
              supportedLocales: const [Locale('zh', 'CN')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              builder: (c, child) => MediaQuery(
                data: MediaQuery.of(
                  c,
                ).copyWith(textScaler: const TextScaler.linear(1.5)),
                child: child!,
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: AdvancedSettings(
                    library: library,
                    source: source,
                    web: false,
                    sourceOnly: true,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('检查 GitHub 更新'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('检查 GitHub 更新'));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(
            tester.widget<AlertDialog>(find.byType(AlertDialog)).scrollable,
            isTrue,
          );
          expect(
            find.byType(CircularProgressIndicator, skipOffstage: false),
            findsNothing,
          );
          expect(find.text('稍后').hitTestable(), findsOneWidget);
          expect(find.text('前往下载').hitTestable(), findsOneWidget);
          await tester.tap(find.text('稍后'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
        () => MockClient(
          (_) async => http.Response(
            jsonEncode({
              'tag_name': 'v0.3.9',
              'body': List.filled(50, '修复设置与改进页面布局').join('\n'),
              'assets': [
                {'name': 'Manxia-0.3.9-arm64-v8a.apk'},
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
    },
  );
}

class _PendingSource extends Dm5Source {
  @override
  Dm5Source forkForCheck() => this;
  final homeResult = Completer<List<Comic>>();
  @override
  Future<List<Comic>> home() => homeResult.future;
}
