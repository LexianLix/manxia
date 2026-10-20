import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../data/comic.dart';

String imageAddress(String original, bool web) => web
    ? Uri.base
          .resolve('/api/image')
          .replace(queryParameters: {'url': original})
          .toString()
    : original;

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
  Widget build(BuildContext context) => Image.network(
    imageAddress(comic.cover, web),
    fit: fit,
    headers: web ? null : const {'Referer': 'https://m.dm5.com/'},
    errorBuilder: (_, _, _) => ColoredBox(
      color: const Color(0xffe1e5dc),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Text(
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
  });
  final Comic comic;
  final bool web, bookmark;
  final double exposure;
  final int number;
  @override
  State<BookObject> createState() => _BookObjectState();
}

class _BookObjectState extends State<BookObject> {
  ui.Image? bitmap;
  ImageStream? stream;
  ImageStreamListener? listener;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(BookObject old) {
    super.didUpdateWidget(old);
    if (old.comic.cover != widget.comic.cover) _load();
  }

  void _load() {
    if (listener != null) stream?.removeListener(listener!);
    final provider = NetworkImage(
      imageAddress(widget.comic.cover, widget.web),
      headers: widget.web ? null : const {'Referer': 'https://m.dm5.com/'},
    );
    stream = provider.resolve(createLocalImageConfiguration(context));
    listener = ImageStreamListener((info, _) {
      if (mounted) setState(() => bitmap = info.image);
    }, onError: (_, _) {});
    stream!.addListener(listener!);
  }

  @override
  void dispose() {
    if (listener != null) stream?.removeListener(listener!);
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
  });
  final ui.Image? image;
  final String title;
  final double exposure;
  final int number;
  final bool bookmark;
  Path polygon(List<Offset> p) => Path()..addPolygon(p, true);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 200, size.height / 300);
    final fw = 34 + exposure * 102;
    const x = 22.0, y = 49.0, h = 226.0, spine = 23.0, dy = -34.0;
    final shadow = polygon([
      const Offset(x, 277),
      Offset(x + spine + fw + 32, 250),
      Offset(x + spine + fw + 48, 264),
      const Offset(x + 12, 293),
    ]);
    canvas.drawPath(
      shadow,
      Paint()
        ..color = const Color(0xff243a29).withValues(alpha: .13)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
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
      old.bookmark != bookmark;
}
