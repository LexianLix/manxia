import 'package:flutter/material.dart';

/// A shared rhythm: direct manipulation, short feedback, then spatial travel.
abstract final class RoomMotion {
  static const press = Duration(milliseconds: 110);
  static const feedback = Duration(milliseconds: 180);
  static const page = Duration(milliseconds: 340);
  static const scene = Duration(milliseconds: 240);
  static const arrival = Duration(milliseconds: 420);
  static const cover = Duration(milliseconds: 320);
  static const book = Duration(milliseconds: 620);
  static const bookReturn = Duration(milliseconds: 500);
  static const flight = Duration(milliseconds: 440);
  static const settle = SpringDescription(mass: 1, stiffness: 360, damping: 32);
  static const ease = Cubic(.22, 1, .36, 1);
  static const travel = Cubic(.2, .75, .25, 1);

  static Duration duration(BuildContext context, Duration value) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : value;

  static AnimationStyle sheet(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context)
      ? AnimationStyle.noAnimation
      : const AnimationStyle(
          duration: page,
          reverseDuration: feedback,
          curve: ease,
          reverseCurve: ease,
        );
}

/// Shared by ordinary routes so reading, downloads and library management
/// enter and return with the same rhythm. System reduced motion is immediate.
class RoomPageTransitions extends PageTransitionsBuilder {
  const RoomPageTransitions();
  @override
  Duration get transitionDuration => RoomMotion.scene;
  @override
  Duration get reverseTransitionDuration => RoomMotion.scene;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return AnimatedBuilder(
      animation: Listenable.merge([animation, secondaryAnimation]),
      child: child,
      builder: (_, child) {
        final t = RoomMotion.ease.transform(animation.value);
        final depth = RoomMotion.ease.transform(secondaryAnimation.value);
        return Transform.translate(
          offset: Offset(0, 16 * (1 - t) - 4 * depth),
          child: Opacity(opacity: t, child: child!),
        );
      },
    );
  }
}

/// Keeps the reading viewport fixed while chrome slides over its edges.
class ReaderChrome extends StatelessWidget {
  const ReaderChrome({
    super.key,
    required this.visible,
    required this.top,
    required this.child,
  });
  final bool visible, top;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: visible ? 1.0 : 0.0, end: visible ? 1.0 : 0.0),
    duration: RoomMotion.duration(context, RoomMotion.feedback),
    curve: RoomMotion.ease,
    child: child,
    builder: (_, t, child) => Offstage(
      offstage: t == 0,
      child: IgnorePointer(
        ignoring: !visible,
        child: ExcludeSemantics(
          excluding: !visible,
          child: FractionalTranslation(
            translation: Offset(0, (1 - t) * (top ? -1 : 1)),
            child: Opacity(opacity: t, child: child),
          ),
        ),
      ),
    ),
  );
}
