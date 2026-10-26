import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/rendering.dart';
import 'package:manxia/ui/glass_navigation.dart';
import 'package:manxia/ui/living_shelf.dart';
import 'package:manxia/data/comic.dart';

void main() {
  testWidgets(
    'six tabs keep a complete selected label at 150 percent on a phone',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var selected = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (c, set) => MediaQuery(
              data: MediaQuery.of(
                c,
              ).copyWith(textScaler: const TextScaler.linear(1.5)),
              child: Scaffold(
                bottomNavigationBar: FrostedNavigation(
                  selectedIndex: selected,
                  destinations: roomDestinations,
                  haptics: false,
                  onSelected: (i) => set(() => selected = i),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Downloads'));
      await tester.pumpAndSettle();
      final label = find.text('Downloads');
      final paragraph = tester.renderObject<RenderParagraph>(label);
      expect(
        paragraph.getBoxesForSelection(
          const TextSelection(baseOffset: 0, extentOffset: 9),
        ),
        hasLength(1),
      );
      final rect = tester.getRect(label);
      expect(rect.left, greaterThanOrEqualTo(16));
      expect(rect.right, lessThanOrEqualTo(374));
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'membership changes cancel a pending drag and the next tap uses the new order',
    (tester) async {
      var ids = [0, 1, 2, 3];
      late StateSetter update;
      final selections = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (c, set) {
              update = set;
              return Scaffold(
                bottomNavigationBar: FrostedNavigation(
                  selectedIndex: ids.indexOf(0),
                  haptics: false,
                  destinations: ids.map((id) => roomDestinations[id]).toList(),
                  onSelected: (i) => selections.add(ids[i]),
                ),
              );
            },
          ),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Library')),
      );
      await gesture.moveTo(tester.getCenter(find.text('Settings')));
      await tester.pump(const Duration(milliseconds: 60));
      update(() => ids = [3, 0, 4]);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(selections, isEmpty);
      await tester.tap(find.text('Downloads'));
      await tester.pumpAndSettle();
      expect(selections, [4]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reduced motion immediately settles a changing member layout', (
    tester,
  ) async {
    var ids = [0, 1, 2, 3];
    var reduced = false;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (c, set) {
            update = set;
            return MediaQuery(
              data: MediaQuery.of(c).copyWith(disableAnimations: reduced),
              child: Scaffold(
                bottomNavigationBar: FrostedNavigation(
                  selectedIndex: ids.indexOf(0),
                  haptics: false,
                  destinations: ids.map((id) => roomDestinations[id]).toList(),
                  onSelected: (_) {},
                ),
              ),
            );
          },
        ),
      ),
    );
    update(() => ids = [1, 3, 0, 4, 5]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    update(() => reduced = true);
    await tester.pump();
    expect(
      tester.getCenter(find.byKey(const ValueKey('navigation-lens'))).dx,
      closeTo(tester.getCenter(find.text('Library')).dx, 1),
    );
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets('reordering members keeps icons and lens continuous', (
    tester,
  ) async {
    var ids = [0, 1, 2, 3];
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (c, set) {
            update = set;
            return Scaffold(
              bottomNavigationBar: FrostedNavigation(
                selectedIndex: ids.indexOf(0),
                haptics: false,
                destinations: ids.map((id) => roomDestinations[id]).toList(),
                onSelected: (_) {},
              ),
            );
          },
        ),
      ),
    );
    final before = tester.getCenter(find.text('Library'));
    final lens = tester.getCenter(
      find.byKey(const ValueKey('navigation-lens')),
    );
    update(() => ids = [1, 2, 3, 0]);
    await tester.pump();
    expect(tester.getCenter(find.text('Library')).dx, closeTo(before.dx, .1));
    expect(
      tester.getCenter(find.byKey(const ValueKey('navigation-lens'))).dx,
      closeTo(lens.dx, .1),
    );
    await tester.pump(const Duration(milliseconds: 70));
    expect(tester.getCenter(find.text('Library')).dx, greaterThan(before.dx));
    await tester.pumpAndSettle();
    expect(
      tester.getCenter(find.byKey(const ValueKey('navigation-lens'))).dx,
      closeTo(tester.getCenter(find.text('Library')).dx, 1),
    );
    expect(tester.takeException(), isNull);
  });
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
    final destination = tester.getCenter(find.byTooltip('Settings'));
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
    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();
    expect(selected, 3);
    expect(
      tester.getCenter(find.byKey(const ValueKey('navigation-lens'))).dx,
      closeTo(tester.getCenter(find.byTooltip('Settings')).dx, 1),
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
