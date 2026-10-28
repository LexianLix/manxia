import 'dart:math' as math;
import 'package:flutter/physics.dart';

/// A shallow ring: depth changes the scale and yaw, never the cover's width.
class ShelfOrbitPose {
  ShelfOrbitPose(double distance, int period) {
    final angle = distance * math.pi * 2 / period;
    depth = math.cos(angle);
    horizontal = math.sin(angle);
    vertical = (1 - depth) * 9;
    scale = .78 + .22 * (depth + 1) / 2;
    yaw = -horizontal * .28;
    final visible = ((depth + .35) / .7).clamp(0.0, 1.0);
    opacity = period <= 4 ? .32 + .68 * visible : visible;
  }
  late final double depth, horizontal, vertical, scale, yaw, opacity;
}

/// Coasting and settling share position and velocity at their boundary. A new
/// pointer can stop this single simulation without delayed callbacks winning.
class ShelfGlideSimulation extends Simulation {
  ShelfGlideSimulation(double start, double velocity)
    : super(tolerance: const Tolerance(distance: .002, velocity: .01)) {
    final speed = velocity.clamp(-24.0, 24.0);
    friction = FrictionSimulation(.08, start, speed);
    coastDuration = speed.abs() <= 2
        ? 0
        : (math.log(speed.abs() / 2) / -math.log(.08)).clamp(0.0, 1.2);
    final end = friction.x(coastDuration);
    final carried = friction.dx(coastDuration);
    target = (end + carried * .12).roundToDouble();
    settling = SpringSimulation(
      const SpringDescription(mass: 1, stiffness: 105, damping: 21),
      end,
      target,
      carried,
      tolerance: tolerance,
    );
  }
  late final FrictionSimulation friction;
  late final SpringSimulation settling;
  late final double coastDuration, target;
  @override
  double x(double time) => time < coastDuration
      ? friction.x(time)
      : settling.isDone(time - coastDuration)
      ? target
      : settling.x(time - coastDuration);
  @override
  double dx(double time) => time < coastDuration
      ? friction.dx(time)
      : settling.isDone(time - coastDuration)
      ? 0
      : settling.dx(time - coastDuration);
  @override
  bool isDone(double time) =>
      time >= coastDuration && settling.isDone(time - coastDuration);
}
