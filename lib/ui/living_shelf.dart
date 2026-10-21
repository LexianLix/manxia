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
    duration: RoomMotion.arrival,
  );
  late final lean = AnimationController.unbounded(vsync: this);
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
            (e) => aim(Offset((e.x / 6).clamp(-1, 1), (e.y / 6).clamp(-1, 1))),
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
      position.stop();
      position.value = intendedPosition ?? position.value.roundToDouble();
      lean.value = 0;
      parallax.stop();
      pointer.value = Offset.zero;
    }
  }

  @override
  void didUpdateWidget(LivingShelf old) {
    super.didUpdateWidget(old);
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
    final object = bookKeys[position.value.round()]?.currentContext
        ?.findRenderObject();
    return object is RenderBox && object.hasSize
        ? object.localToGlobal(Offset.zero) & object.size
        : null;
  }

  void openBook(Comic comic) {
    position.stop();
    lean.stop();
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
        if (mounted) widget.onFocus?.call(focused);
      });
      if (widget.library.option<bool>('haptics', true)) {
        HapticFeedback.selectionClick();
      }
    }
  }

  void step(int delta) => snap(
    (position.isAnimating
            ? intendedPosition ?? position.value.roundToDouble()
            : position.value.roundToDouble()) +
        delta,
  );

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

  @override
  void dispose() {
    tilt?.cancel();
    position.dispose();
    pointer.dispose();
    entrance.dispose();
    lean.dispose();
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
        SizedBox(
          height: MediaQuery.sizeOf(context).width < 600 ? 330 : 365,
          child: LayoutBuilder(
            builder: (context, box) {
              gap = box.maxWidth < 500 ? 33 : 53;
              final scale = (box.maxWidth / 700).clamp(.72, 1.04);
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
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (_) {
                    position.stop();
                    intendedPosition = null;
                    lean.stop();
                  },
                  onHorizontalDragUpdate: (d) {
                    position.value -= d.delta.dx / (gap * 1.35);
                    if (animate) {
                      lean.animateTo(
                        (d.delta.dx / 16).clamp(-1, 1),
                        duration: RoomMotion.press,
                        curve: RoomMotion.ease,
                      );
                    } else {
                      lean.value = 0;
                    }
                  },
                  onHorizontalDragEnd: (d) {
                    lean.animateTo(
                      0,
                      duration: animate ? RoomMotion.page : Duration.zero,
                      curve: RoomMotion.ease,
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
                      duration: animate ? RoomMotion.feedback : Duration.zero,
                      curve: RoomMotion.ease,
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
                              duration: animate
                                  ? RoomMotion.page
                                  : Duration.zero,
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
                                    ? RoomMotion.ease.transform(
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
                                            milliseconds: animate
                                                ? RoomMotion.page.inMilliseconds
                                                : 0,
                                          ),
                                          curve: RoomMotion.ease,
                                          child: BookFlight(
                                            enabled: logical == center,
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
                                                      widget.library
                                                          .option<bool>(
                                                            'coverColor',
                                                            true,
                                                          )
                                                  ? (color) {
                                                      if (mounted &&
                                                          ambient != color) {
                                                        setState(
                                                          () => ambient = color,
                                                        );
                                                        widget.onAmbientColor
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
  });
  final Animation<double> animation;
  final Comic comic;
  final bool web;
  final Widget child;
  final Rect? origin;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    child: child,
    builder: (context, child) {
      final t = RoomMotion.travel.transform(animation.value);
      return IgnorePointer(
        ignoring: animation.value < .12,
        child: ExcludeSemantics(
          excluding: animation.value < .12,
          child: Opacity(opacity: t, child: child),
        ),
      );
    },
  );
}
