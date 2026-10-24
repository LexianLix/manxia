import 'package:flutter/material.dart';
import 'room_motion.dart';

/// Current content determines the target height. Retiring content cannot
/// receive a second tap or remain in accessibility traversal during the fade.
class ContentHandoff extends StatelessWidget {
  const ContentHandoff({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return AnimatedSize(
      alignment: Alignment.topLeft,
      duration: RoomMotion.feedback,
      curve: RoomMotion.ease,
      child: AnimatedSwitcher(
        duration: RoomMotion.feedback,
        switchInCurve: Curves.linear,
        switchOutCurve: Curves.linear,
        transitionBuilder: (child, animation) {
          final opacity = animation.drive(
            CurveTween(curve: const Interval(.5, 1, curve: RoomMotion.ease)),
          );
          return AnimatedBuilder(
            animation: animation,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, .035),
                end: Offset.zero,
              ).chain(CurveTween(curve: RoomMotion.ease)).animate(animation),
              child: child,
            ),
            builder: (_, body) => IgnorePointer(
              ignoring: animation.value < .55,
              child: ExcludeSemantics(
                excluding: animation.value < .55,
                child: FadeTransition(opacity: opacity, child: body),
              ),
            ),
          );
        },
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topLeft,
          children: [
            for (final old in previous)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(child: ExcludeSemantics(child: old)),
              ),
            ?current,
          ],
        ),
        child: child,
      ),
    );
  }
}
