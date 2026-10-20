import 'localized_text.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../data/comic.dart';
import '../data/library.dart';
import 'book_object.dart';
import 'collection_motion.dart';
import 'materials.dart';

class LivingShelf extends StatefulWidget {
  const LivingShelf({
    super.key,
    required this.books,
    required this.library,
    required this.web,
    required this.onOpen,
    this.onFocus,
    this.onBookOrigin,
  });
  final List<Comic> books;
  final Library library;
  final bool web;
  final ValueChanged<Comic> onOpen;
  final ValueChanged<Comic>? onFocus;
  final void Function(Comic, Rect)? onBookOrigin;
  @override
  State<LivingShelf> createState() => _LivingShelfState();
}

class _LivingShelfState extends State<LivingShelf>
    with TickerProviderStateMixin {
  late final position = AnimationController.unbounded(
    vsync: this,
    value:
        widget.books.length * 1000 +
        math.min(3, widget.books.length - 1).toDouble(),
  )..addListener(_detent);
  final pointer = ValueNotifier(Offset.zero);
  final bookKeys = <int, GlobalKey>{};
  late final entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 640),
  );
  late final lean = AnimationController.unbounded(vsync: this);
  bool entered = false;
  Color ambient = const Color(0xff8baf99);
  StreamSubscription<AccelerometerEvent>? tilt;
  double gap = 50;
  int last = -1;
  int index(int i) =>
      ((i % widget.books.length) + widget.books.length) % widget.books.length;
  int get selected => index(position.value.round());
  bool get animate =>
      widget.library.motion && !MediaQuery.disableAnimationsOf(context);
  @override
  void initState() {
    super.initState();
    if (!kIsWeb && widget.library.option<bool>('tilt', false)) {
      tilt = accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval)
          .listen(
            (e) => pointer.value = Offset(
              (e.x / 6).clamp(-1, 1),
              (e.y / 6).clamp(-1, 1),
            ),
            onError: (_) {},
          );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!entered) {
      entered = true;
      if (animate) {
        entrance.forward();
      } else {
        entrance.value = 1;
      }
    } else if (!animate) {
      entrance.value = 1;
      lean.value = 0;
    }
  }

  void openBook(Comic comic) {
    final object = bookKeys[position.value.round()]?.currentContext
        ?.findRenderObject();
    if (object is RenderBox && object.hasSize) {
      widget.onBookOrigin?.call(
        comic,
        object.localToGlobal(Offset.zero) & object.size,
      );
    }
    widget.onOpen(comic);
  }

  void _detent() {
    final current = position.value.round();
    if (current != last) {
      last = current;
      if (mounted) setState(() {});
      final focused = widget.books[selected];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onFocus?.call(focused);
      });
      if (widget.library.option<bool>('haptics', true)) {
        HapticFeedback.selectionClick();
      }
    }
  }

  void snap(double target, {double velocity = 0}) {
    position.stop();
    if (!animate) {
      position.value = target;
      return;
    }
    position.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 210, damping: 22),
        position.value,
        target,
        velocity,
      ),
    );
  }

  @override
  void dispose() {
    tilt?.cancel();
    position.dispose();
    pointer.dispose();
    entrance.dispose();
    lean.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final comic = widget.books[selected];
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: .63);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).width < 600 ? 330 : 365,
          child: LayoutBuilder(
            builder: (context, box) {
              gap = box.maxWidth < 500 ? 33 : 53;
              final scale = (box.maxWidth / 700).clamp(.72, 1.04);
              return MouseRegion(
                onHover: (e) {
                  if (widget.library.option<bool>('parallax', true)) {
                    pointer.value = Offset(
                      (e.localPosition.dx / box.maxWidth - .5) * 2,
                      (e.localPosition.dy / box.maxHeight - .5) * 2,
                    );
                  }
                },
                onExit: (_) => pointer.value = Offset.zero,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (_) {
                    position.stop();
                    lean.stop();
                  },
                  onHorizontalDragUpdate: (d) {
                    position.value -= d.delta.dx / (gap * 1.35);
                    lean.value = animate ? (d.delta.dx / 16).clamp(-1, 1) : 0;
                  },
                  onHorizontalDragEnd: (d) {
                    lean.animateTo(
                      0,
                      duration: Duration(milliseconds: animate ? 320 : 0),
                      curve: Curves.easeOutCubic,
                    );
                    final velocity = -(d.primaryVelocity ?? 0) / (gap * 1.35);
                    final target =
                        (position.value + (velocity * .18).clamp(-4, 4))
                            .roundToDouble();
                    snap(target, velocity: velocity);
                  },
                  onHorizontalDragCancel: () {
                    lean.animateTo(
                      0,
                      duration: const Duration(milliseconds: 200),
                    );
                    snap(position.value.roundToDouble());
                  },
                  child: AnimatedBuilder(
                    animation: Listenable.merge([
                      position,
                      pointer,
                      entrance,
                      lean,
                    ]),
                    builder: (context, _) {
                      final center = position.value.round();
                      bookKeys.removeWhere(
                        (logical, _) => (logical - center).abs() > 7,
                      );
                      final order = List.generate(11, (i) => center + i - 5)
                        ..sort(
                          (a, b) => (b - position.value).abs().compareTo(
                            (a - position.value).abs(),
                          ),
                        );
                      return Stack(
                        clipBehavior: Clip.hardEdge,
                        children: [
                          Positioned.fill(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 380),
                              decoration: BoxDecoration(
                                gradient: RadialGradient(
                                  center: const Alignment(0, .2),
                                  radius: .75,
                                  colors: [
                                    ambient.withValues(
                                      alpha:
                                          widget.library.option<String>(
                                                'quality',
                                                'high',
                                              ) ==
                                              'low'
                                          ? .035
                                          : .13,
                                    ),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 25,
                            child: Container(
                              height: 1,
                              color: Theme.of(
                                context,
                              ).dividerColor.withValues(alpha: .45),
                            ),
                          ),
                          for (final logical in order) ...[
                            Builder(
                              builder: (context) {
                                final distance = logical - position.value;
                                final focus = math
                                    .pow((1 - distance.abs()).clamp(0, 1), 1.5)
                                    .toDouble();
                                final x =
                                    box.maxWidth / 2 -
                                    95 * scale +
                                    distance * gap +
                                    (distance > 0
                                        ? 108 * scale * (1 - focus)
                                        : 0) +
                                    pointer.value.dx * 4;
                                final y =
                                    70 -
                                    focus * 64 +
                                    distance.abs() * 2 +
                                    pointer.value.dy * 3;
                                final item = widget.books[index(logical)];
                                final delay = distance.abs().clamp(0, 5) * .055;
                                final arrival = animate
                                    ? Curves.easeOutCubic.transform(
                                        ((entrance.value - delay) / (1 - delay))
                                            .clamp(0.0, 1.0),
                                      )
                                    : 1.0;
                                return Positioned(
                                  key: ValueKey('paint-$logical'),
                                  left: x + (1 - arrival) * distance * 7,
                                  top: y + (1 - arrival) * 48,
                                  width: 200 * scale,
                                  height: 280 * scale,
                                  child: IgnorePointer(
                                    child: Opacity(
                                      opacity: arrival,
                                      child: Transform(
                                        alignment: Alignment.center,
                                        transform: Matrix4.identity()
                                          ..setEntry(3, 2, .0012)
                                          ..rotateY(
                                            distance.clamp(-2, 2) * .075 +
                                                pointer.value.dx * .06 +
                                                lean.value * .13 * focus,
                                          )
                                          ..rotateX(pointer.value.dy * .04)
                                          ..rotateZ(-lean.value * .045 * focus),
                                        child: AnimatedSlide(
                                          offset: Offset(
                                            0,
                                            widget.library.updates[item
                                                        .path]?['changed'] ==
                                                    true
                                                ? -.03
                                                : 0,
                                          ),
                                          duration: Duration(
                                            milliseconds: animate ? 280 : 0,
                                          ),
                                          curve: Curves.easeOutBack,
                                          child: BookObject(
                                            item,
                                            key: bookKeys.putIfAbsent(
                                              logical,
                                              GlobalKey.new,
                                            ),
                                            web: widget.web,
                                            number: index(logical) + 1,
                                            exposure: focus,
                                            light: pointer.value.dx,
                                            bookmark:
                                                widget.library.record(item) !=
                                                null,
                                            onColor:
                                                logical == center &&
                                                    widget.library.option<bool>(
                                                      'coverColor',
                                                      true,
                                                    )
                                                ? (color) {
                                                    if (mounted &&
                                                        ambient != color) {
                                                      setState(
                                                        () => ambient = color,
                                                      );
                                                    }
                                                  }
                                                : null,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                            Builder(
                              builder: (context) {
                                final d = logical - position.value;
                                final focus = math
                                    .pow((1 - d.abs()).clamp(0, 1), 1.5)
                                    .toDouble();
                                final item = widget.books[index(logical)];
                                return Positioned(
                                  key: ValueKey('hit-$logical'),
                                  left:
                                      box.maxWidth / 2 -
                                      78 * scale +
                                      d * gap +
                                      (d > 0 ? 108 * scale * (1 - focus) : 0),
                                  top: 95 - focus * 64 + d.abs() * 2,
                                  width: (34 + 129 * focus) * scale,
                                  height: 210 * scale,
                                  child: Semantics(
                                    button: true,
                                    label: focus > .8
                                        ? '查看${item.title}'
                                        : '选择${item.title}',
                                    child: Tooltip(
                                      message: item.title,
                                      child: GestureDetector(
                                        onTap: () {
                                          if (focus > .8) {
                                            openBook(item);
                                          } else {
                                            snap(logical.toDouble());
                                          }
                                        },
                                        child: MouseRegion(
                                          cursor: SystemMouseCursors.click,
                                          child: Container(
                                            color: Colors.transparent,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
        Row(
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: Duration(milliseconds: animate ? 180 : 0),
                transitionBuilder: (child, a) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(
                    position:
                        Tween(
                          begin: const Offset(0, .16),
                          end: Offset.zero,
                        ).animate(
                          CurvedAnimation(
                            parent: a,
                            curve: Curves.easeOutCubic,
                          ),
                        ),
                    child: child,
                  ),
                ),
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.centerLeft,
                  children: [...previous, ?current],
                ),
                child: Column(
                  key: ValueKey(comic.path),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LocalizedText(
                      comic.title,
                      style: const TextStyle(fontSize: 26, letterSpacing: 1),
                    ),
                    const SizedBox(height: 8),
                    LocalizedText(
                      widget.library.record(comic) == null
                          ? '动漫屋 · 拖动书架，挑选故事'
                          : '书签 · ${widget.library.record(comic)!.chapterTitle}',
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: '上一本',
              onPressed: () => snap(position.value.roundToDouble() - 1),
              icon: const Icon(Icons.chevron_left, size: 21),
            ),
            LocalizedText(
              '${(selected + 1).toString().padLeft(2, '0')} / ${widget.books.length.toString().padLeft(2, '0')}',
              style: TextStyle(fontSize: 11, color: muted),
            ),
            IconButton(
              tooltip: '下一本',
              onPressed: () => snap(position.value.roundToDouble() + 1),
              icon: const Icon(Icons.chevron_right, size: 21),
            ),
          ],
        ),
        const SizedBox(height: 21),
        Row(
          children: [
            FilledButton.icon(
              onPressed: () => openBook(comic),
              icon: const Icon(Icons.menu_book_outlined, size: 17),
              label: const LocalizedText(
                '翻开这本漫画',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(width: 12),
            MilkGlass(
              radius: 8,
              high: widget.library.option<String>('quality', 'high') == 'high',
              child: IconButton(
                tooltip: widget.library.contains(comic) ? '移出收藏' : '加入收藏',
                onPressed: () => collectWithMotion(
                  context,
                  comic,
                  widget.library,
                  widget.web,
                ),
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, a) => ScaleTransition(
                    scale: CurvedAnimation(
                      parent: a,
                      curve: Curves.easeOutBack,
                    ),
                    child: child,
                  ),
                  child: Icon(
                    widget.library.contains(comic)
                        ? Icons.bookmark
                        : Icons.bookmark_border,
                    key: ValueKey(widget.library.contains(comic)),
                    size: 20,
                  ),
                ),
              ),
            ),
            const Spacer(),
            if (MediaQuery.sizeOf(context).width > 700)
              LocalizedText(
                '惯性滑动 · 循环书架',
                style: TextStyle(fontSize: 10, color: muted),
              ),
          ],
        ),
      ],
    );
  }
}

class OpenBookTransition extends StatelessWidget {
  const OpenBookTransition({
    super.key,
    required this.animation,
    required this.comic,
    required this.web,
    required this.child,
    this.origin,
  });
  final Animation<double> animation;
  final Comic comic;
  final bool web;
  final Widget child;
  final Rect? origin;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    builder: (context, _) {
      final progress = animation.value;
      final screen = MediaQuery.sizeOf(context);
      final move = Curves.easeInOutCubic.transform(
        (progress / .66).clamp(0.0, 1.0),
      );
      final target = Rect.fromCenter(
        center: Offset(screen.width / 2, screen.height * .43),
        width: 200,
        height: 280,
      );
      final rect = Rect.lerp(origin ?? target.translate(0, 35), target, move)!;
      final opening = Curves.easeInOutCubic.transform(
        ((progress - .30) / .52).clamp(0.0, 1.0),
      );
      final flatten = ((progress - .17) / .23).clamp(0.0, 1.0);
      final reveal = Curves.easeOutCubic.transform(
        ((progress - .60) / .40).clamp(0.0, 1.0),
      );
      final veil = ((progress - .08) / .55).clamp(0.0, 1.0);
      return Stack(
        children: [
          Positioned.fill(
            child: ClipRect(
              child: BackdropFilter(
                enabled: progress < .999,
                filter: ui.ImageFilter.blur(sigmaX: 4 * veil, sigmaY: 4 * veil),
                child: ColoredBox(
                  color: Theme.of(
                    context,
                  ).colorScheme.surface.withValues(alpha: veil),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Opacity(
              opacity: reveal,
              child: Transform.translate(
                offset: Offset(0, 18 * (1 - reveal)),
                child: child,
              ),
            ),
          ),
          Positioned.fromRect(
            rect: rect,
            child: IgnorePointer(
              child: Opacity(
                opacity: 1 - reveal,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (flatten < 1)
                      Positioned.fill(
                        child: Opacity(
                          opacity: 1 - flatten,
                          child: BookObject(comic, web: web),
                        ),
                      ),
                    if (flatten > 0)
                      Positioned.fill(
                        child: Opacity(
                          opacity: flatten,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 12, 20, 6),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Positioned.fill(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: const Color(0xfffafbf5),
                                      border: Border.all(
                                        color: const Color(0xffd6ddcf),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: .18,
                                          ),
                                          blurRadius: 26,
                                          offset: const Offset(10, 18),
                                        ),
                                      ],
                                    ),
                                    child: Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(20),
                                        child: LocalizedText(
                                          comic.title,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Color(0xff526d60),
                                            fontSize: 23,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned.fill(
                                  child: Transform(
                                    alignment: Alignment.centerLeft,
                                    transform: Matrix4.identity()
                                      ..setEntry(3, 2, .002)
                                      ..rotateY(-math.pi * .83 * opening),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        ComicCover(comic, web: web),
                                        DecoratedBox(
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                Colors.black.withValues(
                                                  alpha: .22 * opening,
                                                ),
                                                Colors.white.withValues(
                                                  alpha: .15 * opening,
                                                ),
                                                Colors.transparent,
                                              ],
                                              stops: const [0, .13, 1],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}
