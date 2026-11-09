import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../data/frame_budget.dart';
import 'materials.dart';

/// Budgets expensive material passes using real engine build/raster timings,
/// rather than a device-name blacklist or a permanent preference downgrade.
class AdaptiveGlass extends StatefulWidget {
  const AdaptiveGlass({super.key, required this.high, required this.child});
  final bool high;
  final Widget child;
  @override
  State<AdaptiveGlass> createState() => _AdaptiveGlassState();
}

class _AdaptiveGlassState extends State<AdaptiveGlass>
    with WidgetsBindingObserver {
  final budget = FrameBudget();
  bool listening = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    listen(widget.high);
  }

  void listen(bool enabled) {
    if (enabled == listening) return;
    listening = enabled;
    if (enabled) {
      SchedulerBinding.instance.addTimingsCallback(record);
    } else {
      SchedulerBinding.instance.removeTimingsCallback(record);
      budget.pause();
    }
  }

  void record(List<FrameTiming> frames) {
    if (!listening) return;
    for (final frame in frames) {
      budget.observe(
        frame.buildDuration.inMicroseconds,
        frame.rasterDuration.inMicroseconds,
      );
    }
  }

  @override
  void didUpdateWidget(AdaptiveGlass old) {
    super.didUpdateWidget(old);
    listen(
      widget.high &&
          (WidgetsBinding.instance.lifecycleState == null ||
              WidgetsBinding.instance.lifecycleState ==
                  AppLifecycleState.resumed),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      listen(widget.high && state == AppLifecycleState.resumed);
  @override
  void dispose() {
    listen(false);
    WidgetsBinding.instance.removeObserver(this);
    budget.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: budget,
    child: widget.child,
    builder: (_, tier, child) => GlassPerformanceScope(
      high: widget.high,
      refraction: tier == 0,
      blurScale: tier == 0
          ? 1
          : tier == 1
          ? .65
          : .4,
      child: child!,
    ),
  );
}
