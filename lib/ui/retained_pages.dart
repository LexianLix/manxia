import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'room_motion.dart';
import 'paper_leaf.dart';

/// Retarget from the rendered poses instead of replaying a transition at zero.
/// Only visited pages are built; hidden scenes retain state without ticking.
class RetainedPages extends StatefulWidget {
  const RetainedPages({
    super.key,
    required this.index,
    required this.builder,
    this.animate = true,
    this.onSelected,
    this.order = const [0, 1, 2, 3],
  });
  final int index;
  final Widget Function(int index) builder;
  final bool animate;
  final ValueChanged<int>? onSelected;
  final List<int> order;
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
  final hinges = <int, bool>{};
  bool dragging = false;
  int dragFrom = 0;
  int? dragTarget;
  double dragDistance = 0, dragFraction = 0, width = 390, direction = 1;
  final dragStarts = <int, (double, double)>{};

  (double, double) pose(int index) {
    if (dragging) {
      final start = dragStarts[index] ?? (0.0, direction * 48);
      final end = index == dragTarget
          ? (1.0, 0.0)
          : (0.0, index == dragFrom ? -direction * 48 : start.$2);
      return (
        start.$1 + (end.$1 - start.$1) * dragFraction,
        start.$2 + (end.$2 - start.$2) * dragFraction,
      );
    }
    final end = ends[index] ?? (index == widget.index ? 1.0 : 0.0, 0.0);
    final start = starts[index] ?? end;
    final t = RoomMotion.ease.transform(clock.value);
    return (
      start.$1 + (end.$1 - start.$1) * t,
      start.$2 + (end.$2 - start.$2) * t,
    );
  }

  void beginDrag(DragStartDetails details) {
    dragStarts.clear();
    for (final i in visited) {
      dragStarts[i] = pose(i);
    }
    clock.stop();
    dragFrom = widget.index;
    dragDistance = dragFraction = 0;
    dragTarget = null;
    dragging = true;
  }

  void updateDrag(DragUpdateDetails details) {
    dragDistance += details.delta.dx;
    direction = dragDistance < 0 ? 1 : -1;
    final at = widget.order.indexOf(dragFrom) + direction.toInt();
    if (at < 0 || at >= widget.order.length) {
      setState(() {
        dragTarget = null;
        dragFraction = 0;
      });
      return;
    }
    setState(() {
      dragTarget = widget.order[at];
      hinges[dragFrom] = direction < 0;
      hinges[dragTarget!] = direction > 0;
      visited.add(dragTarget!);
      if ((dragStarts[dragTarget]?.$1 ?? 0) < .001) {
        dragStarts[dragTarget!] = (0, direction * 48);
      }
      dragFraction = (dragDistance.abs() / width).clamp(0.0, 1.0);
    });
  }

  Map<int, (double, double)> captureDrag() {
    final snapshot = {for (final i in visited) i: pose(i)};
    dragging = false;
    starts.addAll(snapshot);
    ends.addAll(snapshot);
    clock.value = 1;
    return snapshot;
  }

  void endDrag([DragEndDetails? details]) {
    if (!dragging) return;
    final target = dragTarget;
    final accept =
        details != null &&
        target != null &&
        (dragFraction > .22 ||
            ((details.primaryVelocity ?? 0) * -direction) > 450);
    final snapshots = captureDrag();
    if (accept) {
      widget.onSelected!(target);
    } else {
      setState(() {
        for (final i in visited) {
          starts[i] = snapshots[i]!;
          ends[i] = i == widget.index ? (1, 0) : (0, snapshots[i]!.$2);
        }
        if (widget.animate && !MediaQuery.disableAnimationsOf(context)) {
          clock.forward(from: 0);
        } else {
          clock.value = 1;
        }
      });
    }
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
    if (dragging && !listEquals(old.order, widget.order)) endDrag();
    if (old.index != widget.index) {
      if (dragging) captureDrag();
      final from = widget.order.indexOf(old.index);
      final to = widget.order.indexOf(widget.index);
      final direction = from >= 0 && to >= 0
          ? (to > from ? 1.0 : -1.0)
          : (widget.index > old.index ? 1.0 : -1.0);
      // didUpdateWidget already has the new widget. The old page is still at
      // rest when no prior transition has populated its endpoint.
      ends.putIfAbsent(old.index, () => (1.0, 0.0));
      final snapshots = {for (final index in visited) index: pose(index)};
      visited.add(widget.index);
      for (final index in visited) {
        final snapshot = snapshots[index];
        final start =
            index == widget.index && (snapshot == null || snapshot.$1 < .001)
            ? (0.0, 48 * direction)
            : snapshot ?? (0.0, 48 * direction);
        starts[index] = start;
        if (start.$1 >= .999 || start.$1 <= .001) {
          hinges[index] = index == widget.index ? direction > 0 : direction < 0;
        }
        ends[index] = index == widget.index
            ? (1.0, 0.0)
            : (0.0, index == old.index ? -48 * direction : start.$2);
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
  Widget build(BuildContext context) {
    width = MediaQuery.sizeOf(context).width;
    final stack = Stack(
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
              final visible =
                  current || ((dragging || !clock.isCompleted) && alpha > .001);
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
                        child: PaperLeaf(
                          amount: 1 - alpha.clamp(0, 1),
                          reverse: hinges[index] ?? dx > 0,
                          child: child!,
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
    return widget.onSelected == null
        ? stack
        : Listener(
            onPointerCancel: (_) => endDrag(),
            child: GestureDetector(
              onHorizontalDragStart: beginDrag,
              onHorizontalDragUpdate: updateDrag,
              onHorizontalDragEnd: endDrag,
              onHorizontalDragCancel: () => endDrag(),
              child: stack,
            ),
          );
  }
}
