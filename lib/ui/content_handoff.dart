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
        switchInCurve: RoomMotion.ease,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, .035),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
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
