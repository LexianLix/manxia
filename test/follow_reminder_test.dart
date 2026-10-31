import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/platform/follow_reminder.dart';
import 'package:manxia/ui/follow_reminder_sheet.dart';
import 'package:manxia/ui/localized_text.dart';

void main() {
  for (final allowed in [false, true]) {
    testWidgets('weekly reminder reports permission result: $allowed', (
      tester,
    ) async {
      final calls = <Map>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(FollowReminder.channel, (call) async {
            if (call.method == 'get') {
              return {
                'available': true,
                'enabled': false,
                'days': [5],
                'hour': 20,
                'minute': 0,
              };
            }
            calls.add(call.arguments as Map);
            return {'available': true, 'allowed': allowed, 'enabled': allowed};
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(FollowReminder.channel, null),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showFollowReminder(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text(translate('保存', const Locale('en'))));
      await tester.pumpAndSettle();
      expect(calls, hasLength(1));
      expect(calls.single['enabled'], true);
      expect(calls.single['days'], [5]);
      if (allowed) {
        expect(find.byType(SwitchListTile), findsNothing);
      } else {
        expect(
          tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
          false,
        );
        expect(
          find.text(
            translate('系统未允许通知，提醒尚未开启；可在系统通知设置中允许后重试。', const Locale('en')),
          ),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('unavailable reminder keeps the calendar usable', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          FollowReminder.channel,
          (_) async => throw PlatformException(code: 'unavailable'),
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(FollowReminder.channel, null),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showFollowReminder(context),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
      isNull,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
