import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/data/frame_monitor.dart';

FrameTiming frame(int build, int raster) => FrameTiming(
  vsyncStart: 0,
  buildStart: 0,
  buildFinish: build,
  rasterStart: build,
  rasterFinish: build + raster,
  rasterFinishWallTime: build + raster,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'recording skips old batches, stops in background and freezes its report',
    (tester) async {
      final monitor = FrameMonitor();
      addTearDown(monitor.dispose);
      monitor.start(120);
      monitor.ingest([frame(999999, 999999)]);
      monitor.ingest([
        frame(2000, 3000),
        frame(9000, 2000),
        frame(1000, 10000),
      ]);
      monitor.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(monitor.recording, false);
      final report = monitor.report!;
      expect(report.samples, hasLength(3));
      expect(report.slowFrames, 2);
      expect(report.toJson()['rasterP95Ms'], 10);
      monitor.ingest([frame(500000, 500000)]);
      expect(report.samples, hasLength(3));
      monitor.start(60);
      expect(monitor.report, isNull);
      await tester.pump(const Duration(seconds: 20));
      expect(monitor.recording, false);
      expect(monitor.report!.samples, isEmpty);
      expect(report.samples, hasLength(3));
    },
  );
  test(
    'pipeline phases use their own budget rather than summing overlapped work',
    () {
      final report = FrameReport(60, [(build: 10000, raster: 10000)]);
      expect(report.slowFrames, 0);
    },
  );
}
