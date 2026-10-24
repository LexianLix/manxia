import 'localized_text.dart';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../data/comic.dart';
import 'comic_image.dart';
import 'cover_palette.dart';
import 'room_motion.dart';
import 'cover_arrival.dart';
export 'comic_image.dart' show imageAddress;

/// One book travels between the real shelf and detail bounds in both directions.
/// The same cover, numbering and material survive the flight.
class BookFlight extends StatelessWidget {
  const BookFlight({
    super.key,
    required this.child,
    this.enabled = true,
    this.tag,
  });
  final BookObject child;
  final bool enabled;
  final Object? tag;

  @override
  Widget build(BuildContext context) {
    if (!enabled || MediaQuery.disableAnimationsOf(context)) return child;
    return Hero(
      tag: tag ?? 'book-${child.comic.path}',
      curve: Curves.linear,
      reverseCurve: Curves.linear,
      createRectTween: (begin, end) => _BookRectTween(begin: begin, end: end),
      flightShuttleBuilder: shuttle(child.comic, child.web),
      child: child,
    );
  }

  static HeroFlightShuttleBuilder shuttle(
    Comic comic,
    bool web,
  ) => (_, animation, direction, from, to) {
    final fromChild = (from.widget as Hero).child;
    final toChild = (to.widget as Hero).child;
    final start = fromChild is BookObject
        ? fromChild
        : BookObject(comic, web: web);
    final end = toChild is BookObject ? toChild : BookObject(comic, web: web);
    final flat =
        (direction == HeroFlightDirection.push ? fromChild : toChild)
            is! BookObject;
    // The route's visual progress runs from one to zero on pop, while Hero
    // reverses its geometric endpoints. Keep the cover progress reversible.
    final source = direction == HeroFlightDirection.push ? start : end;
    final target = direction == HeroFlightDirection.push ? end : start;
    final sourceChild = direction == HeroFlightDirection.push
        ? fromChild
        : toChild;
    final targetChild = direction == HeroFlightDirection.push
        ? toChild
        : fromChild;
    final landsOnCover = targetChild is! BookObject;
    final hinge = targetChild is! _DetailComicCover || targetChild.opening;
    Widget stillCover(Widget child) => child is ComicCover
        ? ComicCover(
            child.comic,
            web: child.web,
            fit: child.fit,
            animate: false,
          )
        : child;
    final destinationContext = direction == HeroFlightDirection.push
        ? to
        : from;
    Widget destinationCover() => stillCover(
      destinationContext.mounted && destinationContext.widget is Hero
          ? (destinationContext.widget as Hero).child
          : targetChild,
    );
    if (landsOnCover && flat) {
      return AnimatedBuilder(
        animation: animation,
        builder: (_, _) => CoverHinge(
          progress: animation.value,
          opening: hinge,
          source: stillCover(sourceChild),
          destination: destinationCover(),
        ),
      );
    }
    return AnimatedBuilder(
      animation: animation,
      builder: (_, _) {
        final t = animation.value;
        final lift = math.sin(math.pi * t);
        final book = BookObject(
          comic,
          web: web,
          animateCover: false,
          number: t < .5 ? source.number : target.number,
          bookmark: t < .5 ? source.bookmark : target.bookmark,
          exposure: ui.lerpDouble(source.exposure, target.exposure, t)!,
          light: ui.lerpDouble(source.light, target.light, t)!,
          opening: landsOnCover
              ? (hinge ? .76 * math.sin(math.pi * t) : 0)
              : ui.lerpDouble(
                  source.opening,
                  target.opening,
                  const Interval(
                    .12,
                    .96,
                    curve: Curves.easeInOutCubic,
                  ).transform(t),
                )!,
        );
        final binding = RoomMotion.ease.transform((t / .2).clamp(0, 1));
        final reveal = landsOnCover
            ? RoomMotion.ease.transform(((t - .60) / .40).clamp(0, 1))
            : 0.0;
        final solid = Transform.rotate(
          angle: -.025 * lift,
          child: flat
              ? Stack(
                  fit: StackFit.expand,
                  clipBehavior: Clip.none,
                  children: [
                    Opacity(opacity: binding, child: book),
                    if (binding < 1)
                      Opacity(
                        opacity: 1 - binding,
                        child: stillCover(sourceChild),
                      ),
                  ],
                )
              : book,
        );
        return landsOnCover
            ? Stack(
                fit: StackFit.expand,
                children: [
                  if (reveal < 1) Opacity(opacity: 1 - reveal, child: solid),
                  if (reveal > 0)
                    Opacity(opacity: reveal, child: destinationCover()),
                ],
              )
            : solid;
      },
    );
  };
}

/// Flat entries keep the exact source and landing bounds. Paper leaves stay
/// behind a cover that pivots around its spine; no unrelated inner-page art is
/// substituted for the image during the flight.
class CoverHinge extends StatelessWidget {
  const CoverHinge({
    super.key,
    required this.progress,
    required this.source,
    required this.destination,
    this.opening = true,
  });
  final double progress;
  final Widget source, destination;
  final bool opening;
  @override
  Widget build(BuildContext context) {
    final lift = math.sin(math.pi * progress);
    final turn = const Interval(
      .05,
      .75,
      curve: Curves.easeInOutCubic,
    ).transform(progress);
    final angle = opening ? 2.55 * turn : 0.0;
    final departing =
        1 -
        const Interval(.55, .86, curve: RoomMotion.ease).transform(progress);
    final reveal = const Interval(
      .48,
      1,
      curve: RoomMotion.ease,
    ).transform(progress);
    Widget plane(double angle, Widget child) => Transform(
      alignment: Alignment.centerLeft,
      transform: Matrix4.identity()
        ..setEntry(3, 2, .0015)
        ..rotateY(angle),
      child: child,
    );
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        if (opening && lift > .001)
          for (var leaf = 0; leaf < 3; leaf++)
            Opacity(
              opacity: lift,
              child: plane(
                lift * (.14 + leaf * .13),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color.lerp(
                      const Color(0xfff8f5ec),
                      const Color(0xffe4e0d5),
                      leaf / 3,
                    ),
                    border: Border.all(
                      color: const Color(0xffd7d3c7),
                      width: .5,
                    ),
                  ),
                ),
              ),
            ),
        Opacity(opacity: reveal, child: destination),
        Opacity(
          opacity: departing,
          child: plane(
            angle,
            angle > math.pi / 2
                ? const ColoredBox(color: Color(0xfff8f5ec))
                : source,
          ),
        ),
      ],
    );
  }
}

/// The detail landing surface is the unaltered cover. The hinge belongs to
/// the reversible flight, rather than a permanent decorative open inner page.
class DetailCover extends StatelessWidget {
  const DetailCover(
    this.comic, {
    super.key,
    required this.web,
    this.tag,
    this.opening = true,
  });
  final Comic comic;
  final bool web;
  final Object? tag;
  final bool opening;

  @override
  Widget build(BuildContext context) {
    final cover = _DetailComicCover(comic, web: web, opening: opening);
    if (MediaQuery.disableAnimationsOf(context)) return cover;
    return Hero(
      tag: tag ?? 'book-${comic.path}',
      curve: Curves.linear,
      reverseCurve: Curves.linear,
      createRectTween: (begin, end) => _BookRectTween(begin: begin, end: end),
      flightShuttleBuilder: BookFlight.shuttle(comic, web),
      child: cover,
    );
  }
}

class _DetailComicCover extends ComicCover {
  const _DetailComicCover(
    super.comic, {
    required super.web,
    required this.opening,
  }) : super(fit: BoxFit.contain);
  final bool opening;
}

class _BookRectTween extends RectTween {
  _BookRectTween({super.begin, super.end});
  @override
  Rect? lerp(double t) => Rect.lerp(
    begin,
    end,
    const Interval(0, .82, curve: Curves.easeInOutCubic).transform(t),
  );
}

class ComicCover extends StatelessWidget {
  const ComicCover(
    this.comic, {
    super.key,
    required this.web,
    this.fit = BoxFit.cover,
    this.cacheWidth = 512,
    this.animate = true,
  });
  final Comic comic;
  final bool web;
  final BoxFit fit;
  final int cacheWidth;
  final bool animate;
  @override
  Widget build(BuildContext context) => ComicImage(
    comic.cover,
    web: web,
    fit: fit,
    cacheWidth: cacheWidth,
    animate: animate,
    fallback: ColoredBox(
      color: const Color(0xffe1e5dc),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: LocalizedText(
            comic.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xff3b4d40),
              fontFamily: 'ArchiveSerif',
              fontSize: 20,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Orthographic paper solid, with a sheared cover plane. Implemented independently.
class BookObject extends StatefulWidget {
  const BookObject(
    this.comic, {
    super.key,
    required this.web,
    this.exposure = 1,
    this.number = 1,
    this.bookmark = false,
    this.light = 0,
    this.opening = 0,
    this.onColor,
    this.animateCover = true,
  });
  final Comic comic;
  final bool web, bookmark;
  final bool animateCover;
  final double exposure;
  final double light;
  final double opening;
  final ValueChanged<Color>? onColor;
  final int number;
  @override
  State<BookObject> createState() => _BookObjectState();
}

class _BookObjectState extends State<BookObject>
    with SingleTickerProviderStateMixin {
  late final arrival =
      AnimationController(vsync: this, duration: RoomMotion.cover)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed && bitmap != null) {
            CoverArrival.markPresented(widget.comic.cover);
          }
        });
  ui.Image? bitmap;
  Color? bindingColor;
  ImageInfo? frame;
  ImageStream? stream;
  ImageStreamListener? listener;
  int generation = 0;
  String? requestedCover;
  bool? requestedWeb;
  _BookArtwork? artwork;
  void _invalidateArtwork() {
    artwork?.dispose();
    artwork = null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (bitmap != null && MediaQuery.disableAnimationsOf(context)) {
      arrival.value = 1;
    }
    _load();
  }

  @override
  void didUpdateWidget(BookObject old) {
    super.didUpdateWidget(old);
    if (old.comic.title != widget.comic.title ||
        old.number != widget.number ||
        old.bookmark != widget.bookmark) {
      _invalidateArtwork();
    }
    if (old.comic.cover != widget.comic.cover || old.web != widget.web) {
      _invalidateArtwork();
      bitmap = null;
      bindingColor = null;
      arrival.value = 0;
      _load();
    } else if (old.onColor == null &&
        widget.onColor != null &&
        bitmap != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && bitmap != null) _color(bitmap!);
      });
    }
  }

  Future<void> _load() async {
    if (requestedCover == widget.comic.cover && requestedWeb == widget.web) {
      return;
    }
    requestedCover = widget.comic.cover;
    requestedWeb = widget.web;
    final current = ++generation;
    _unsubscribe();
    final ImageProvider provider;
    try {
      provider = await comicImageProvider(widget.comic.cover, widget.web);
    } catch (_) {
      if (current == generation) requestedCover = null;
      return;
    }
    if (!mounted || current != generation) return;
    stream = ResizeImage.resizeIfNeeded(
      512,
      null,
      provider,
    ).resolve(createLocalImageConfiguration(context));
    listener = ImageStreamListener(
      (info, synchronous) {
        if (!mounted || current != generation) {
          info.dispose();
          return;
        }
        final previous = frame;
        final first = bitmap == null;
        frame = info;
        if (mounted) {
          setState(() {
            bitmap = info.image;
            _invalidateArtwork();
          });
        }
        previous?.dispose();
        if (first) {
          if (synchronous ||
              !widget.animateCover ||
              MediaQuery.disableAnimationsOf(context) ||
              CoverArrival.hasPresented(widget.comic.cover)) {
            arrival.value = 1;
          } else {
            arrival.forward(from: 0);
          }
        }
        _color(info.image);
      },
      onError: (_, _) {
        if (current == generation) requestedCover = null;
      },
    );
    stream!.addListener(listener!);
  }

  void _unsubscribe() {
    final previousStream = stream;
    final previousListener = listener;
    stream = null;
    listener = null;
    if (previousListener != null) {
      previousStream?.removeListener(previousListener);
    }
  }

  Future<void> _color(ui.Image image) async {
    final cover = widget.comic.cover;
    final color = await CoverPalette.average(cover, image);
    if (mounted && cover == widget.comic.cover && color != null) {
      if (bindingColor != color) {
        setState(() {
          bindingColor = color;
          _invalidateArtwork();
        });
      }
      widget.onColor?.call(color);
    }
  }

  @override
  void dispose() {
    generation++;
    _unsubscribe();
    arrival.dispose();
    frame?.dispose();
    _invalidateArtwork();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _BookPainter(
      artwork: artwork ??= _BookArtwork(
        bitmap,
        widget.comic.title,
        widget.number,
        widget.bookmark,
        bindingColor,
      ),
      exposure: widget.exposure,
      light: widget.light,
      opening: widget.opening,
      arrival: arrival,
    ),
    size: const Size(200, 300),
  );
}

/// Immutable pictures retain paragraph layout and cover draw commands. The
/// animation only changes the projection and light; it does not lay out type.
class _BookArtwork {
  _BookArtwork(
    ui.Image? image,
    String title,
    int number,
    bool bookmark,
    Color? tone,
  ) : hasCover = image != null {
    final spineRecorder = ui.PictureRecorder();
    tone ??= const Color(0xffe7e8db);
    final spineCanvas = Canvas(spineRecorder);
    final spineRect = const Rect.fromLTWH(0, 0, 23, 226);
    spineCanvas.drawRect(
      spineRect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Color.lerp(const Color(0xffe7e8db), tone, .24)!,
            Color.lerp(const Color(0xfffcfcf6), tone, .18)!,
            Color.lerp(const Color(0xffdedfd1), tone, .30)!,
          ],
          stops: [0, .45, 1],
        ).createShader(spineRect),
    );
    spineCanvas.drawRect(
      spineRect,
      Paint()
        ..color = const Color(0xffb7baaa)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .5,
    );
    _text(
      spineCanvas,
      number.toString().padLeft(2, '0'),
      5,
      12,
      8,
      const Color(0xff858d7b),
    );
    _text(
      spineCanvas,
      title.characters.take(11).join('\n'),
      6,
      52,
      11,
      const Color(0xff343c31),
      max: 14,
    );
    _text(spineCanvas, '漫\n匣', 7, 194, 7, const Color(0xff8d9686));
    spine = spineRecorder.endRecording();
    final placeholderRecorder = ui.PictureRecorder();
    final placeholderCanvas = Canvas(placeholderRecorder);
    placeholderCanvas.drawRect(
      const Rect.fromLTWH(0, 0, 136, 226),
      Paint()..color = const Color(0xffb4c6b4),
    );
    _text(
      placeholderCanvas,
      title,
      12,
      80,
      13,
      const Color(0xff304c3a),
      max: 112,
    );
    placeholder = placeholderRecorder.endRecording();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const faceRect = Rect.fromLTWH(0, 0, 136, 226);
    canvas.drawRect(faceRect, Paint()..color = const Color(0xffb4c6b4));
    const cover = faceRect;
    if (image != null) {
      paintImage(
        canvas: canvas,
        rect: cover,
        image: image,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      );
    } else {
      canvas.drawPicture(placeholder);
    }
    canvas.drawRect(
      faceRect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.black.withValues(alpha: .16),
            Colors.transparent,
            Colors.white.withValues(alpha: .08),
          ],
          stops: const [0, .13, 1],
        ).createShader(faceRect),
    );
    canvas.drawLine(
      const Offset(3, 0),
      const Offset(3, 226),
      Paint()..color = Colors.black.withValues(alpha: .12),
    );
    canvas.drawRect(
      faceRect,
      Paint()
        ..color = const Color(0xffc6cbbd)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .6,
    );
    // The cover is the entire binding, rather than a framed image pasted on it.
    if (bookmark) {
      canvas.drawPath(
        Path()..addPolygon(const [
          Offset(112, -1),
          Offset(124, -1),
          Offset(124, 42),
          Offset(118, 35),
          Offset(112, 42),
        ], true),
        Paint()..color = const Color(0xff47775e),
      );
    }
    face = recorder.endRecording();
    final innerRecorder = ui.PictureRecorder();
    final paper = Canvas(innerRecorder);
    paper.drawRect(faceRect, Paint()..color = const Color(0xfff5f1e6));
    paper.drawRect(
      faceRect,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xffded9ca), Color(0xfffaf7ed), Color(0xffebe6d8)],
          stops: [0, .16, 1],
        ).createShader(faceRect),
    );
    inner = innerRecorder.endRecording();
  }
  final bool hasCover;
  late final ui.Picture spine, face, inner, placeholder;
  static void _text(
    Canvas canvas,
    String text,
    double x,
    double y,
    double size,
    Color color, {
    double max = 180,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'ArchiveSerif',
          fontSize: size,
          color: color,
          height: 1.12,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 12,
    )..layout(maxWidth: max);
    painter.paint(canvas, Offset(x, y));
    painter.dispose();
  }

  void dispose() {
    spine.dispose();
    face.dispose();
    inner.dispose();
    placeholder.dispose();
  }
}

class _BookPainter extends CustomPainter {
  _BookPainter({
    required this.artwork,
    required this.exposure,
    required this.light,
    required this.opening,
    required this.arrival,
  }) : super(repaint: arrival);
  final Animation<double> arrival;
  final _BookArtwork artwork;
  final double exposure, light, opening;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 200, size.height / 300);
    final spread = Curves.easeInOut.transform(opening.clamp(0, 1));
    final fw = ui.lerpDouble(34 + exposure * 102, 86, spread)!;
    final x = ui.lerpDouble(22, 92, spread)!;
    final spine = ui.lerpDouble(23, 5, spread)!;
    const y = 49.0, h = 226.0;
    final dy = ui.lerpDouble(-28 - 12 * exposure + light * 4, -8, spread)!;
    final shadow = Path()
      ..addPolygon([
        Offset(x, 277),
        Offset(x + spine + fw + 32, 250),
        Offset(x + spine + fw + 48, 264),
        Offset(x + 12, 293),
      ], true);
    canvas.drawPath(
      shadow,
      Paint()
        ..color = const Color(
          0xff243a29,
        ).withValues(alpha: .08 + exposure * .12)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 + exposure * 12),
    );
    final top = Path()
      ..addPolygon([
        Offset(x, y),
        Offset(x + spine, y),
        Offset(x + spine + fw, y + dy),
        Offset(x + fw, y + dy - 3),
      ], true);
    canvas.drawPath(top, Paint()..color = const Color(0xffeeeede));
    for (var i = 1; i < 5; i++) {
      canvas.drawLine(
        Offset(x + i * 4, y - 1),
        Offset(x + fw + i * 4, y + dy - 2),
        Paint()
          ..color = const Color(0xffd7d8cb)
          ..strokeWidth = .5,
      );
    }
    canvas.save();
    canvas.translate(x, y);
    canvas.scale(spine / 23, 1);
    canvas.drawPicture(artwork.spine);
    canvas.restore();
    canvas.save();
    canvas.translate(x + spine, y);
    canvas.transform((Matrix4.identity()..setEntry(1, 0, dy / fw)).storage);
    canvas.scale(fw / 136, 1);
    if (opening > .001) {
      canvas.drawPicture(artwork.inner);
      for (var line = 1; line < 5; line++) {
        canvas.drawLine(
          Offset(136 - line * 2, 4),
          Offset(136 - line * 2, h - 4),
          Paint()..color = const Color(0xffcdd2c3),
        );
      }
      // Separate leaves lag behind the binding, all pivoting around the spine.
      for (var leaf = 2; leaf >= 0; leaf--) {
        final turn = ((opening - .12 - leaf * .07) / .76).clamp(0.0, 1.0);
        final angle = 2.56 * turn;
        canvas.save();
        canvas.translate(0, -leaf * .65);
        canvas.transform(
          (Matrix4.identity()
                ..setEntry(3, 2, .0012)
                ..rotateY(angle))
              .storage,
        );
        if (angle.abs() > math.pi / 2) {
          canvas.translate(136, 0);
          canvas.scale(-1, 1);
        }
        canvas.drawPicture(artwork.inner);
        canvas.restore();
      }
    }
    final angle = 2.75 * opening;
    canvas.transform(
      (Matrix4.identity()
            ..setEntry(3, 2, .0012)
            ..rotateY(angle))
          .storage,
    );
    if (angle.abs() > math.pi / 2) {
      canvas.translate(136, 0);
      canvas.scale(-1, 1);
      canvas.drawPicture(artwork.inner);
    } else {
      final opacity = RoomMotion.ease.transform(arrival.value);
      if (artwork.hasCover && opacity < 1) {
        canvas.drawPicture(artwork.placeholder);
        canvas.saveLayer(
          const Rect.fromLTWH(0, 0, 136, h),
          Paint()..color = Colors.white.withValues(alpha: opacity),
        );
        canvas.drawPicture(artwork.face);
        canvas.restore();
      } else {
        canvas.drawPicture(artwork.face);
      }
    }
    const face = Rect.fromLTWH(0, 0, 136, h);
    canvas.drawRect(
      face,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment(-1 + light, -1),
          end: Alignment(1 + light, 1),
          colors: [
            Colors.transparent,
            Colors.white.withValues(alpha: .04 + exposure * .035),
            Colors.transparent,
          ],
          stops: const [0, .45, 1],
        ).createShader(face),
    );
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BookPainter old) =>
      old.artwork != artwork ||
      old.exposure != exposure ||
      old.light != light ||
      old.opening != opening;
}
