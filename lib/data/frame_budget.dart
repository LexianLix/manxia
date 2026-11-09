import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// Session-only effect budgeting. It never changes the saved quality setting.
/// A short bad window sheds optical passes; recovery needs ten seconds of good
/// rendered frames per step so the material does not flicker between qualities.
class FrameBudget extends ValueNotifier<int> {
  FrameBudget() : super(0);
  int frames = 0, slow = 0, severe = 0, healthy = 0;

  void observe(int buildMicros, int rasterMicros) {
    final cost = math.max(buildMicros, rasterMicros);
    frames++;
    if (cost > 16667) slow++;
    if (cost > 33333) severe++;
    if (frames < 20) return;
    if (slow >= 8 || severe >= 3) {
      healthy = 0;
      if (value < 2) value++;
    } else if (slow <= 1) {
      healthy += frames;
      if (healthy >= 600) {
        healthy = 0;
        if (value > 0) value--;
      }
    } else {
      healthy = 0;
    }
    frames = slow = severe = 0;
  }

  void pause() {
    frames = slow = severe = healthy = 0;
  }
}
