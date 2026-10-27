import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// A cylindrical page mesh. SnapshotWidget captures only once for a short
/// turn; repainting the mesh never reads the screen back again. At rest the
/// live subtree paints and handles input normally. No timers or shader warmup.
class PaperLeaf extends StatefulWidget {
  const PaperLeaf({
    super.key,
    required this.amount,
    required this.child,
    this.reverse = false,
  });
  final double amount;
  final bool reverse;
  final Widget child;
  @override
  State<PaperLeaf> createState() => _PaperLeafState();
}

class _PaperLeafState extends State<PaperLeaf> {
  final snapshot = SnapshotController();
  final painter = PageLeafPainter();
  @override
  void dispose() {
    snapshot.dispose();
    painter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final amount = MediaQuery.disableAnimationsOf(context)
        ? 0.0
        : widget.amount.clamp(0.0, 1.0);
    snapshot.allowSnapshotting = amount > .0001 && amount < .9999;
    painter.update(
      amount,
      widget.reverse,
      Theme.of(context).colorScheme.surface,
    );
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        devicePixelRatio: math.min(2, MediaQuery.devicePixelRatioOf(context)),
      ),
      child: SnapshotWidget(
        controller: snapshot,
        painter: painter,
        mode: SnapshotMode.permissive,
        autoresize: true,
        child: widget.child,
      ),
    );
  }
}

class PageLeafPainter extends SnapshotPainter {
  double amount = 0;
  bool reverse = false;
  Color paper = const Color(0xfff5f8fa);
  void update(double value, bool mirrored, Color color) {
    if (amount == value && reverse == mirrored && paper == color) return;
    amount = value;
    reverse = mirrored;
    paper = color;
    notifyListeners();
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset,
    Size size,
    PaintingContextCallback painter,
  ) {
    if (amount >= .9999) return;
    painter(context, offset);
  }

  @override
  void paintSnapshot(
    PaintingContext context,
    Offset offset,
    Size size,
    ui.Image image,
    Size sourceSize,
    double pixelRatio,
  ) {
    final canvas = context.canvas;
    if (size.isEmpty || amount >= .9999) return;
    if (amount <= .0001) {
      canvas.drawImageRect(
        image,
        Offset.zero & sourceSize,
        offset & size,
        Paint()..filterQuality = FilterQuality.medium,
      );
      return;
    }
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.clipRect(Offset.zero & size);
    final radius = size.width * (.10 + .04 * math.sin(math.pi * amount));
    final edge = size.width * (1 - 1.25 * amount);
    const segments = 48;
    final positions = <Offset>[], textures = <Offset>[], colors = <Color>[];
    final front = <int>[], back = <int>[];
    for (var i = 0; i <= segments; i++) {
      final u = i / segments;
      final distance = u * size.width - edge;
      final angle = (distance / radius).clamp(0.0, math.pi);
      final x = distance <= 0
          ? u * size.width
          : distance < math.pi * radius
          ? edge + math.sin(angle) * radius
          : edge - (distance - math.pi * radius);
      final z = (1 - math.cos(angle)) * radius;
      final perspective = 1 / (1 + z / (size.width * 5));
      final shade = (.80 + .20 * math.cos(angle).abs()).clamp(.70, 1.0);
      for (final v in [0.0, 1.0]) {
        positions.add(
          Offset(
            reverse ? size.width - x : x,
            size.height / 2 + (v - .5) * size.height * perspective,
          ),
        );
        textures.add(
          Offset(
            (reverse ? 1 - u : u) * sourceSize.width,
            v * sourceSize.height,
          ),
        );
        colors.add(
          Color.fromRGBO(
            (255 * shade).round(),
            (255 * shade).round(),
            (255 * shade).round(),
            1,
          ),
        );
      }
      if (i < segments) {
        final mid = ((i + .5) / segments * size.width - edge) / radius;
        final indices = mid <= math.pi / 2 ? front : back;
        final k = i * 2;
        indices.addAll([k, k + 1, k + 2, k + 2, k + 1, k + 3]);
      }
    }
    final outline = Path()..moveTo(positions.first.dx, positions.first.dy);
    for (var i = 2; i < positions.length; i += 2) {
      outline.lineTo(positions[i].dx, positions[i].dy);
    }
    for (var i = positions.length - 1; i > 0; i -= 2) {
      outline.lineTo(positions[i].dx, positions[i].dy);
    }
    outline.close();
    canvas.drawShadow(outline, Colors.black.withValues(alpha: .20), 9, false);
    canvas.drawPath(outline, Paint()..color = paper);
    if (back.isNotEmpty) {
      final mesh = ui.Vertices(
        ui.VertexMode.triangles,
        positions,
        colors: colors,
        indices: back,
      );
      canvas.drawVertices(mesh, BlendMode.modulate, Paint()..color = paper);
      mesh.dispose();
    }
    if (front.isNotEmpty) {
      final mesh = ui.Vertices(
        ui.VertexMode.triangles,
        positions,
        textureCoordinates: textures,
        colors: colors,
        indices: front,
      );
      canvas.drawVertices(
        mesh,
        BlendMode.modulate,
        Paint()
          ..shader = ui.ImageShader(
            image,
            TileMode.clamp,
            TileMode.clamp,
            Matrix4.identity().storage,
          )
          ..filterQuality = FilterQuality.medium,
      );
      mesh.dispose();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(PageLeafPainter oldPainter) => true;
}
