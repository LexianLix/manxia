import 'package:flutter/material.dart';
import 'room_motion.dart';

/// One virtual sliver remains laid out at a time. Swap while invisible rather
/// than expanding both catalogs or retaining every combination of filters.
class SliverHandoff extends StatefulWidget {
  const SliverHandoff({
    super.key,
    required this.identity,
    required this.sliver,
    this.animate = true,
  });
  final Object identity;
  final Widget sliver;
  final bool animate;
  @override
  State<SliverHandoff> createState() => _SliverHandoffState();
}

class _SliverHandoffState extends State<SliverHandoff>
    with SingleTickerProviderStateMixin {
  late final clock = AnimationController(
    vsync: this,
    value: 1,
    duration: RoomMotion.feedback ~/ 2,
  )..addStatusListener(settle);
  late final opacity = CurvedAnimation(parent: clock, curve: RoomMotion.ease);
  late Object current = widget.identity;
  late Widget displayed = widget.sliver;
  (Object, Widget)? pending;
  bool get animate =>
      widget.animate && !MediaQuery.disableAnimationsOf(context);
  void commit() {
    final target = pending;
    if (target == null) return;
    current = target.$1;
    displayed = target.$2;
    pending = null;
  }

  void settle(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && pending != null) {
      setState(commit);
      clock.forward();
    }
  }

  void immediate() {
    pending = null;
    current = widget.identity;
    displayed = widget.sliver;
    clock.value = 1;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!animate) immediate();
  }

  @override
  void didUpdateWidget(SliverHandoff old) {
    super.didUpdateWidget(old);
    if (!animate) {
      immediate();
      return;
    }
    if (widget.identity == current) {
      pending = null;
      displayed = widget.sliver;
      clock.forward();
      return;
    }
    pending = (widget.identity, widget.sliver);
    if (clock.value == 0) {
      commit();
      clock.forward();
    } else {
      clock.reverse();
    }
  }

  @override
  void dispose() {
    opacity.dispose();
    clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: clock,
    child: displayed,
    builder: (_, child) => SliverIgnorePointer(
      ignoring: current != widget.identity || clock.isAnimating,
      sliver: SliverFadeTransition(opacity: opacity, sliver: child!),
    ),
  );
}
