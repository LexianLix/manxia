import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'room_motion.dart';

enum GlassRole { chrome, panel, control }

class GlassPerformanceScope extends InheritedWidget {
  const GlassPerformanceScope({
    super.key,
    required this.high,
    this.refraction = true,
    this.blurScale = 1,
    required super.child,
  });
  final bool high;
  final bool refraction;
  final double blurScale;
  static bool refractionOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<GlassPerformanceScope>()
          ?.refraction ??
      true;
  static double blurScaleOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<GlassPerformanceScope>()
          ?.blurScale ??
      1;
  static bool highOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<GlassPerformanceScope>()
          ?.high ??
      true;
  @override
  bool updateShouldNotify(GlassPerformanceScope old) =>
      old.high != high ||
      old.refraction != refraction ||
      old.blurScale != blurScale;
}

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
    this.role = GlassRole.panel,
  });
  final Widget child;
  final double radius;
  final bool high;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double? tintOpacity, blurSigma;
  final bool shadow;
  final GlassRole role;
  @override
  State<MilkGlass> createState() => _MilkGlassState();
}

class _MilkGlassState extends State<MilkGlass> {
  static Future<ui.FragmentProgram>? program;
  ui.FragmentShader? shader;
  bool loadingShader = false;
  bool allowHigh = true;
  bool allowRefraction = true;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    allowHigh = GlassPerformanceScope.highOf(context);
    allowRefraction = GlassPerformanceScope.refractionOf(context);
    if (allowHigh) loadShader();
  }

  @override
  void didUpdateWidget(MilkGlass old) {
    super.didUpdateWidget(old);
    if (allowHigh && widget.high && !old.high) loadShader();
  }

  void loadShader() {
    if (widget.high &&
        allowHigh &&
        allowRefraction &&
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
    final high = widget.high && allowHigh;
    final chrome = widget.role == GlassRole.chrome;
    final blurScale = GlassPerformanceScope.blurScaleOf(context);
    ui.ImageFilter filter = ui.ImageFilter.blur(
      sigmaX: high ? (widget.blurSigma ?? (chrome ? 18 : 22)) * blurScale : 0,
      sigmaY: high ? (widget.blurSigma ?? (chrome ? 18 : 22)) * blurScale : 0,
    );
    if (high && allowRefraction && shader != null) {
      shader!
        ..setFloat(2, chrome ? .45 : .30)
        ..setFloat(3, widget.radius * MediaQuery.devicePixelRatioOf(context))
        ..setFloat(4, 0)
        ..setFloat(5, 0)
        ..setFloat(6, 0);
      filter = ui.ImageFilter.compose(
        outer: filter,
        inner: ui.ImageFilter.shader(shader!),
      );
    }
    final glass = ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: BackdropFilter(
        enabled: high && !contrast,
        filter: filter,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            color: scheme.surface.withValues(
              alpha: contrast
                  ? .96
                  : widget.tintOpacity ??
                        (high
                            ? (chrome ? (dark ? .28 : .20) : (dark ? .38 : .30))
                            : .94),
            ),
            border: Border.all(
              color: scheme.onSurface.withValues(alpha: dark ? .12 : .07),
              width: .6,
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: dark ? .05 : .09),
                  Colors.white.withValues(alpha: .01),
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
                  color: scheme.shadow.withValues(alpha: dark ? .20 : .09),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: Colors.white.withValues(alpha: dark ? .08 : .32),
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

/// Refracts the already frosted control layer without blurring it a second time.
class GlassLens extends StatefulWidget {
  const GlassLens({
    super.key,
    required this.clipper,
    required this.center,
    required this.strength,
    this.enabled = true,
  });
  final CustomClipper<Path> clipper;
  final Offset center;
  final double strength;
  final bool enabled;
  @override
  State<GlassLens> createState() => _GlassLensState();
}

class _GlassLensState extends State<GlassLens> {
  ui.FragmentShader? shader;
  bool loading = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    load();
  }

  @override
  void didUpdateWidget(GlassLens old) {
    super.didUpdateWidget(old);
    if (!old.enabled && widget.enabled) load();
  }

  void load() {
    if (!widget.enabled ||
        !GlassPerformanceScope.highOf(context) ||
        !GlassPerformanceScope.refractionOf(context) ||
        shader != null ||
        loading ||
        !ui.ImageFilter.isShaderFilterSupported) {
      return;
    }
    loading = true;
    (_MilkGlassState.program ??= ui.FragmentProgram.fromAsset(
          'shaders/glass.frag',
        ))
        .then((p) {
          if (mounted) setState(() => shader = p.fragmentShader());
        })
        .catchError((Object _) {})
        .whenComplete(() => loading = false);
  }

  @override
  void dispose() {
    shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled ||
        !GlassPerformanceScope.highOf(context) ||
        !GlassPerformanceScope.refractionOf(context) ||
        shader == null ||
        MediaQuery.highContrastOf(context)) {
      return const SizedBox.shrink();
    }
    final ratio = MediaQuery.devicePixelRatioOf(context);
    shader!
      ..setFloat(2, widget.strength)
      ..setFloat(3, 17 * ratio)
      ..setFloat(4, 1)
      ..setFloat(5, widget.center.dx * ratio)
      ..setFloat(6, widget.center.dy * ratio);
    return ClipPath(
      clipper: widget.clipper,
      child: BackdropFilter(
        filter: ui.ImageFilter.shader(shader!),
        child: const SizedBox.expand(),
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
    duration: enabled ? RoomMotion.duration(c, RoomMotion.page) : Duration.zero,
    curve: RoomMotion.ease,
    builder: (_, t, child) => Opacity(
      opacity: t,
      child: Transform.translate(offset: Offset(0, 14 * (1 - t)), child: child),
    ),
    child: child,
  );
}
