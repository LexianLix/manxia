import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'glass_navigation.dart' show RoomDestination;
import 'room_motion.dart';

/// Every selection plays one finite gesture, independent of the lens spring.
/// The icon's layout anchor never moves, so the glass remains centered on it.
class DestinationMotionIcon extends StatefulWidget {
  const DestinationMotionIcon({
    super.key,
    required this.destination,
    required this.selected,
    required this.reduced,
    required this.color,
  });
  final RoomDestination destination;
  final bool selected, reduced;
  final Color color;
  @override
  State<DestinationMotionIcon> createState() => _DestinationMotionIconState();
}

class _DestinationMotionIconState extends State<DestinationMotionIcon>
    with SingleTickerProviderStateMixin {
  late final clock = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 440),
    value: 1,
  );
  @override
  void didUpdateWidget(DestinationMotionIcon old) {
    super.didUpdateWidget(old);
    if (widget.reduced) {
      clock.value = 1;
    } else if (widget.selected && !old.selected) {
      clock.forward(from: 0);
    } else if (!widget.selected && old.selected) {
      clock.animateTo(1, duration: RoomMotion.feedback, curve: RoomMotion.ease);
    }
  }

  @override
  void dispose() {
    clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 22,
    child: AnimatedBuilder(
      animation: clock,
      builder: (_, _) {
        final progress = widget.reduced ? 1.0 : clock.value;
        final pulse = math.sin(math.pi * progress);
        if (widget.destination.id == 0) {
          return CustomPaint(painter: _BookGlyph(widget.color, progress));
        }
        final id = widget.destination.id;
        Widget icon = Icon(
          widget.selected
              ? widget.destination.activeIcon
              : widget.destination.icon,
          size: 21,
          color: widget.color,
        );
        if (id == 1 || id == 2 || id == 3) {
          icon = Transform.rotate(
            angle: pulse * (id == 3 ? .30 : -.20),
            child: icon,
          );
        } else if (id == 4) {
          icon = Transform.scale(
            scaleY: 1 - .15 * pulse,
            alignment: Alignment.bottomCenter,
            child: icon,
          );
        } else {
          icon = Transform(
            transform: Matrix4.identity()
              ..setEntry(3, 2, .002)
              ..rotateY(.55 * pulse),
            alignment: Alignment.center,
            child: icon,
          );
        }
        return icon;
      },
    ),
  );
}

class _BookGlyph extends CustomPainter {
  const _BookGlyph(this.color, this.progress);
  final Color color;
  final double progress;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.45
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final left = Path()
      ..moveTo(12, 5)
      ..cubicTo(9, 2.6, 5, 2.6, 2, 4)
      ..lineTo(2, 20)
      ..cubicTo(5, 18.6, 9, 18.6, 12, 21)
      ..close();
    final right = Path()
      ..moveTo(12, 5)
      ..cubicTo(15, 2.6, 19, 2.6, 22, 4)
      ..lineTo(22, 20)
      ..cubicTo(19, 18.6, 15, 18.6, 12, 21)
      ..close();
    canvas.drawPath(left, Paint()..color = color.withValues(alpha: .12));
    canvas.drawPath(right, Paint()..color = color.withValues(alpha: .12));
    canvas.drawPath(left, pen);
    canvas.drawPath(right, pen);
    if (progress > 0 && progress < 1) {
      final x = 12 + math.cos(math.pi * progress) * 9;
      final leaf = Path()
        ..moveTo(12, 5)
        ..quadraticBezierTo(x, -2, x, 3.6)
        ..lineTo(x, 19.6)
        ..quadraticBezierTo(x, 17, 12, 21)
        ..close();
      canvas.drawPath(leaf, Paint()..color = color.withValues(alpha: .30));
      canvas.drawPath(leaf, pen);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BookGlyph old) =>
      old.progress != progress || old.color != color;
}
