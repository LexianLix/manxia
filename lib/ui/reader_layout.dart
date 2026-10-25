import 'package:flutter/material.dart';
import 'reader_surfaces.dart';
import 'room_motion.dart';
import 'localized_text.dart';

/// Keeps the last decoded layout visible until its replacement is ready.
/// Each visible layer owns its controller; a rapid reversal starts at the
/// currently painted opacities rather than replacing a half-finished frame.
class ReaderLayout extends StatefulWidget {
  const ReaderLayout({
    super.key,
    required this.urls,
    required this.web,
    required this.mode,
    required this.rtl,
    required this.paired,
    required this.startPage,
    required this.position,
    required this.control,
    required this.onPosition,
    required this.onReady,
    required this.onLoadError,
    required this.paper,
    required this.crop,
    required this.autoCrop,
    required this.decodeWidth,
    required this.speed,
  });
  final List<String> urls;
  final bool web, rtl, paired, paper, autoCrop;
  final String mode;
  final int startPage, decodeWidth;
  final double position, speed, crop;
  final ReaderControl control;
  final PagePosition onPosition;
  final VoidCallback onReady, onLoadError;

  @override
  State<ReaderLayout> createState() => _ReaderLayoutState();
}

typedef _Layout = ({String mode, bool rtl, bool paired});

class _ReaderLayoutState extends State<ReaderLayout>
    with SingleTickerProviderStateMixin {
  late final clock = AnimationController(
    vsync: this,
    duration: RoomMotion.page,
    value: 1,
  )..addStatusListener(finished);
  final layers = <_LayoutLayer>[];
  _LayoutLayer? current, pending;
  late int page = widget.startPage;
  late int stripPage = page;
  late double stripPosition = widget.position;
  bool failed = false;
  _Layout get layout =>
      (mode: widget.mode, rtl: widget.rtl, paired: widget.paired);
  double opacity(_LayoutLayer layer) =>
      layer.from +
      ((identical(layer, current) ? 1 : 0) - layer.from) *
          RoomMotion.ease.transform(clock.value);

  @override
  void initState() {
    super.initState();
    widget.control.addListener(jump);
    prepare();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) clock.value = 1;
  }

  @override
  void didUpdateWidget(ReaderLayout old) {
    super.didUpdateWidget(old);
    if (layout != (pending ?? current)?.layout) prepare();
  }

  void discard(_LayoutLayer layer) {
    layers.remove(layer);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => layer.control.dispose(),
    );
  }

  void prepare({bool force = false}) {
    if (pending != null) discard(pending!);
    pending = null;
    for (final old in layers.toList()) {
      if (!identical(old, current) && opacity(old) < 1 / 255) discard(old);
    }
    failed = false;
    if (!force && current?.layout == layout) return;
    final next = _LayoutLayer(
      layout,
      page,
      stripPage == page ? stripPosition : 0,
    );
    final previous = current;
    if (previous != null && previous.control.transformPage == page) {
      next.control.transform = Matrix4.copy(previous.control.transform);
    }
    layers.add(next);
    pending = next;
  }

  void jump() {
    page = widget.control.page.clamp(0, widget.urls.length - 1);
    stripPage = page;
    stripPosition = widget.control.position.clamp(0, 1);
    if (widget.mode == 'strip' && stripPosition > 0) {
      setState(() => prepare(force: true));
      return;
    }
    current?.control.go(page);
    if (pending != null) setState(prepare);
  }

  void positioned(_LayoutLayer layer, int p, double f) {
    layer.page = p;
    layer.position = f;
    if (!identical(layer, current)) return;
    page = p;
    if (layer.layout.mode == 'strip') {
      stripPage = p;
      stripPosition = f;
    }
    widget.control.target = layer.control.target;
    widget.onPosition(p, layer.layout.mode == 'strip' ? f : 0);
  }

  void ready(_LayoutLayer layer) {
    if (!mounted || !identical(layer, pending) || failed) return;
    final first = current == null;
    final poses = {for (final old in layers) old: opacity(old)};
    setState(() {
      for (final old in layers) {
        old.from = poses[old]!;
      }
      current = layer;
      pending = null;
      page = layer.page;
    });
    if (first || MediaQuery.disableAnimationsOf(context)) {
      clock.value = 1;
      finished(AnimationStatus.completed);
    } else {
      clock.forward(from: 0);
    }
    positioned(layer, layer.page, layer.position);
    if (first) widget.onReady();
  }

  void error(_LayoutLayer layer) {
    if (!mounted || !identical(layer, pending)) return;
    setState(() => failed = true);
    if (current == null) widget.onLoadError();
  }

  void finished(AnimationStatus status) {
    if (!mounted || status != AnimationStatus.completed) return;
    final obsolete = layers
        .where((l) => !identical(l, current) && !identical(l, pending))
        .toList();
    if (obsolete.isEmpty) return;
    setState(() {
      for (final layer in obsolete) {
        discard(layer);
      }
    });
  }

  @override
  void dispose() {
    widget.control.removeListener(jump);
    clock.dispose();
    for (final layer in layers) {
      layer.control.dispose();
    }
    super.dispose();
  }

  Widget body(_LayoutLayer layer) {
    final active = identical(layer, current) && pending == null;
    return layer.layout.mode == 'strip'
        ? StripSurface(
            urls: widget.urls,
            web: widget.web,
            startPage: layer.startPage,
            position: layer.startPosition,
            control: layer.control,
            onPosition: (p, f) => positioned(layer, p, f),
            onReady: () => ready(layer),
            onLoadError: () => error(layer),
            speed: active ? widget.speed : 0,
            crop: widget.crop,
            autoCrop: widget.autoCrop,
            decodeWidth: widget.decodeWidth,
          )
        : PagedSurface(
            urls: widget.urls,
            web: widget.web,
            startPage: layer.startPage,
            control: layer.control,
            onPosition: (p, f) => positioned(layer, p, f),
            onReady: () => ready(layer),
            onLoadError: () => error(layer),
            rtl: layer.layout.rtl,
            vertical: layer.layout.mode == 'vertical',
            doublePage: layer.layout.paired,
            paper: widget.paper,
            crop: widget.crop,
            autoCrop: widget.autoCrop,
            decodeWidth: widget.decodeWidth,
          );
  }

  @override
  Widget build(BuildContext context) {
    final children = {
      for (final layer in layers) layer: RepaintBoundary(child: body(layer)),
    };
    return AnimatedBuilder(
      animation: clock,
      builder: (_, _) => Stack(
        fit: StackFit.expand,
        children: [
          for (final layer in children.keys)
            KeyedSubtree(
              key: ObjectKey(layer),
              child: IgnorePointer(
                ignoring: !identical(layer, current) || pending != null,
                child: ExcludeSemantics(
                  excluding: !identical(layer, current) || pending != null,
                  child: ExcludeFocus(
                    excluding: !identical(layer, current) || pending != null,
                    child: TickerMode(
                      enabled:
                          identical(layer, current) ||
                          identical(layer, pending),
                      child: Opacity(
                        opacity: identical(layer, pending) ? 0 : opacity(layer),
                        child: children[layer],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (failed && current != null)
            Align(
              alignment: Alignment.center,
              child: FilledButton.tonalIcon(
                onPressed: () => setState(prepare),
                icon: const Icon(Icons.refresh),
                label: const LocalizedText('新布局图片未就绪，点击重试'),
              ),
            ),
        ],
      ),
    );
  }
}

class _LayoutLayer {
  _LayoutLayer(this.layout, this.startPage, this.startPosition)
    : page = startPage,
      position = startPosition {
    control.transformPage = startPage;
  }
  final _Layout layout;
  final int startPage;
  final double startPosition;
  final control = ReaderControl();
  int page;
  double position, from = 0;
}
