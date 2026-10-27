import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/ui/retained_sections.dart';

void main() {
  testWidgets('section retarget preserves poses, heights and visited state', (
    tester,
  ) async {
    var selected = 'a', reduced = false, animate = true, mounts = 0, taps = 0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
              child: SingleChildScrollView(
                child: RetainedSections(
                  index: selected,
                  animate: animate,
                  order: const ['a', 'b', 'c'],
                  builder: (id) => _Probe(
                    key: ValueKey(id),
                    mounted: () => mounts++,
                    child: GestureDetector(
                      onTap: () => taps++,
                      child: SizedBox(
                        key: ValueKey('body-$id'),
                        width: 400,
                        height: id == 'a' ? 200 : 400,
                        child: Text(id),
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
    expect(mounts, 1);
    update(() => selected = 'b');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final section = find.byType(RetainedSections);
    final before = tester.getSize(section).height;
    final opacity = tester
        .widgetList<Opacity>(
          find.descendant(of: section, matching: find.byType(Opacity)),
        )
        .map((w) => w.opacity)
        .toList();
    expect(before, inExclusiveRange(200, 400));
    // Crossfade without an empty midpoint, including interrupted transitions.
    expect(
      opacity.fold<double>(0, (sum, value) => sum + value),
      closeTo(1, .001),
    );
    update(() => selected = 'c');
    await tester.pump();
    expect(tester.getSize(section).height, closeTo(before, .01));
    final after = tester
        .widgetList<Opacity>(
          find.descendant(of: section, matching: find.byType(Opacity)),
        )
        .map((w) => w.opacity)
        .toList();
    expect(after.take(2), opacity);
    await tester.pumpAndSettle();
    update(() => selected = 'a');
    await tester.pumpAndSettle();
    expect(mounts, 3);
    expect(tester.getSize(section).height, 200);
    await tester.tap(find.text('a'));
    expect(taps, 1);
    update(() => selected = 'c');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 25));
    update(() => animate = false);
    await tester.pump();
    expect(tester.getSize(section).height, 400);
    reduced = true;
    update(() => selected = 'b');
    await tester.pump();
    expect(tester.getSize(section).height, 400);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

class _Probe extends StatefulWidget {
  const _Probe({super.key, required this.mounted, required this.child});
  final VoidCallback mounted;
  final Widget child;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.mounted();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
