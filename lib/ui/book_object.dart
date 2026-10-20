import 'localized_text.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../data/comic.dart';
import 'comic_image.dart';
import 'cover_palette.dart';
export 'comic_image.dart' show imageAddress;

class ComicCover extends StatelessWidget {
  const ComicCover(
    this.comic, {
    super.key,
    required this.web,
    this.fit = BoxFit.cover,
    this.cacheWidth = 512,
  });
  final Comic comic;
  final bool web;
  final BoxFit fit;
  final int cacheWidth;
  @override
  Widget build(BuildContext context) => ComicImage(
    comic.cover,
    web: web,
    fit: fit,
    cacheWidth: cacheWidth,
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
    this.onColor,
  });
  final Comic comic;
  final bool web, bookmark;
  final double exposure;
  final double light;
  final ValueChanged<Color>? onColor;
  final int number;
  @override
  State<BookObject> createState() => _BookObjectState();
}

class _BookObjectState extends State<BookObject> {
  ui.Image? bitmap;
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
      (info, _) {
        if (!mounted || current != generation) {
          info.dispose();
          return;
        }
        final previous = frame;
        frame = info;
        if (mounted) {
          setState(() {
            bitmap = info.image;
            _invalidateArtwork();
          });
        }
        previous?.dispose();
        if (widget.onColor != null) _color(info.image);
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
      widget.onColor?.call(color);
    }
  }

  @override
  void dispose() {
    generation++;
    _unsubscribe();
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
      ),
      exposure: widget.exposure,
      light: widget.light,
    ),
    size: const Size(200, 300),
  );
}

/// Immutable pictures retain paragraph layout and cover draw commands. The
/// animation only changes the projection and light; it does not lay out type.
class _BookArtwork {
  _BookArtwork(ui.Image? image, String title, int number, bool bookmark) {
    final spineRecorder = ui.PictureRecorder();
    final spineCanvas = Canvas(spineRecorder);
    final spineRect = const Rect.fromLTWH(0, 0, 23, 226);
    spineCanvas.drawRect(
      spineRect,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xffe7e8db), Color(0xfffcfcf6), Color(0xffdedfd1)],
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
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const faceRect = Rect.fromLTWH(0, 0, 136, 226);
    canvas.drawRect(faceRect, Paint()..color = const Color(0xfffafbf4));
    _text(
      canvas,
      'MANGA / ${number.toString().padLeft(3, '0')}',
      7,
      11,
      6.5,
      const Color(0xff6f7a67),
    );
    const cover = Rect.fromLTWH(7, 29, 122, 161);
    if (image != null) {
      paintImage(
        canvas: canvas,
        rect: cover,
        image: image,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.low,
      );
    } else {
      canvas.drawRect(cover, Paint()..color = const Color(0xffb4c6b4));
      _text(canvas, title, 12, 80, 13, const Color(0xff304c3a), max: 112);
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
    _text(canvas, title, 8, 202, 8, const Color(0xff4e5b46), max: 120);
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
  }
  late final ui.Picture spine, face;
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
  }
}

class _BookPainter extends CustomPainter {
  _BookPainter({
    required this.artwork,
    required this.exposure,
    required this.light,
  });
  final _BookArtwork artwork;
  final double exposure, light;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 200, size.height / 300);
    final fw = 34 + exposure * 102;
    const x = 22.0, y = 49.0, h = 226.0, spine = 23.0;
    final dy = -28.0 - 12 * exposure + light * 4;
    final shadow = Path()
      ..addPolygon([
        const Offset(x, 277),
        Offset(x + spine + fw + 32, 250),
        Offset(x + spine + fw + 48, 264),
        const Offset(x + 12, 293),
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
        const Offset(x, y),
        const Offset(x + spine, y),
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
    canvas.drawPicture(artwork.spine);
    canvas.restore();
    canvas.save();
    canvas.translate(x + spine, y);
    canvas.transform((Matrix4.identity()..setEntry(1, 0, dy / fw)).storage);
    canvas.scale(fw / 136, 1);
    canvas.drawPicture(artwork.face);
    const face = Rect.fromLTWH(0, 0, 136, h);
    canvas.drawRect(
      face,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment(-1 + light, -1),
          end: Alignment(1 + light, 1),
          colors: [
            Colors.transparent,
            Colors.white.withValues(alpha: .14 + exposure * .1),
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
      old.artwork != artwork || old.exposure != exposure || old.light != light;
}
