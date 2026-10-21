import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'room_motion.dart';

class MilkGlass extends StatefulWidget {
  const MilkGlass({
    super.key,
    required this.child,
    this.radius = 14,
    this.high = true,
    this.padding = EdgeInsets.zero,
    this.tintOpacity,
    this.blurSigma,
    this.shadow = false,
  });
  final Widget child;
  final double radius;
  final bool high;
  final EdgeInsetsGeometry padding;
  final double? tintOpacity, blurSigma;
  final bool shadow;
  @override
  State<MilkGlass> createState() => _MilkGlassState();
}

class _MilkGlassState extends State<MilkGlass> {
  static Future<ui.FragmentProgram>? program;
  ui.FragmentShader? shader;
  @override
  void initState() {
    super.initState();
    if (ui.ImageFilter.isShaderFilterSupported) {
      (program ??= ui.FragmentProgram.fromAsset('shaders/glass.frag'))
          .then((p) {
            if (mounted) {
              setState(() => shader = p.fragmentShader()..setFloat(2, 1));
            }
          })
          .catchError((Object _) {});
    }
  }

  @override
  void dispose() {
    shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final contrast = MediaQuery.highContrastOf(context);
    ui.ImageFilter filter = ui.ImageFilter.blur(
      sigmaX: widget.high ? (widget.blurSigma ?? 22) : 4,
      sigmaY: widget.high ? (widget.blurSigma ?? 22) : 4,
    );
    if (widget.high && shader != null) {
      filter = ui.ImageFilter.compose(
        outer: filter,
        inner: ui.ImageFilter.shader(shader!),
      );
    }
    final glass = ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: BackdropFilter(
        filter: filter,
        child: Container(
          padding: widget.padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            color: (dark ? const Color(0xff182a25) : const Color(0xfff6fbfa))
                .withValues(
                  alpha: contrast
                      ? .96
                      : widget.tintOpacity ??
                            (widget.high ? (dark ? .46 : .30) : .90),
                ),
            border: Border.all(
              color: Colors.white.withValues(alpha: dark ? .22 : .82),
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: dark ? .12 : .34),
                Colors.white.withValues(alpha: dark ? .025 : .055),
              ],
            ),
          ),
          child: widget.child,
        ),
      ),
    );
    return widget.shadow
        ? DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius),
              boxShadow: [
                BoxShadow(
                  color: const Color(
                    0xff183d32,
                  ).withValues(alpha: dark ? .28 : .12),
                  blurRadius: 30,
                  offset: const Offset(0, 12),
                ),
                BoxShadow(
                  color: Colors.white.withValues(alpha: dark ? .03 : .65),
                  blurRadius: 1,
                  offset: const Offset(0, -1),
                ),
              ],
            ),
            child: glass,
          )
        : glass;
  }
}

class EntryReveal extends StatelessWidget {
  const EntryReveal({super.key, required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;
  @override
  Widget build(BuildContext c) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: enabled ? RoomMotion.duration(c, RoomMotion.page) : Duration.zero,
    curve: RoomMotion.ease,
    builder: (_, t, child) => Opacity(
      opacity: t,
      child: Transform.translate(offset: Offset(0, 14 * (1 - t)), child: child),
    ),
    child: child,
  );
}
