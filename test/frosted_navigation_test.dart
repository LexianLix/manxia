import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/ui/glass_navigation.dart';
import 'package:manxia/ui/living_shelf.dart';
import 'package:manxia/data/comic.dart';

void main() {
  testWidgets(
    'opening a book keeps the loaded detail mounted through the transition',
    (tester) async {
      final progress = ValueNotifier(0.0);
      addTearDown(progress.dispose);
      var mounts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<double>(
            valueListenable: progress,
            builder: (_, value, child) => OpenBookTransition(
              animation: AlwaysStoppedAnimation(value),
              web: false,
              comic: const Comic(
                path: '/test/',
                title: 'Test',
                cover: 'offline:test',
              ),
              origin: const Rect.fromLTWH(70, 250, 150, 220),
              child: child!,
            ),
            child: _PageProbe(onMount: () => mounts++),
          ),
        ),
      );
      for (final value in [.15, .40, .65, .99, 1.0]) {
        progress.value = value;
        await tester.pump();
      }
      expect(mounts, 1);
      expect(find.text('Detail'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('scrubbing the lens changes pages only after release', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final selections = <int>[];
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, update) => Scaffold(
            extendBody: true,
            body: const ColoredBox(color: Colors.teal),
            bottomNavigationBar: FrostedNavigation(
              selectedIndex: selected,
              haptics: false,
              onSelected: (index) {
                selections.add(index);
                update(() => selected = index);
              },
            ),
          ),
        ),
      ),
    );
    final origin = tester.getCenter(
      find.byKey(const ValueKey('navigation-lens')),
    );
    final destination = tester.getCenter(find.text('Settings'));
    final gesture = await tester.startGesture(origin);
    await gesture.moveTo(destination);
    await tester.pump(const Duration(milliseconds: 150));
    expect(selections, isEmpty);
    expect(
      tester.getCenter(find.byKey(const ValueKey('navigation-lens'))).dx,
      greaterThan(origin.dx + 150),
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(selections, [3]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelled drag restores the selected destination', (
    tester,
  ) async {
    final selections = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: FrostedNavigation(
            selectedIndex: 0,
            haptics: false,
            onSelected: selections.add,
          ),
        ),
      ),
    );
    final initial = tester.getCenter(
      find.byKey(const ValueKey('navigation-lens')),
    );
    final gesture = await tester.startGesture(initial);
    await gesture.moveTo(tester.getCenter(find.text('History')));
    await tester.pump();
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(selections, isEmpty);
    expect(
      tester.getCenter(find.byKey(const ValueKey('navigation-lens'))).dx,
      closeTo(initial.dx, .5),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion selects immediately with a bottom safe area', (
    tester,
  ) async {
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            disableAnimations: true,
            padding: EdgeInsets.only(bottom: 34),
            textScaler: TextScaler.linear(1.5),
          ),
          child: StatefulBuilder(
            builder: (context, update) => Scaffold(
              bottomNavigationBar: FrostedNavigation(
                selectedIndex: selected,
                haptics: false,
                onSelected: (index) => update(() => selected = index),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Settings'));
    await tester.pump();
    expect(selected, 3);
    expect(
      tester.getCenter(find.byKey(const ValueKey('navigation-lens'))).dx,
      closeTo(tester.getCenter(find.text('Settings')).dx, 1),
    );
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.takeException(), isNull);
    final label = tester.getRect(find.text('Settings'));
    expect(label.bottom, lessThan(tester.view.physicalSize.height - 34));
  });
}

class _PageProbe extends StatefulWidget {
  const _PageProbe({required this.onMount});
  final VoidCallback onMount;
  @override
  State<_PageProbe> createState() => _PageProbeState();
}

class _PageProbeState extends State<_PageProbe> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('Detail'));
}
