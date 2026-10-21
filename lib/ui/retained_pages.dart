import 'package:flutter/material.dart';
import 'room_motion.dart';

/// Retarget from the rendered poses instead of replaying a transition at zero.
/// Only visited pages are built; hidden scenes retain state without ticking.
class RetainedPages extends StatefulWidget {
  const RetainedPages({
    super.key,
    required this.index,
    required this.builder,
    this.animate = true,
  });
  final int index;
  final Widget Function(int index) builder;
  final bool animate;
  @override
  State<RetainedPages> createState() => _RetainedPagesState();
}

class _RetainedPagesState extends State<RetainedPages>
    with SingleTickerProviderStateMixin {
  late final clock = AnimationController(
    vsync: this,
    duration: RoomMotion.page,
    value: 1,
  );
  late final visited = <int>{widget.index};
  final starts = <int, (double, double)>{};
  final ends = <int, (double, double)>{};

  (double, double) pose(int index) {
    final end = ends[index] ?? (index == widget.index ? 1.0 : 0.0, 0.0);
    final start = starts[index] ?? end;
    final t = RoomMotion.ease.transform(clock.value);
    return (
      start.$1 + (end.$1 - start.$1) * t,
      start.$2 + (end.$2 - start.$2) * t,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.animate || MediaQuery.disableAnimationsOf(context)) {
      clock.value = 1;
    }
  }

  @override
  void didUpdateWidget(RetainedPages old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      final direction = widget.index > old.index ? 1.0 : -1.0;
      // didUpdateWidget already has the new widget. The old page is still at
      // rest when no prior transition has populated its endpoint.
      ends.putIfAbsent(old.index, () => (1.0, 0.0));
      final snapshots = {for (final index in visited) index: pose(index)};
      visited.add(widget.index);
      for (final index in visited) {
        final snapshot = snapshots[index];
        final start =
            index == widget.index && (snapshot == null || snapshot.$1 < .001)
            ? (0.0, 18 * direction)
            : snapshot ?? (0.0, 18 * direction);
        starts[index] = start;
        ends[index] = index == widget.index
            ? (1.0, 0.0)
            : (0.0, index == old.index ? -18 * direction : start.$2);
      }
      if (widget.animate && !MediaQuery.disableAnimationsOf(context)) {
        clock.forward(from: 0);
      } else {
        clock.value = 1;
      }
    } else if (!widget.animate || MediaQuery.disableAnimationsOf(context)) {
      clock.value = 1;
    }
  }

  @override
  void dispose() {
    clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      for (final index in visited)
        AnimatedBuilder(
          key: ValueKey(index),
          animation: clock,
          child: RepaintBoundary(child: widget.builder(index)),
          builder: (context, child) {
            final current = index == widget.index;
            final (alpha, dx) = pose(index);
            final visible = current || (!clock.isCompleted && alpha > .001);
            return Offstage(
              offstage: !visible,
              child: HeroMode(
                enabled: current,
                child: TickerMode(
                  enabled: current,
                  child: ExcludeSemantics(
                    excluding: !current,
                    child: IgnorePointer(
                      ignoring: !current,
                      child: Opacity(
                        opacity: alpha.clamp(0, 1),
                        child: Transform.translate(
                          offset: Offset(dx, 0),
                          child: child,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
    ],
  );
}
