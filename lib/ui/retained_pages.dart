import 'package:flutter/material.dart';

/// Only visited pages are created. Inactive scenes retain state and images,
/// but do not paint or tick; transitions animate their retained layer.
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
    duration: const Duration(milliseconds: 280),
    value: 1,
  );
  late final visited = <int>{widget.index};
  int? previous;
  int direction = 1;
  @override
  void didUpdateWidget(RetainedPages old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      visited.add(widget.index);
      previous = old.index;
      direction = widget.index > old.index ? 1 : -1;
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
            final visible =
                current || (index == previous && !clock.isCompleted);
            final t = Curves.easeOutCubic.transform(clock.value);
            return Offstage(
              offstage: !visible,
              child: TickerMode(
                enabled: visible,
                child: ExcludeSemantics(
                  excluding: !current,
                  child: IgnorePointer(
                    ignoring: !current,
                    child: Opacity(
                      opacity: current ? t : 1 - t,
                      child: Transform.translate(
                        offset: Offset(
                          current
                              ? 24 * direction * (1 - t)
                              : -16 * direction * t,
                          0,
                        ),
                        child: child,
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
