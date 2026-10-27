import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'room_motion.dart';

/// Retains visited document sections without giving every section the height
/// of the longest one. A retarget begins at the currently painted poses.
class RetainedSections extends StatefulWidget {
  const RetainedSections({
    super.key,
    required this.index,
    required this.builder,
    required this.order,
    this.animate = true,
  });
  final String index;
  final List<String> order;
  final Widget Function(String) builder;
  final bool animate;
  @override
  State<RetainedSections> createState() => _RetainedSectionsState();
}

class _RetainedSectionsState extends State<RetainedSections>
    with SingleTickerProviderStateMixin {
  late final clock = AnimationController(
    vsync: this,
    duration: RoomMotion.page,
    value: 1,
  );
  late final visited = <String>{widget.index};
  final starts = <String, (double, double)>{};
  final ends = <String, (double, double)>{};
  bool get animate =>
      widget.animate && !MediaQuery.disableAnimationsOf(context);
  (double, double) pose(String id) {
    final end = ends[id] ?? (id == widget.index ? 1.0 : 0.0, 0.0);
    final start = starts[id] ?? end;
    final t = RoomMotion.ease.transform(clock.value);
    return (
      start.$1 + (end.$1 - start.$1) * t,
      start.$2 + (end.$2 - start.$2) * t,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!animate) clock.value = 1;
  }

  @override
  void didUpdateWidget(RetainedSections old) {
    super.didUpdateWidget(old);
    if (old.index == widget.index) {
      if (!animate) clock.value = 1;
      return;
    }
    ends.putIfAbsent(old.index, () => (1, 0));
    final before = {for (final id in visited) id: pose(id)};
    final direction =
        widget.order.indexOf(widget.index) >= widget.order.indexOf(old.index)
        ? 1.0
        : -1.0;
    visited.add(widget.index);
    for (final id in visited) {
      starts[id] = before[id] ?? (0, direction * 12);
      ends[id] = id == widget.index ? (1, 0) : (0, -direction * 12);
    }
    if (animate) {
      clock.forward(from: 0);
    } else {
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
    final ids = visited.toList();
    // These subtrees remain identical throughout clock ticks. In particular,
    // grids and source parsers are not rebuilt once per animation frame.
    final children = [
      for (final id in ids)
        KeyedSubtree(key: ValueKey(id), child: widget.builder(id)),
    ];
    return AnimatedBuilder(
      animation: clock,
      builder: (_, _) {
        final poses = ids.map(pose).toList();
        return _SectionLayout(
          selected: ids.indexOf(widget.index),
          weights: poses.map((p) => p.$1).toList(),
          children: [
            for (var i = 0; i < ids.length; i++)
              TickerMode(
                key: ValueKey(ids[i]),
                enabled: poses[i].$1 > .001,
                child: IgnorePointer(
                  ignoring: ids[i] != widget.index,
                  child: ExcludeSemantics(
                    excluding: ids[i] != widget.index,
                    child: ExcludeFocus(
                      excluding: ids[i] != widget.index,
                      child: Opacity(
                        // Fade through a shared paper surface: two text-heavy
                        // sections must never be legible over each other.
                        // Height still follows the continuous section weights.
                        opacity: poses[i].$1.clamp(0, 1),
                        child: Transform.translate(
                          offset: Offset(
                            poses[i].$2 / 3,
                            poses[i].$2.abs() * .6,
                          ),
                          child: RepaintBoundary(child: children[i]),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SectionLayout extends MultiChildRenderObjectWidget {
  const _SectionLayout({
    required this.selected,
    required this.weights,
    required super.children,
  });
  final int selected;
  final List<double> weights;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _SectionBox(selected, weights);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant _SectionBox renderObject,
  ) => renderObject.update(selected, weights);
}

class _SectionParentData extends ContainerBoxParentData<RenderBox> {}

class _SectionBox extends RenderBox
    with
        ContainerRenderObjectMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        >,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        > {
  _SectionBox(this.selected, this.weights);
  int selected;
  List<double> weights;
  void update(int index, List<double> values) {
    selected = index;
    weights = values;
    markNeedsLayout();
    markNeedsSemanticsUpdate();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! ContainerBoxParentData<RenderBox>) {
      child.parentData = _SectionParentData();
    }
  }

  @override
  void performLayout() {
    var height = 0.0, index = 0;
    RenderBox? child = firstChild;
    while (child != null) {
      child.layout(
        BoxConstraints.tightFor(width: constraints.maxWidth),
        parentUsesSize: true,
      );
      height += child.size.height * weights[index++];
      child =
          (child.parentData! as ContainerBoxParentData<RenderBox>).nextSibling;
    }
    size = constraints.constrain(Size(constraints.maxWidth, height));
  }

  @override
  void paint(PaintingContext context, Offset offset) => context.pushClipRect(
    needsCompositing,
    offset,
    Offset.zero & size,
    defaultPaint,
  );
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    RenderBox? child = firstChild;
    for (var i = 0; child != null; i++) {
      if (i == selected) {
        return weights[i] > .55 && child.hitTest(result, position: position);
      }
      child =
          (child.parentData! as ContainerBoxParentData<RenderBox>).nextSibling;
    }
    return false;
  }
}
