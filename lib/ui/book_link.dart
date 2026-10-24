import 'package:flutter/material.dart';
import '../data/comic.dart';
import 'book_object.dart';

/// Each visible occurrence owns its flight identity, even when one book occurs
/// in several recommendation sections. Only the tapped identity is consumed.
class BookLink extends StatefulWidget {
  const BookLink({
    super.key,
    required this.comic,
    required this.web,
    required this.onOpen,
    required this.builder,
    this.cover,
  });
  final Comic comic;
  final bool web;
  final ValueChanged<Comic> onOpen;
  final Widget Function(Widget cover, VoidCallback open) builder;
  final Widget? cover;
  static final _origins = Expando<(String, Object)>();
  static Object? takeTag(BuildContext context, Comic comic) {
    final navigator = Navigator.of(context);
    final origin = _origins[navigator];
    _origins[navigator] = null;
    return origin?.$1 == comic.path ? origin!.$2 : null;
  }

  @override
  State<BookLink> createState() => _BookLinkState();
}

class _BookLinkState extends State<BookLink> {
  final tag = Object();
  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final cover = widget.cover ?? ComicCover(widget.comic, web: widget.web);
    return widget.builder(
      reduced
          ? cover
          : Hero(
              tag: tag,
              curve: Curves.linear,
              reverseCurve: Curves.linear,
              createRectTween: (begin, end) =>
                  BookTravelRectTween(begin: begin, end: end),
              flightShuttleBuilder: BookFlight.shuttle(
                widget.comic,
                widget.web,
              ),
              child: cover,
            ),
      () {
        if (!reduced) {
          BookLink._origins[Navigator.of(context)] = (widget.comic.path, tag);
        }
        widget.onOpen(widget.comic);
      },
    );
  }
}
