import 'package:flutter/material.dart';
import 'room_motion.dart';

/// The paper remains painted until a decoded frame is visible. A bounded set of
/// identities prevents recycled covers from repeatedly replaying their arrival.
class CoverArrival extends StatefulWidget {
  const CoverArrival({
    super.key,
    required this.identity,
    required this.ready,
    required this.placeholder,
    required this.child,
    this.immediate = false,
  });
  final String identity;
  final bool ready, immediate;
  final Widget placeholder, child;
  static final _presented = <String>{};
  static bool hasPresented(String identity) => _presented.contains(identity);
  static void markPresented(String identity) {
    _presented.remove(identity);
    _presented.add(identity);
    while (_presented.length > 256) {
      _presented.remove(_presented.first);
    }
  }

  @override
  State<CoverArrival> createState() => _CoverArrivalState();
}

class _CoverArrivalState extends State<CoverArrival>
    with SingleTickerProviderStateMixin {
  late final clock = AnimationController(
    vsync: this,
    duration: RoomMotion.cover,
  );
  bool started = false;
  void remember() {
    CoverArrival.markPresented(widget.identity);
  }

  void prepare() {
    if (!widget.ready) return;
    if (widget.immediate ||
        MediaQuery.disableAnimationsOf(context) ||
        CoverArrival.hasPresented(widget.identity)) {
      clock.value = 1;
      started = true;
      remember();
    } else if (!started) {
      started = true;
      clock.forward();
    }
  }

  @override
  void initState() {
    super.initState();
    clock.addStatusListener((status) {
      if (status == AnimationStatus.completed) remember();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    prepare();
  }

  @override
  void didUpdateWidget(CoverArrival old) {
    super.didUpdateWidget(old);
    if (old.identity != widget.identity || (old.ready && !widget.ready)) {
      clock.stop();
      clock.value = 0;
      started = false;
    }
    prepare();
  }

  @override
  void dispose() {
    clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: clock,
    child: widget.child,
    builder: (context, child) {
      if (!widget.ready) return widget.placeholder;
      if (clock.value == 1) return child!;
      final t = RoomMotion.ease.transform(clock.value);
      return ClipRect(
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            widget.placeholder,
            Positioned.fill(
              child: Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(0, 4 * (1 - t)),
                  child: child,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
