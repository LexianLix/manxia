import 'package:flutter/material.dart';

/// A shared rhythm: direct manipulation, short feedback, then spatial travel.
abstract final class RoomMotion {
  static const press = Duration(milliseconds: 110);
  static const feedback = Duration(milliseconds: 180);
  static const page = Duration(milliseconds: 260);
  static const arrival = Duration(milliseconds: 420);
  static const book = Duration(milliseconds: 760);
  static const bookReturn = Duration(milliseconds: 580);
  static const flight = Duration(milliseconds: 440);
  static const settle = SpringDescription(mass: 1, stiffness: 360, damping: 32);
  static const ease = Cubic(.22, 1, .36, 1);
  static const travel = Cubic(.2, .75, .25, 1);

  static Duration duration(BuildContext context, Duration value) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : value;
}

/// Shared by ordinary routes so reading, downloads and library management
/// enter and return with the same rhythm. System reduced motion is immediate.
class RoomPageTransitions extends PageTransitionsBuilder {
  const RoomPageTransitions();
  @override
  Duration get transitionDuration => RoomMotion.page;
  @override
  Duration get reverseTransitionDuration => RoomMotion.page;

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
      animation: animation,
      child: child,
      builder: (_, child) {
        final t = RoomMotion.ease.transform(animation.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(18 * (1 - t), 0),
            child: child,
          ),
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
