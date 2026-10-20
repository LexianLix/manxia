import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class MilkGlass extends StatefulWidget {
  const MilkGlass({
    super.key,
    required this.child,
    this.radius = 14,
    this.high = true,
    this.padding = EdgeInsets.zero,
  });
  final Widget child;
  final double radius;
  final bool high;
  final EdgeInsetsGeometry padding;
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
    ui.ImageFilter filter = ui.ImageFilter.blur(
      sigmaX: widget.high ? 18 : 4,
      sigmaY: widget.high ? 18 : 4,
    );
    if (widget.high && shader != null) {
      filter = ui.ImageFilter.compose(
        outer: filter,
        inner: ui.ImageFilter.shader(shader!),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: BackdropFilter(
        filter: filter,
        child: Container(
          padding: widget.padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            color: (dark ? const Color(0xff25342b) : const Color(0xfffdfef7))
                .withValues(alpha: widget.high ? .68 : .95),
            border: Border.all(
              color: Colors.white.withValues(alpha: dark ? .12 : .72),
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: dark ? .08 : .5),
                Colors.white.withValues(alpha: .015),
              ],
            ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class EntryReveal extends StatelessWidget {
  const EntryReveal({super.key, required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;
  @override
  Widget build(BuildContext c) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: Duration(
      milliseconds: enabled && !MediaQuery.disableAnimationsOf(c) ? 360 : 0,
    ),
    curve: Curves.easeOutCubic,
    builder: (_, t, child) => Opacity(
      opacity: t,
      child: Transform.translate(offset: Offset(0, 14 * (1 - t)), child: child),
    ),
    child: child,
  );
}
