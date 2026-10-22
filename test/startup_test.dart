import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/data/library.dart';
import 'package:manxia/ui/startup.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('first frame is visible while native preferences are pending', (
    tester,
  ) async {
    final pending = Completer<Library>();
    await tester.pumpWidget(
      ManxiaStartup(
        load: (report) {
          report('正在读取本地设置');
          return pending.future;
        },
        builder: (_) => const SizedBox(),
      ),
    );
    await tester.pump();
    expect(find.text('漫匣'), findsOneWidget);
    expect(find.text('正在读取本地设置'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('JNI startup failure becomes a retryable diagnostic screen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'favorites': 'preserved'});
    final prefs = await SharedPreferences.getInstance();
    var attempts = 0;
    await tester.pumpWidget(
      ManxiaStartup(
        load: (report) async {
          attempts++;
          report('正在读取本地设置');
          if (attempts == 1) {
            throw PlatformException(
              code: 'PlatformException',
              message:
                  'java.lang.NoSuchMethodError: SharedPreferencesApiRegistrar.getAll',
            );
          }
          return Library(prefs);
        },
        builder: (_) => const MaterialApp(home: Text('书架已打开')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('启动未完成'), findsOneWidget);
    expect(find.text('复制诊断信息'), findsOneWidget);
    expect(prefs.getString('favorites'), 'preserved');
    await tester.tap(find.text('重试启动'));
    await tester.pumpAndSettle();
    expect(find.text('书架已打开'), findsOneWidget);
    expect(attempts, 2);
    expect(prefs.getString('favorites'), 'preserved');
    expect(tester.takeException(), isNull);
  });
}
