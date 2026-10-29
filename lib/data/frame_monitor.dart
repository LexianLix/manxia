import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

class FrameReport {
  FrameReport(this.refreshRate, List<({int build, int raster})> values)
    : samples = List.unmodifiable(values);
  final double refreshRate;
  final List<({int build, int raster})> samples;
  double get budgetMs => 1000 / refreshRate;
  double percentile(Iterable<int> values) {
    final sorted = values.toList()..sort();
    return sorted.isEmpty
        ? 0
        : sorted[((sorted.length - 1) * .95).ceil()] / 1000;
  }

  int get slowFrames => samples
      .where((s) => math.max(s.build, s.raster) / 1000 > budgetMs)
      .length;
  Map<String, Object> toJson() => {
    'scope':
        'Flutter build/raster timings; not display FPS or thermal measurements',
    'mode': kReleaseMode
        ? 'release'
        : kProfileMode
        ? 'profile'
        : 'debug',
    'refreshRateHz': refreshRate,
    'samples': samples.length,
    'frameBudgetMs': budgetMs,
    'buildP95Ms': percentile(samples.map((s) => s.build)),
    'rasterP95Ms': percentile(samples.map((s) => s.raster)),
    'overBudgetFrames': slowFrames,
  };
}

/// Opt-in, memory-only recording. Does not retain titles, URLs or device IDs.
class FrameMonitor extends ChangeNotifier with WidgetsBindingObserver {
  static final shared = FrameMonitor();
  bool recording = false, _skipBatch = true;
  double _rate = 60;
  final _samples = <({int build, int raster})>[];
  Timer? _timer;
  FrameReport? report;

  void start(double refreshRate) {
    stop();
    _rate = refreshRate.isFinite && refreshRate >= 30 && refreshRate <= 240
        ? refreshRate
        : 60;
    report = null;
    _samples.clear();
    _skipBatch = true;
    recording = true;
    WidgetsBinding.instance.addObserver(this);
    SchedulerBinding.instance.addTimingsCallback(ingest);
    _timer = Timer(const Duration(seconds: 20), stop);
    notifyListeners();
  }

  void ingest(List<FrameTiming> timings) {
    if (!recording) return;
    // The first engine batch may contain frames queued before recording began.
    if (_skipBatch) {
      _skipBatch = false;
      return;
    }
    for (final frame in timings) {
      if (_samples.length >= 4800) break;
      _samples.add((
        build: frame.buildDuration.inMicroseconds,
        raster: frame.rasterDuration.inMicroseconds,
      ));
    }
  }

  void stop() {
    if (!recording) return;
    recording = false;
    _timer?.cancel();
    SchedulerBinding.instance.removeTimingsCallback(ingest);
    WidgetsBinding.instance.removeObserver(this);
    report = FrameReport(_rate, _samples);
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) stop();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
