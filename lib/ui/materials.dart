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
    this.margin = EdgeInsets.zero,
  });
  final Widget child;
  final double radius;
  final bool high;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double? tintOpacity, blurSigma;
  final bool shadow;
  @override
  State<MilkGlass> createState() => _MilkGlassState();
}

class _MilkGlassState extends State<MilkGlass> {
  static Future<ui.FragmentProgram>? program;
  ui.FragmentShader? shader;
  bool loadingShader = false;
  @override
  void initState() {
    super.initState();
    loadShader();
  }

  @override
  void didUpdateWidget(MilkGlass old) {
    super.didUpdateWidget(old);
    if (widget.high && !old.high) loadShader();
  }

  void loadShader() {
    if (widget.high &&
        shader == null &&
        !loadingShader &&
        ui.ImageFilter.isShaderFilterSupported) {
      loadingShader = true;
      (program ??= ui.FragmentProgram.fromAsset('shaders/glass.frag'))
          .then((p) {
            if (mounted && widget.high) {
              setState(() => shader = p.fragmentShader()..setFloat(2, 1));
            }
          })
          .catchError((Object _) {})
          .whenComplete(() => loadingShader = false);
    }
  }

  @override
  void dispose() {
    shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final contrast = MediaQuery.highContrastOf(context);
    ui.ImageFilter filter = ui.ImageFilter.blur(
      sigmaX: widget.high ? (widget.blurSigma ?? 16) : 0,
      sigmaY: widget.high ? (widget.blurSigma ?? 16) : 0,
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
        enabled: widget.high && !contrast,
        filter: filter,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            color: scheme.surface.withValues(
              alpha: contrast
                  ? .96
                  : widget.tintOpacity ??
                        (widget.high ? (dark ? .72 : .64) : .96),
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: dark ? .22 : .82),
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: dark ? .08 : .22),
                  Colors.white.withValues(alpha: dark ? .01 : .02),
                ],
              ),
            ),
            child: Padding(
              padding: widget.padding,
              child: Material(
                type: MaterialType.transparency,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
    final result = widget.shadow
        ? DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius),
              boxShadow: [
                BoxShadow(
                  color: scheme.shadow.withValues(alpha: dark ? .20 : .08),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
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
    return Padding(padding: widget.margin, child: result);
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
