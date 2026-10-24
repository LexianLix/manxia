import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../data/comic.dart';
import '../data/dm5_source.dart';
import '../data/library.dart';
import 'detail_page.dart';
import 'living_shelf.dart';
import 'room_motion.dart';

/// Every result, including an alternative source, opens with the same book
/// route. The tapped Hero tag remains owned by the still-visible source page.
PageRoute<void> comicDetailRoute(
  BuildContext context, {
  required Comic comic,
  required Library library,
  required Dm5Source source,
  required bool web,
  Object? flightTag,
  Rect? origin,
}) {
  final animate = library.motion && !MediaQuery.disableAnimationsOf(context);
  return PageRouteBuilder<void>(
    opaque: false,
    transitionDuration: animate ? RoomMotion.book : Duration.zero,
    reverseTransitionDuration: animate ? RoomMotion.bookReturn : Duration.zero,
    pageBuilder: (_, _, _) => DetailPage(
      comic: comic,
      library: library,
      source: source,
      web: web,
      flightTag: flightTag,
      bookNumber: math.max(
        1,
        library.books.indexWhere((b) => b.path == comic.path) + 1,
      ),
    ),
    transitionsBuilder: (_, animation, _, child) => OpenBookTransition(
      animation: animation,
      comic: comic,
      web: web,
      origin: origin,
      child: child,
    ),
  );
}
