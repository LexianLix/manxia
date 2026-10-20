import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../data/comic.dart';
import '../data/library.dart';
import 'book_object.dart';

Future<void> collectWithMotion(
  BuildContext context,
  Comic comic,
  Library library,
  bool web,
) async {
  final adding = !library.contains(comic);
  if (adding && library.motion && !MediaQuery.disableAnimationsOf(context)) {
    final overlay = Overlay.of(context);
    final size = MediaQuery.sizeOf(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => IgnorePointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 620),
          onEnd: () => entry.remove(),
          builder: (c, t, _) {
            final eased = Curves.easeInOutCubic.transform(t);
            final start = Offset(size.width * .5 - 38, size.height * .48 - 55);
            final end = Offset(
              size.width < 1000 ? size.width * .15 : 64,
              size.height < 700 ? size.height - 65 : 80,
            );
            final point =
                Offset.lerp(start, end, eased)! -
                Offset(0, math.sin(t * math.pi) * 100);
            return Stack(
              children: [
                Positioned(
                  left: point.dx,
                  top: point.dy,
                  width: 76,
                  height: 110,
                  child: Opacity(
                    opacity: (1 - t * t).clamp(0, 1),
                    child: Transform.rotate(
                      angle: t * .25,
                      child: Transform.scale(
                        scale: 1 - eased * .7,
                        child: Material(
                          elevation: 12,
                          child: ComicCover(comic, web: web),
                        ),
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
  }
  await library.toggle(comic);
}
