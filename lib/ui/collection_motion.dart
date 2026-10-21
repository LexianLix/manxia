import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../data/comic.dart';
import '../data/library.dart';
import 'book_object.dart';
import 'room_motion.dart';

final _flights = Expando<Map<String, OverlayEntry>>();

Future<void> collectWithMotion(
  BuildContext context,
  Comic comic,
  Library library,
  bool web, {
  Rect? origin,
}) async {
  final flights = _flights[library] ??= <String, OverlayEntry>{};
  final prior = flights.remove(comic.path);
  if (prior != null) {
    prior.remove();
    prior.dispose();
  }
  final adding = !library.contains(comic);
  if (adding && library.motion && !MediaQuery.disableAnimationsOf(context)) {
    final overlay = Overlay.of(context);
    final size = MediaQuery.sizeOf(context);
    final safe = MediaQuery.paddingOf(context);
    final navWidth = math.min(size.width - 40, 420.0);
    final destination = size.width < 1000
        ? Offset(
            (size.width - navWidth) / 2 + 7 + (navWidth - 14) / 8,
            size.height - safe.bottom - 52,
          )
        : Offset(53, safe.top + 188);
    final start = origin?.center ?? Offset(size.width / 2, size.height * .42);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => IgnorePointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: RoomMotion.flight,
          onEnd: () {
            if (identical(flights[comic.path], entry)) {
              flights.remove(comic.path);
              entry.remove();
              entry.dispose();
            }
          },
          child: Material(elevation: 8, child: ComicCover(comic, web: web)),
          builder: (c, t, child) {
            final eased = RoomMotion.travel.transform(t);
            final point =
                Offset.lerp(start, destination, eased)! -
                Offset(0, math.sin(t * math.pi) * 60);
            return Stack(
              children: [
                Positioned(
                  left: point.dx - 38,
                  top: point.dy - 55,
                  width: 76,
                  height: 110,
                  child: Opacity(
                    opacity: (1 - ((t - .65) / .35).clamp(0, 1)),
                    child: Transform.rotate(
                      angle: t * .25,
                      child: Transform.scale(
                        scale: 1 - eased * .7,
                        child: child,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
    overlay.insert(entry);
    flights[comic.path] = entry;
  }
  await library.toggle(comic);
}
