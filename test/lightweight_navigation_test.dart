import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/ui/retained_pages.dart';
import 'package:manxia/ui/room_motion.dart';

void main() {
  testWidgets('tab changes remain live and do not capture full-page textures', (
    tester,
  ) async {
    var selected = 0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (_, set) {
            update = set;
            return Scaffold(
              body: RetainedPages(
                index: selected,
                builder: (index) => Center(child: Text('Page $index')),
              ),
            );
          },
        ),
      ),
    );
    update(() => selected = 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    expect(
      find.byType(SnapshotWidget),
      findsNothing,
      reason: 'Switching tabs must not rasterize and curl the full screen.',
    );
    update(() => selected = 2);
    await tester.pumpAndSettle();
    expect(find.text('Page 2').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ordinary routes do not capture a page to perform a turn', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: ThemeData(
          pageTransitionsTheme: const PageTransitionsTheme(
            builders: {TargetPlatform.android: RoomPageTransitions()},
          ),
        ),
        home: const Scaffold(body: Text('Home')),
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Settings')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    expect(find.byType(SnapshotWidget), findsNothing);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
