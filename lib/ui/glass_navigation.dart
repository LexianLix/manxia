import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'localized_text.dart';
import 'materials.dart';
import 'room_motion.dart';

class RoomDestination {
  const RoomDestination(this.id, this.label, this.icon, this.activeIcon);
  final int id;
  final String label;
  final IconData icon, activeIcon;
}

const roomDestinations = [
  RoomDestination(0, '书架', Icons.auto_stories_outlined, Icons.auto_stories),
  RoomDestination(1, '发现', Icons.explore_outlined, Icons.explore),
  RoomDestination(2, '足迹', Icons.history_outlined, Icons.history),
  RoomDestination(3, '设置', Icons.tune_outlined, Icons.tune),
  RoomDestination(4, '下载', Icons.download_outlined, Icons.download),
  RoomDestination(5, '插件', Icons.extension_outlined, Icons.extension),
];

class FrostedNavigation extends StatefulWidget {
  const FrostedNavigation({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    this.highQuality = true,
    this.haptics = true,
    this.liquid = true,
    this.destinations = const [
      RoomDestination(0, '书架', Icons.auto_stories_outlined, Icons.auto_stories),
      RoomDestination(1, '发现', Icons.explore_outlined, Icons.explore),
      RoomDestination(2, '足迹', Icons.history_outlined, Icons.history),
      RoomDestination(3, '设置', Icons.tune_outlined, Icons.tune),
    ],
  });
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool highQuality, haptics, liquid;
  final List<RoomDestination> destinations;
  @override
  State<FrostedNavigation> createState() => _FrostedNavigationState();
}

class _FrostedNavigationState extends State<FrostedNavigation>
    with TickerProviderStateMixin {
  late final lens = AnimationController.unbounded(
    vsync: this,
    value: widget.selectedIndex.toDouble(),
  );
  late final tail = AnimationController.unbounded(
    vsync: this,
    value: widget.selectedIndex.toDouble(),
  );
  late final contact = AnimationController(
    vsync: this,
    duration: RoomMotion.press,
    reverseDuration: RoomMotion.feedback,
  );
  int? preview;
  bool cancelled = false, reduced = false;
  double slotWidth = 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced) settle(widget.selectedIndex.toDouble());
  }

  void spring(
    AnimationController controller,
    double target,
    SpringDescription spring,
  ) {
    final velocity = controller.velocity.clamp(-14.0, 14.0);
    controller.stop();
    if (reduced) {
      controller.value = target;
      return;
    }
    controller.animateWith(
      SpringSimulation(spring, controller.value, target, velocity),
    );
  }

  void settle(double target) {
    spring(lens, target, RoomMotion.settle);
    spring(
      tail,
      target,
      const SpringDescription(mass: 1, stiffness: 160, damping: 23),
    );
  }

  void select(int index) {
    setState(() => preview = null);
    contact.reverse();
    settle(index.toDouble());
    if (widget.selectedIndex != index) {
      if (widget.haptics) HapticFeedback.selectionClick();
      widget.onSelected(index);
    }
  }

  void scrub(double x) {
    final value = ((x - 7) / slotWidth - .5).clamp(
      0.0,
      widget.destinations.length - 1.0,
    );
    lens.stop();
    lens.value = value;
    spring(
      tail,
      value,
      const SpringDescription(mass: 1, stiffness: 160, damping: 23),
    );
    final index = value.round();
    if (preview != index) {
      setState(() => preview = index);
      if (widget.haptics) HapticFeedback.selectionClick();
    }
  }

  void cancel() {
    cancelled = true;
    setState(() => preview = null);
    contact.reverse();
    settle(widget.selectedIndex.toDouble());
  }

  @override
  void didUpdateWidget(FrostedNavigation old) {
    super.didUpdateWidget(old);
    if (old.selectedIndex != widget.selectedIndex && preview == null ||
        old.destinations.length != widget.destinations.length) {
      settle(widget.selectedIndex.toDouble());
    }
  }

  @override
  void dispose() {
    lens.dispose();
    tail.dispose();
    contact.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: LayoutBuilder(
              builder: (context, box) {
                slotWidth = (box.maxWidth - 14) / widget.destinations.length;
                return Listener(
                  onPointerDown: (_) => cancelled = false,
                  onPointerCancel: (_) => cancel(),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: (d) {
                      if (!reduced) contact.forward();
                      scrub(d.localPosition.dx);
                    },
                    onHorizontalDragUpdate: (d) => scrub(d.localPosition.dx),
                    onHorizontalDragEnd: (_) {
                      if (!cancelled) select(preview ?? widget.selectedIndex);
                    },
                    onHorizontalDragCancel: cancel,
                    child: SizedBox(
                      height: 76,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: RepaintBoundary(
                              child: MilkGlass(
                                radius: 35,
                                high: widget.highQuality,
                                blurSigma: 22,
                                tintOpacity: dark ? .52 : .36,
                                shadow: true,
                                child: const SizedBox.expand(),
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: IgnorePointer(
                              child: AnimatedBuilder(
                                animation: Listenable.merge([
                                  lens,
                                  tail,
                                  contact,
                                ]),
                                builder: (_, _) => CustomPaint(
                                  painter: WaterDropPainter(
                                    head: 7 + (lens.value + .5) * slotWidth,
                                    tail:
                                        7 +
                                        ((widget.liquid && !reduced
                                                    ? tail.value
                                                    : lens.value) +
                                                .5) *
                                            slotWidth,
                                    width: slotWidth - 3,
                                    press: reduced ? 0 : contact.value,
                                    color: scheme.primary,
                                    dark: dark,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          AnimatedBuilder(
                            animation: lens,
                            builder: (_, _) => Positioned(
                              left: 7 + lens.value * slotWidth,
                              top: 8,
                              bottom: 8,
                              width: slotWidth,
                              child: const IgnorePointer(
                                child: SizedBox(
                                  key: ValueKey('navigation-lens'),
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 7),
                            child: Row(
                              children: List.generate(
                                widget.destinations.length,
                                (index) {
                                  final item = widget.destinations[index];
                                  final label = translate(
                                    item.label,
                                    Localizations.localeOf(context),
                                  );
                                  return Expanded(
                                    child: Semantics(
                                      button: true,
                                      selected: widget.selectedIndex == index,
                                      label: label,
                                      excludeSemantics: true,
                                      onTap: () => select(index),
                                      child: Tooltip(
                                        message: label,
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(
                                            30,
                                          ),
                                          onTap: () => select(index),
                                          onTapDown: (_) {
                                            if (!reduced) contact.forward();
                                          },
                                          onTapUp: (_) => contact.reverse(),
                                          onTapCancel: () => contact.reverse(),
                                          child: SizedBox(
                                            height: 76,
                                            child: AnimatedBuilder(
                                              animation: lens,
                                              builder: (_, _) {
                                                final focus =
                                                    (1 -
                                                            (lens.value - index)
                                                                .abs())
                                                        .clamp(0.0, 1.0);
                                                return Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    Transform.translate(
                                                      offset: Offset(
                                                        0,
                                                        -2 * focus,
                                                      ),
                                                      child: Transform.scale(
                                                        scale: 1 + .1 * focus,
                                                        child: Icon(
                                                          focus > .5
                                                              ? item.activeIcon
                                                              : item.icon,
                                                          size: 23,
                                                          color: Color.lerp(
                                                            scheme.onSurface
                                                                .withValues(
                                                                  alpha: .58,
                                                                ),
                                                            scheme.primary,
                                                            focus,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 5),
                                                    Text(
                                                      label,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.fade,
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        color: Color.lerp(
                                                          scheme.onSurface
                                                              .withValues(
                                                                alpha: .60,
                                                              ),
                                                          scheme.primary,
                                                          focus,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                );
                                              },
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Two linked volumes form one closed contour. Only this small path repaints;
/// the expensive backdrop remains stationary throughout a drag or spring.
class WaterDropPainter extends CustomPainter {
  WaterDropPainter({
    required this.head,
    required this.tail,
    required this.width,
    required this.press,
    required this.color,
    required this.dark,
  });
  final double head, tail, width, press;
  final Color color;
  final bool dark;
  Path contour() {
    final distance = (head - tail).abs();
    final half = 28 - press * 1.2;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(head, 38),
            width: width,
            height: half * 2,
          ),
          const Radius.circular(28),
        ),
      );
    if (distance < .6) return path;
    final radius = math.min(21.0, distance * .55);
    final droplet = Path()
      ..addOval(Rect.fromCircle(center: Offset(tail, 38), radius: radius));
    final mid = (head + tail) / 2;
    final neck = (18 - distance * .10).clamp(4.0, 17.0);
    final bridge = Path()
      ..moveTo(tail, 38 - radius * .85)
      ..cubicTo(mid, 38 - neck, mid, 38 - neck, head, 38 - half * .8)
      ..lineTo(head, 38 + half * .8)
      ..cubicTo(mid, 38 + neck, mid, 38 + neck, tail, 38 + radius * .85)
      ..close();
    return Path.combine(
      PathOperation.union,
      Path.combine(PathOperation.union, path, droplet),
      bridge,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = contour();
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: dark ? .19 : .83),
            color.withValues(alpha: dark ? .25 : .20),
            Colors.white.withValues(alpha: dark ? .07 : .52),
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: dark ? .35 : .96),
    );
  }

  @override
  bool shouldRepaint(WaterDropPainter old) =>
      head != old.head ||
      tail != old.tail ||
      width != old.width ||
      press != old.press ||
      color != old.color ||
      dark != old.dark;
}

class ReadingAtmosphere extends StatelessWidget {
  const ReadingAtmosphere({
    super.key,
    required this.color,
    this.highQuality = true,
  });
  final Color color;
  final bool highQuality;
  @override
  Widget build(BuildContext context) {
    if (!highQuality || MediaQuery.highContrastOf(context)) {
      return const SizedBox.expand();
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedContainer(
          duration: Duration(
            milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 360,
          ),
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-.6, .95),
              radius: .85,
              colors: [
                color.withValues(alpha: dark ? .28 : .20),
                color.withValues(alpha: dark ? .07 : .04),
                Colors.transparent,
              ],
              stops: const [0, .6, 1],
            ),
          ),
        ),
      ),
    );
  }
}
