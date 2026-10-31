import 'package:flutter/material.dart';
import 'room_motion.dart';

class ReaderZoomAnimation {
  ReaderZoomAnimation(TickerProvider vsync, this.viewport) {
    clock = AnimationController(vsync: vsync, duration: RoomMotion.feedback)
      ..addListener(
        () => viewport.value = Matrix4Tween(
          begin: from,
          end: target,
        ).transform(RoomMotion.ease.transform(clock.value)),
      );
  }
  final TransformationController viewport;
  late final AnimationController clock;
  Matrix4 from = Matrix4.identity(), target = Matrix4.identity();
  void stop() => clock.stop();
  void finish() {
    if (clock.isAnimating) {
      clock.stop();
      viewport.value = Matrix4.copy(target);
    }
  }

  void animate(Matrix4 value, bool reduced) {
    clock.stop();
    from = Matrix4.copy(viewport.value);
    target = value;
    if (reduced) {
      viewport.value = Matrix4.copy(value);
    } else {
      clock.forward(from: 0);
    }
  }

  void toggle(Offset point, bool reduced) {
    final scale = viewport.value.getMaxScaleOnAxis() > 1.01 ? 1.0 : 2.4;
    animate(
      Matrix4.identity()
        ..translateByDouble(
          -point.dx * (scale - 1),
          -point.dy * (scale - 1),
          0,
          1,
        )
        ..scaleByDouble(scale, scale, 1, 1),
      reduced,
    );
  }

  void dispose() => clock.dispose();
}
