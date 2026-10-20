import 'localized_text.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../data/comic.dart';
import 'comic_image.dart';
export 'comic_image.dart' show imageAddress;

class ComicCover extends StatelessWidget {
  const ComicCover(
    this.comic, {
    super.key,
    required this.web,
    this.fit = BoxFit.cover,
  });
  final Comic comic;
  final bool web;
  final BoxFit fit;
  @override
  Widget build(BuildContext context) => ComicImage(
    comic.cover,
    web: web,
    fit: fit,
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
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(BookObject old) {
    super.didUpdateWidget(old);
    if (old.comic.cover != widget.comic.cover) {
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
    final current = ++generation;
    if (listener != null) stream?.removeListener(listener!);
    final ImageProvider provider;
    try {
      provider = await comicImageProvider(widget.comic.cover, widget.web);
    } catch (_) {
      return;
    }
    if (!mounted || current != generation) return;
    stream = provider.resolve(createLocalImageConfiguration(context));
    listener = ImageStreamListener((info, _) {
      if (!mounted || current != generation) {
        info.dispose();
        return;
      }
      final previous = frame;
      frame = info;
      if (mounted) setState(() => bitmap = info.image);
      previous?.dispose();
      if (widget.onColor != null) _color(info.image);
    }, onError: (_, _) {});
    stream!.addListener(listener!);
  }

  Future<void> _color(ui.Image image) async {
    final width = image.width,
        height = image.height,
        cover = widget.comic.cover;
    final data = await image.toByteData();
    if (data == null || !mounted || cover != widget.comic.cover) return;
    var r = 0, g = 0, b = 0, n = 0;
    final bytes = data.buffer.asUint8List();
    for (var y = 0; y < height; y += 12) {
      for (var x = 0; x < width; x += 12) {
        final k = (y * width + x) * 4;
        final sum = bytes[k] + bytes[k + 1] + bytes[k + 2];
        if (sum > 90 && sum < 680) {
          r += bytes[k];
          g += bytes[k + 1];
          b += bytes[k + 2];
          n++;
        }
      }
    }
    if (n > 0 && mounted) {
      widget.onColor?.call(Color.fromARGB(255, r ~/ n, g ~/ n, b ~/ n));
    }
  }

  @override
  void dispose() {
    generation++;
    if (listener != null) stream?.removeListener(listener!);
    frame?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _BookPainter(
      image: bitmap,
      title: widget.comic.title,
      exposure: widget.exposure,
      number: widget.number,
      bookmark: widget.bookmark,
      light: widget.light,
    ),
    size: const Size(200, 300),
  );
}

class _BookPainter extends CustomPainter {
  _BookPainter({
    required this.image,
    required this.title,
    required this.exposure,
    required this.number,
    required this.bookmark,
    required this.light,
  });
  final ui.Image? image;
  final String title;
  final double exposure;
  final double light;
  final int number;
  final bool bookmark;
  Path polygon(List<Offset> p) => Path()..addPolygon(p, true);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 200, size.height / 300);
    final fw = 34 + exposure * 102;
    const x = 22.0, y = 49.0, h = 226.0, spine = 23.0;
    final dy = -28.0 - 12 * exposure + light * 4;
    final shadow = polygon([
      const Offset(x, 277),
      Offset(x + spine + fw + 32, 250),
      Offset(x + spine + fw + 48, 264),
      const Offset(x + 12, 293),
    ]);
    canvas.drawPath(
      shadow,
      Paint()
        ..color = const Color(
          0xff243a29,
        ).withValues(alpha: .08 + exposure * .12)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 + exposure * 12),
    );
    final top = polygon([
      const Offset(x, y),
      const Offset(x + spine, y),
      Offset(x + spine + fw, y + dy),
      Offset(x + fw, y + dy - 3),
    ]);
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
    final spineRect = const Rect.fromLTWH(x, y, spine, h);
    canvas.drawRect(
      spineRect,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xffe7e8db), Color(0xfffcfcf6), Color(0xffdedfd1)],
          stops: [0, .45, 1],
        ).createShader(spineRect),
    );
    canvas.drawRect(
      spineRect,
      Paint()
        ..color = const Color(0xffb7baaa)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .5,
    );
    void text(
      String value,
      double px,
      double py,
      double fs,
      Color color, {
      double max = 180,
    }) {
      final tp = TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(
            fontFamily: 'ArchiveSerif',
            fontSize: fs,
            color: color,
            height: 1.12,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 12,
      )..layout(maxWidth: max);
      tp.paint(canvas, Offset(px, py));
    }

    text(
      number.toString().padLeft(2, '0'),
      x + 5,
      y + 12,
      8,
      const Color(0xff858d7b),
    );
    text(
      title.characters.take(11).join('\n'),
      x + 6,
      y + 52,
      11,
      const Color(0xff343c31),
      max: 14,
    );
    text('漫\n匣', x + 7, y + h - 32, 7, const Color(0xff8d9686));
    canvas.save();
    canvas.translate(x + spine, y);
    final transform = Matrix4.identity()..setEntry(1, 0, dy / fw);
    canvas.transform(transform.storage);
    final face = Rect.fromLTWH(0, 0, fw, h);
    canvas.drawRect(face, Paint()..color = const Color(0xfffafbf4));
    text(
      'MANGA / ${number.toString().padLeft(3, '0')}',
      7,
      11,
      6.5,
      const Color(0xff6f7a67),
    );
    final cover = Rect.fromLTWH(7, 29, fw - 14, h - 65);
    if (image != null) {
      paintImage(
        canvas: canvas,
        rect: cover,
        image: image!,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      );
    } else {
      canvas.drawRect(cover, Paint()..color = const Color(0xffb4c6b4));
      text(title, 12, 80, 13, const Color(0xff304c3a), max: fw - 24);
    }
    canvas.drawRect(
      face,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.black.withValues(alpha: .16),
            Colors.transparent,
            Colors.white.withValues(alpha: .08),
          ],
          stops: const [0, .13, 1],
        ).createShader(face),
    );
    canvas.drawLine(
      const Offset(3, 0),
      const Offset(3, h),
      Paint()..color = Colors.black.withValues(alpha: .12),
    );
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
    canvas.drawRect(
      face,
      Paint()
        ..color = const Color(0xffc6cbbd)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .6,
    );
    text(title, 8, h - 24, 8, const Color(0xff4e5b46), max: fw - 16);
    if (bookmark) {
      final flag = polygon([
        Offset(fw - 24, -1),
        Offset(fw - 12, -1),
        Offset(fw - 12, 42),
        Offset(fw - 18, 35),
        Offset(fw - 24, 42),
      ]);
      canvas.drawPath(flag, Paint()..color = const Color(0xff47775e));
    }
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BookPainter old) =>
      old.image != image ||
      old.exposure != exposure ||
      old.title != title ||
      old.bookmark != bookmark ||
      old.light != light;
}
