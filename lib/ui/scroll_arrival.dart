import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'room_motion.dart';

/// Reveal on first paint inside the viewport, rather than when the full
/// shrink-wrapped catalog is built. Its short-lived scroll listener detaches
/// after the first reveal; there is no polling or permanent animation ticker.
class ScrollArrival extends StatefulWidget {
  const ScrollArrival({super.key, required this.identity, required this.child});
  final String identity;
  final Widget child;
  static final _seen = <String>{};
  @override
  State<ScrollArrival> createState() => _ScrollArrivalState();
}

class _ScrollArrivalState extends State<ScrollArrival>
    with SingleTickerProviderStateMixin {
  late final clock = AnimationController(
    vsync: this,
    duration: RoomMotion.scene,
    value: ScrollArrival._seen.contains(widget.identity) ? 1 : 0,
  );
  bool queued = false;
  ScrollPosition? position;
  void scrolled() => context.findRenderObject()?.markNeedsPaint();
  void reveal() {
    if (queued || clock.value == 1) return;
    queued = true;
    position?.removeListener(scrolled);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScrollArrival._seen.add(widget.identity);
      if (ScrollArrival._seen.length > 512) {
        ScrollArrival._seen.remove(ScrollArrival._seen.first);
      }
      if (MediaQuery.disableAnimationsOf(context)) {
        clock.value = 1;
      } else {
        clock.forward();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    position?.removeListener(scrolled);
    position = Scrollable.maybeOf(context)?.position;
    if (MediaQuery.disableAnimationsOf(context)) {
      clock.value = 1;
    } else if (!queued && clock.value < 1) {
      position?.addListener(scrolled);
    }
  }

  @override
  void didUpdateWidget(ScrollArrival old) {
    super.didUpdateWidget(old);
    if (old.identity != widget.identity) {
      queued = false;
      clock.value =
          ScrollArrival._seen.contains(widget.identity) ||
              MediaQuery.disableAnimationsOf(context)
          ? 1
          : 0;
      position?.removeListener(scrolled);
      if (clock.value < 1) position?.addListener(scrolled);
    }
  }

  @override
  void dispose() {
    position?.removeListener(scrolled);
    clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _PaintArrival(
    key: ValueKey(widget.identity),
    onVisible: reveal,
    child: RepaintBoundary(
      child: AnimatedBuilder(
        animation: clock,
        child: widget.child,
        builder: (_, child) {
          final t = RoomMotion.ease.transform(clock.value);
          return Transform.translate(
            offset: Offset(0, 12 * (1 - t)),
            child: Opacity(opacity: .35 + .65 * t, child: child!),
          );
        },
      ),
    ),
  );
}

class _PaintArrival extends SingleChildRenderObjectWidget {
  const _PaintArrival({
    super.key,
    required this.onVisible,
    required super.child,
  });
  final VoidCallback onVisible;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _ArrivalBox(onVisible);
  @override
  void updateRenderObject(BuildContext context, _ArrivalBox renderObject) =>
      renderObject.onVisible = onVisible;
}

class _ArrivalBox extends RenderProxyBox {
  _ArrivalBox(this.onVisible);
  VoidCallback onVisible;
  bool reported = false;
  @override
  void paint(PaintingContext context, Offset offset) {
    final viewport = reported ? null : RenderAbstractViewport.maybeOf(this);
    if (!reported &&
        (viewport == null ||
            MatrixUtils.transformRect(
              getTransformTo(viewport),
              paintBounds,
            ).overlaps(viewport.paintBounds))) {
      reported = true;
      onVisible();
    }
    super.paint(context, offset);
  }
}
