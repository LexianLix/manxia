import 'package:flutter/material.dart';
import 'room_motion.dart';

/// Shared touch friction and edge settling for the shelf, discovery, detail
/// and reader. Wheel/trackpad deltas remain direct; no delayed scroll queue.
class RoomScrollBehavior extends MaterialScrollBehavior {
  const RoomScrollBehavior();
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context)
      ? const ClampingScrollPhysics()
      : const RoomScrollPhysics();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}

class RoomScrollPhysics extends BouncingScrollPhysics {
  const RoomScrollPhysics({super.parent});
  @override
  SpringDescription get spring => RoomMotion.settle;
  @override
  RoomScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      RoomScrollPhysics(parent: buildParent(ancestor));
}
