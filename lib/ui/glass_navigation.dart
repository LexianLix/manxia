import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'localized_text.dart';
import 'materials.dart';
import 'room_motion.dart';
import 'content_handoff.dart';

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
    this.anchors = const {},
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
  final Map<int, GlobalKey> anchors;
  @override
  State<FrostedNavigation> createState() => _FrostedNavigationState();
}

typedef _Slot = ({double center, double width, double alpha});

class _FrostedNavigationState extends State<FrostedNavigation>
    with TickerProviderStateMixin {
  double get target => (widget.selectedIndex + .5) / widget.destinations.length;
  late final lens = AnimationController.unbounded(vsync: this, value: target);
  late final tail = AnimationController.unbounded(vsync: this, value: target);
  late final contact = AnimationController(
    vsync: this,
    duration: RoomMotion.press,
    reverseDuration: RoomMotion.feedback,
  );
  late final members = AnimationController(
    vsync: this,
    duration: RoomMotion.page,
    value: 1,
  );
  final starts = <int, _Slot>{}, ends = <int, _Slot>{};
  final items = <int, RoomDestination>{};
  double widthFrom = 0, widthTo = 0, innerWidth = 1;
  int? preview;
  bool cancelled = false, reduced = false;
  double get lensWidth =>
      widthFrom +
      (widthTo - widthFrom) * RoomMotion.ease.transform(members.value);
  _Slot slot(int id) {
    final end = ends[id]!, start = starts[id] ?? end;
    final t = RoomMotion.ease.transform(members.value);
    return (
      center: start.center + (end.center - start.center) * t,
      width: start.width + (end.width - start.width) * t,
      alpha: start.alpha + (end.alpha - start.alpha) * t,
    );
  }

  @override
  void initState() {
    super.initState();
    widthFrom = widthTo = 1 / widget.destinations.length;
    for (var i = 0; i < widget.destinations.length; i++) {
      final item = widget.destinations[i];
      items[item.id] = item;
      ends[item.id] = (
        center: (i + .5) / widget.destinations.length,
        width: widthTo,
        alpha: 1,
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced) {
      members.value = 1;
      contact.value = 0;
      settle(target);
    }
  }

  void spring(
    AnimationController controller,
    double value,
    SpringDescription physics,
  ) {
    final velocity = controller.velocity.clamp(-14.0, 14.0);
    controller.stop();
    if (reduced) {
      controller.value = value;
      return;
    }
    controller.animateWith(
      SpringSimulation(physics, controller.value, value, velocity),
    );
  }

  void settle(double value) {
    spring(lens, value, RoomMotion.settle);
    spring(
      tail,
      value,
      const SpringDescription(mass: 1, stiffness: 160, damping: 23),
    );
  }

  void select(int index) {
    setState(() => preview = null);
    contact.reverse();
    settle((index + .5) / widget.destinations.length);
    if (widget.selectedIndex != index) {
      if (widget.haptics) HapticFeedback.selectionClick();
      widget.onSelected(index);
    }
  }

  void scrub(double x) {
    if (cancelled) return;
    final count = widget.destinations.length;
    final value = ((x - 7) / innerWidth).clamp(.5 / count, 1 - .5 / count);
    lens.stop();
    lens.value = value;
    spring(
      tail,
      value,
      const SpringDescription(mass: 1, stiffness: 160, damping: 23),
    );
    var index = 0;
    for (var i = 1; i < count; i++) {
      if ((slot(widget.destinations[i].id).center - value).abs() <
          (slot(widget.destinations[index].id).center - value).abs()) {
        index = i;
      }
    }
    if (preview != index) {
      setState(() => preview = index);
      if (widget.haptics) HapticFeedback.selectionClick();
    }
  }

  void cancel() {
    cancelled = true;
    setState(() => preview = null);
    contact.reverse();
    settle(target);
  }

  @override
  void didUpdateWidget(FrostedNavigation old) {
    super.didUpdateWidget(old);
    final changed = !listEquals(
      old.destinations.map((d) => d.id).toList(),
      widget.destinations.map((d) => d.id).toList(),
    );
    if (changed) {
      final snapshot = {for (final id in ends.keys) id: slot(id)};
      widthFrom = lensWidth;
      widthTo = 1 / widget.destinations.length;
      starts.clear();
      ends.clear();
      final currentIds = widget.destinations.map((d) => d.id).toSet();
      for (final id in items.keys.toList()) {
        if (!currentIds.contains(id)) {
          final pose = snapshot[id]!;
          if (pose.alpha < .001) {
            items.remove(id);
            continue;
          }
          starts[id] = pose;
          ends[id] = (center: pose.center, width: pose.width, alpha: 0);
        }
      }
      for (var i = 0; i < widget.destinations.length; i++) {
        final item = widget.destinations[i];
        items[item.id] = item;
        final end = (center: (i + .5) * widthTo, width: widthTo, alpha: 1.0);
        starts[item.id] =
            snapshot[item.id] ??
            (center: end.center, width: widthFrom, alpha: 0);
        ends[item.id] = end;
      }
      // A drag started against the old order cannot commit an unrelated item.
      cancelled = true;
      preview = null;
      contact.reverse();
      if (reduced) {
        members.value = 1;
      } else {
        members.forward(from: 0);
      }
      settle(target);
    } else if (old.selectedIndex != widget.selectedIndex && preview == null) {
      settle(target);
    }
  }

  @override
  void dispose() {
    lens.dispose();
    tail.dispose();
    contact.dispose();
    members.dispose();
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
                innerWidth = box.maxWidth - 14;
                final labels = widget.destinations
                    .map(
                      (item) => translate(
                        item.label,
                        Localizations.localeOf(context),
                      ),
                    )
                    .toList();
                final style = DefaultTextStyle.of(
                  context,
                ).style.copyWith(fontSize: 11);
                double measure(String text) {
                  final painter = TextPainter(
                    text: TextSpan(text: text, style: style),
                    textScaler: MediaQuery.textScalerOf(context),
                    textDirection: Directionality.of(context),
                  )..layout();
                  final width = painter.width;
                  painter.dispose();
                  return width;
                }

                final compactLabels = labels.any(
                  (text) => measure(text) > innerWidth / labels.length - 8,
                );
                final labelIndex = preview ?? widget.selectedIndex;
                final activeLabel = labels[labelIndex];
                final labelWidth = (measure(activeLabel) + 16).clamp(
                  64.0,
                  innerWidth,
                );
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
                            child: AnimatedBuilder(
                              animation: Listenable.merge([
                                lens,
                                tail,
                                contact,
                                members,
                              ]),
                              builder: (_, _) => Stack(
                                children: [
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: CustomPaint(
                                        painter: WaterDropPainter(
                                          head: 7 + lens.value * innerWidth,
                                          tail:
                                              7 +
                                              (widget.liquid && !reduced
                                                      ? tail.value
                                                      : lens.value) *
                                                  innerWidth,
                                          width: lensWidth * innerWidth - 3,
                                          press: reduced ? 0 : contact.value,
                                          color: scheme.primary,
                                          dark: dark,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    left:
                                        7 +
                                        (lens.value - lensWidth / 2) *
                                            innerWidth,
                                    top: 8,
                                    bottom: 8,
                                    width: lensWidth * innerWidth,
                                    child: const IgnorePointer(
                                      child: SizedBox(
                                        key: ValueKey('navigation-lens'),
                                      ),
                                    ),
                                  ),
                                  for (final entry in items.entries)
                                    _member(entry.value, scheme, compactLabels),
                                  if (compactLabels)
                                    Positioned(
                                      left:
                                          7 +
                                          (lens.value * innerWidth -
                                                  labelWidth / 2)
                                              .clamp(
                                                0.0,
                                                innerWidth - labelWidth,
                                              ),
                                      width: labelWidth,
                                      top: 47,
                                      bottom: 0,
                                      child: IgnorePointer(
                                        child: ExcludeSemantics(
                                          child: ContentHandoff(
                                            child: Text(
                                              activeLabel,
                                              key: ValueKey(
                                                widget
                                                    .destinations[labelIndex]
                                                    .id,
                                              ),
                                              maxLines: 1,
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: scheme.primary,
                                              ),
                                            ),
                                          ),
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
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _member(RoomDestination item, ColorScheme scheme, bool compactLabels) {
    final pose = slot(item.id);
    final index = widget.destinations.indexWhere((d) => d.id == item.id);
    final active = index >= 0;
    final focus = (1 - (lens.value - pose.center).abs() / pose.width).clamp(
      0.0,
      1.0,
    );
    final label = translate(item.label, Localizations.localeOf(context));
    return Positioned(
      key: ValueKey(item.id),
      left: 7 + (pose.center - pose.width / 2) * innerWidth,
      width: pose.width * innerWidth,
      top: 0,
      bottom: 0,
      child: IgnorePointer(
        ignoring: !active,
        child: ExcludeSemantics(
          excluding: !active,
          child: Opacity(
            opacity: pose.alpha.clamp(0, 1),
            child: Semantics(
              button: true,
              selected: widget.selectedIndex == index,
              label: label,
              excludeSemantics: true,
              onTap: active
                  ? () {
                      cancelled = false;
                      select(index);
                    }
                  : null,
              child: Tooltip(
                message: label,
                child: InkWell(
                  borderRadius: BorderRadius.circular(30),
                  onTap: active ? () => select(index) : null,
                  onTapDown: (_) {
                    if (!reduced) contact.forward();
                  },
                  onTapUp: (_) => contact.reverse(),
                  onTapCancel: () => contact.reverse(),
                  child: SizedBox(
                    key: active ? widget.anchors[item.id] : null,
                    height: 76,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Transform.translate(
                          offset: Offset(0, -2 * focus),
                          child: Transform.scale(
                            scale: 1 + .1 * focus,
                            child: Icon(
                              focus > .5 ? item.activeIcon : item.icon,
                              size: 23,
                              color: Color.lerp(
                                scheme.onSurface.withValues(alpha: .58),
                                scheme.primary,
                                focus,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        if (compactLabels)
                          SizedBox(
                            height:
                                MediaQuery.textScalerOf(context).scale(11) *
                                1.4,
                          )
                        else
                          Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.fade,
                            style: TextStyle(
                              fontSize: 11,
                              color: Color.lerp(
                                scheme.onSurface.withValues(alpha: .60),
                                scheme.primary,
                                focus,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
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
