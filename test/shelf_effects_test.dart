import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/library.dart';
import 'package:manxia/ui/living_shelf.dart';

void main() {
  testWidgets(
    'tilt responds to settings and stops while hidden, reduced or backgrounded',
    (tester) async {
      final calls = <String>[];
      const sensor = MethodChannel(
        'dev.fluttercommunity.plus/sensors/accelerometer',
      );
      const methods = MethodChannel('dev.fluttercommunity.plus/sensors/method');
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(sensor, (call) async {
        calls.add(call.method);
        return null;
      });
      messenger.setMockMethodCallHandler(methods, (_) async => null);
      addTearDown(() {
        messenger.setMockMethodCallHandler(sensor, null);
        messenger.setMockMethodCallHandler(methods, null);
      });
      SharedPreferences.setMockInitialValues({});
      final library = Library(await SharedPreferences.getInstance());
      await library.load();
      var visible = true, reduced = false;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (c, set) {
              update = set;
              return MediaQuery(
                data: MediaQuery.of(c).copyWith(disableAnimations: reduced),
                child: TickerMode(
                  enabled: visible,
                  child: ListenableBuilder(
                    listenable: library,
                    builder: (_, _) => Scaffold(
                      body: SingleChildScrollView(
                        child: LivingShelf(
                          books: const [
                            Comic(
                              path: '/tilt/',
                              title: 'Shelf',
                              cover: 'offline:tilt',
                            ),
                          ],
                          library: library,
                          web: false,
                          onOpen: (_) {},
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      await library.setOption('tilt', true);
      await tester.pumpAndSettle();
      expect(calls, ['listen']);
      await library.setOption('tilt', false);
      await tester.pumpAndSettle();
      expect(calls, ['listen', 'cancel']);
      await library.setOption('tilt', true);
      await tester.pumpAndSettle();
      update(() => visible = false);
      await tester.pump();
      await tester.pump();
      expect(calls.last, 'cancel');
      update(() => visible = true);
      await tester.pumpAndSettle();
      expect(calls.last, 'listen');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(calls.last, 'cancel');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(calls.last, 'listen');
      update(() => reduced = true);
      await tester.pumpAndSettle();
      expect(calls.last, 'cancel');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
