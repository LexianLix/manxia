import 'localized_text.dart';
import 'dart:async';
import 'dart:math' as math;
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
import 'room_motion.dart';
import 'room_backdrop.dart';
import 'shelf_orbit.dart';

class LivingShelf extends StatefulWidget {
  const LivingShelf({
    super.key,
    required this.books,
    required this.library,
    required this.web,
    required this.onOpen,
    this.onFocus,
    this.onBookOrigin,
    this.onAmbientColor,
  });
  final List<Comic> books;
  final Library library;
  final bool web;
  final ValueChanged<Comic> onOpen;
  final ValueChanged<Comic>? onFocus;
  final void Function(Comic, Rect)? onBookOrigin;
  final ValueChanged<Color>? onAmbientColor;
  @override
  State<LivingShelf> createState() => _LivingShelfState();
}

class _LivingShelfState extends State<LivingShelf>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final position = AnimationController.unbounded(
    vsync: this,
    value: widget.books.length * 1000.0,
  )..addListener(_detent);
  final pointer = ValueNotifier(Offset.zero);
  final bookKeys = <int, GlobalKey>{};
  late final entrance = AnimationController(
    vsync: this,
    duration: RoomMotion.arrival,
  );
  late final AnimationController parallax =
      AnimationController(vsync: this, duration: RoomMotion.feedback)
        ..addListener(() {
          pointer.value = Offset.lerp(
            pointerFrom,
            pointerTo,
            RoomMotion.ease.transform(parallax.value),
          )!;
        });
  Offset pointerFrom = Offset.zero, pointerTo = Offset.zero;
  double? intendedPosition;
  bool entered = false;
  Color ambient = const Color(0xff8baf99);
  StreamSubscription<AccelerometerEvent>? tilt;
  double dragExtent = 130;
  Duration lastHaptic = Duration.zero;
  int last = -1;
  int index(int i) =>
      ((i % widget.books.length) + widget.books.length) % widget.books.length;
  int get selected => index(position.value.round());
  bool get animate =>
      widget.library.motion && !MediaQuery.disableAnimationsOf(context);
  bool sensorEnabled = false, foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void syncTilt() {
    final enabled =
        !kIsWeb &&
        foreground &&
        animate &&
        TickerMode.valuesOf(context).enabled &&
        widget.library.option<bool>('tilt', false);
    if (enabled == sensorEnabled) return;
    sensorEnabled = enabled;
    tilt?.cancel();
    tilt = null;
    if (enabled) {
      tilt = accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval)
          .listen((e) {
            if (mounted && sensorEnabled) {
              aim(Offset((e.x / 6).clamp(-1, 1), (e.y / 6).clamp(-1, 1)));
            }
          }, onError: (_) {});
    } else {
      aim(Offset.zero);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (mounted) {
      syncTilt();
      if (!foreground) stopTravel();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    syncTilt();
    if (!TickerMode.valuesOf(context).enabled) stopTravel();
    if (!entered) {
      entered = true;
      if (animate) {
        entrance.forward();
      } else {
        entrance.value = 1;
      }
    } else if (!animate) {
      entrance.value = 1;
      position.stop();
      position.value = intendedPosition ?? position.value.roundToDouble();
      parallax.stop();
      pointer.value = Offset.zero;
    }
  }

  @override
  void didUpdateWidget(LivingShelf old) {
    super.didUpdateWidget(old);
    syncTilt();
    if (!sensorEnabled &&
        !widget.library.option<bool>('parallax', true) &&
        pointerTo != Offset.zero) {
      aim(Offset.zero);
    }
    if (!listEquals(
      old.books.map((c) => c.path).toList(),
      widget.books.map((c) => c.path).toList(),
    )) {
      final oldIndex =
          ((position.value.round() % old.books.length) + old.books.length) %
          old.books.length;
      final path = old.books[oldIndex].path;
      final found = widget.books.indexWhere((c) => c.path == path);
      position.stop();
      intendedPosition = null;
      bookKeys.clear();
      position.value =
          widget.books.length * 1000 + (found < 0 ? 0 : found).toDouble();
    }
  }

  void aim(Offset target) {
    if (!mounted) return;
    if (!animate) {
      pointer.value = Offset.zero;
      return;
    }
    pointerFrom = pointer.value;
    pointerTo = target;
    parallax.forward(from: 0);
  }

  Rect? bookBounds() {
    final object = bookKeys[selected]?.currentContext?.findRenderObject();
    return object is RenderBox && object.hasSize
        ? MatrixUtils.transformRect(
            object.getTransformTo(null),
            Offset.zero & object.size,
          )
        : null;
  }

  void openBook(Comic comic) {
    position.stop();
    parallax.stop();
    intendedPosition = null;
    final bounds = bookBounds();
    if (bounds != null) widget.onBookOrigin?.call(comic, bounds);
    widget.onOpen(comic);
  }

  void _detent() {
    final current = position.value.round();
    if (current != last) {
      last = current;
      if (mounted) setState(() {});
      final focused = widget.books[selected];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.books[selected].path == focused.path) {
          widget.onFocus?.call(focused);
        }
      });
      final now = WidgetsBinding.instance.currentSystemFrameTimeStamp;
      if (widget.library.option<bool>('haptics', true) &&
          now - lastHaptic > const Duration(milliseconds: 70)) {
        lastHaptic = now;
        HapticFeedback.selectionClick();
      }
    }
  }

  void step(int delta) {
    if (widget.books.length < 2) return;
    snap(
      (position.isAnimating
              ? intendedPosition ?? position.value.roundToDouble()
              : position.value.roundToDouble()) +
          delta,
    );
  }

  void snap(double target, {double? velocity}) {
    final carried =
        velocity ?? (position.isAnimating ? position.velocity : 0.0);
    position.stop();
    intendedPosition = target;
    if (!animate) {
      position.value = target;
      return;
    }
    position.animateWith(
      SpringSimulation(
        RoomMotion.settle,
        position.value,
        target,
        carried.clamp(-18, 18),
      ),
    );
  }

  void stopTravel() {
    if (!position.isAnimating) return;
    position.stop();
    intendedPosition = null;
    position.value = position.value.roundToDouble();
  }

  void release(double velocity) {
    if (!animate) {
      snap(position.value.roundToDouble());
      return;
    }
    final glide = ShelfGlideSimulation(position.value, velocity);
    intendedPosition = glide.target;
    position.animateWith(glide);
  }

  Widget orbit(BuildContext context) => SizedBox(
    key: const ValueKey('shelf-orbit'),
    height: MediaQuery.sizeOf(context).width < 600 ? 270 : 310,
    child: LayoutBuilder(
      builder: (context, box) {
        final count = widget.books.length;
        final period = math.min(9, count);
        final density = switch (widget.library.option<String>(
          'shelfDensity',
          'balanced',
        )) {
          'compact' => .9,
          'airy' => 1.1,
          _ => 1.0,
        };
        final radius =
            math.min(box.maxWidth * (count == 2 ? .25 : .48), 310.0) * density;
        final bookWidth = (box.maxWidth * .40).clamp(140.0, 180.0);
        final bookHeight = bookWidth * 1.5;
        dragExtent = (radius * 2 * math.pi / period).clamp(90.0, 200.0);
        return MouseRegion(
          onHover: (e) {
            if (widget.library.option<bool>('parallax', true)) {
              aim(
                Offset(
                  (e.localPosition.dx / box.maxWidth - .5) * 2,
                  (e.localPosition.dy / box.maxHeight - .5) * 2,
                ),
              );
            }
          },
          onExit: (_) => aim(Offset.zero),
          child: Listener(
            onPointerDown: (_) {
              position.stop();
              intendedPosition = null;
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (_) {},
              onHorizontalDragUpdate: (d) {
                if (count < 2) return;
                position.value -= d.delta.dx / dragExtent;
              },
              onHorizontalDragEnd: (d) {
                if (count > 1) release(-(d.primaryVelocity ?? 0) / dragExtent);
              },
              onHorizontalDragCancel: () =>
                  snap(position.value.roundToDouble()),
              child: AnimatedBuilder(
                animation: Listenable.merge([position, pointer, entrance]),
                builder: (context, _) {
                  final center = position.value.round();
                  final slots = List.generate(
                    math.min(7, count),
                    (i) => center + i - math.min(7, count) ~/ 2,
                  );
                  final poses = {
                    for (final slot in slots)
                      slot: ShelfOrbitPose(slot - position.value, period),
                  };
                  slots.sort(
                    (a, b) => poses[a]!.depth.compareTo(poses[b]!.depth),
                  );
                  final arrival = animate
                      ? RoomMotion.ease.transform(entrance.value)
                      : 1.0;
                  return Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: const Alignment(0, .35),
                              radius: .8,
                              colors: [
                                (widget.library.option<bool>('coverColor', true)
                                        ? ambient
                                        : Theme.of(context).colorScheme.primary)
                                    .withValues(
                                      alpha:
                                          widget.library.option<String>(
                                                'quality',
                                                'high',
                                              ) ==
                                              'low'
                                          ? .025
                                          : .065,
                                    ),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                      for (final slot in slots)
                        Builder(
                          key: ValueKey(
                            'orbit-${widget.books[index(slot)].path}',
                          ),
                          builder: (context) {
                            final pose = poses[slot]!;
                            final real = index(slot);
                            final item = widget.books[real];
                            final focused = slot == center;
                            return Positioned(
                              left:
                                  box.maxWidth / 2 -
                                  bookWidth / 2 +
                                  radius * pose.horizontal +
                                  pointer.value.dx * 3,
                              top:
                                  12 +
                                  pose.vertical +
                                  pointer.value.dy * 2 +
                                  (1 - arrival) * 10,
                              width: bookWidth,
                              height: bookHeight,
                              child: IgnorePointer(
                                ignoring: pose.opacity < .3,
                                child: Opacity(
                                  opacity: pose.opacity * arrival,
                                  child: Transform(
                                    alignment: Alignment.center,
                                    transform: Matrix4.identity()
                                      ..setEntry(3, 2, .001)
                                      ..scaleByDouble(
                                        pose.scale,
                                        pose.scale,
                                        1,
                                        1,
                                      )
                                      ..rotateY(
                                        pose.yaw + pointer.value.dx * .025,
                                      ),
                                    child: Semantics(
                                      button: true,
                                      label: focused
                                          ? '查看${item.title}'
                                          : '选择${item.title}',
                                      child: Tooltip(
                                        message: item.title,
                                        child: GestureDetector(
                                          onTap: () {
                                            if (focused) {
                                              openBook(item);
                                            } else {
                                              snap(slot.toDouble());
                                            }
                                          },
                                          child: MouseRegion(
                                            cursor: SystemMouseCursors.click,
                                            child: RepaintBoundary(
                                              child: BookFlight(
                                                enabled: focused,
                                                child: BookObject(
                                                  item,
                                                  key: bookKeys.putIfAbsent(
                                                    real,
                                                    GlobalKey.new,
                                                  ),
                                                  web: widget.web,
                                                  number: real + 1,
                                                  exposure: 1,
                                                  flattening: .58,
                                                  light: 0,
                                                  bookmark:
                                                      widget.library.record(
                                                        item,
                                                      ) !=
                                                      null,
                                                  onColor:
                                                      focused &&
                                                          widget.library
                                                              .option<bool>(
                                                                'coverColor',
                                                                true,
                                                              )
                                                      ? (color) {
                                                          if (mounted &&
                                                              ambient !=
                                                                  color) {
                                                            setState(
                                                              () => ambient =
                                                                  color,
                                                            );
                                                            widget
                                                                .onAmbientColor
                                                                ?.call(color);
                                                          }
                                                        }
                                                      : null,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    ),
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    tilt?.cancel();
    position.dispose();
    pointer.dispose();
    entrance.dispose();
    parallax.dispose();
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
        orbit(context),
        Row(
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: animate ? RoomMotion.feedback : Duration.zero,
                transitionBuilder: (child, a) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(
                    position:
                        Tween(
                          begin: const Offset(0, .16),
                          end: Offset.zero,
                        ).animate(
                          CurvedAnimation(parent: a, curve: RoomMotion.ease),
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
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
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
              onPressed: () => step(-1),
              icon: const Icon(Icons.chevron_left, size: 21),
            ),
            LocalizedText(
              '${(selected + 1).toString().padLeft(2, '0')} / ${widget.books.length.toString().padLeft(2, '0')}',
              style: TextStyle(fontSize: 11, color: muted),
            ),
            IconButton(
              tooltip: '下一本',
              onPressed: () => step(1),
              icon: const Icon(Icons.chevron_right, size: 21),
            ),
          ],
        ),
        const SizedBox(height: 12),
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
                  origin: bookBounds(),
                ),
                icon: AnimatedSwitcher(
                  duration: RoomMotion.duration(context, RoomMotion.feedback),
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

/// The cover travels in the Hero layer; this layer reveals the reading room.
/// A single reversible progress value also supports an early back action.
class OpenBookTransition extends StatelessWidget {
  const OpenBookTransition({
    super.key,
    required this.animation,
    required this.comic,
    required this.web,
    required this.child,
    this.origin,
    this.library,
  });
  final Animation<double> animation;
  final Comic comic;
  final bool web;
  final Widget child;
  final Rect? origin;
  final Library? library;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    child: child,
    builder: (context, child) {
      final t = const Interval(
        .45,
        .95,
        curve: RoomMotion.ease,
      ).transform(animation.value);
      final background = const Interval(
        0,
        .24,
        curve: RoomMotion.ease,
      ).transform(animation.value);
      return IgnorePointer(
        ignoring: animation.value < .12,
        child: ExcludeSemantics(
          excluding: animation.value < .12,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Opacity(
                opacity: background,
                child: library == null
                    ? ColoredBox(color: Theme.of(context).colorScheme.surface)
                    : RoomBackdrop(
                        library: library!,
                        child: const SizedBox.expand(),
                      ),
              ),
              Opacity(opacity: t, child: child),
            ],
          ),
        ),
      );
    },
  );
}
