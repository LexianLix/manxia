import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import '../data/comic.dart';
import 'book_object.dart';
import 'localized_text.dart';
import 'materials.dart';

/// The lens previews a destination while dragging; the page changes on release.
class FrostedNavigation extends StatefulWidget {
  const FrostedNavigation({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    this.highQuality = true,
    this.haptics = true,
  });
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool highQuality, haptics;
  @override
  State<FrostedNavigation> createState() => _FrostedNavigationState();
}

class _FrostedNavigationState extends State<FrostedNavigation>
    with TickerProviderStateMixin {
  late final lens = AnimationController.unbounded(
    vsync: this,
    value: widget.selectedIndex.toDouble(),
  );
  late final contact = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 110),
    reverseDuration: const Duration(milliseconds: 230),
  );
  int? preview;
  bool cancelled = false;
  double slotWidth = 1;
  bool reduced = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    reduced = MediaQuery.disableAnimationsOf(context);
  }

  static const items = [
    (Icons.auto_stories_outlined, Icons.auto_stories, '书架'),
    (Icons.explore_outlined, Icons.explore, '发现'),
    (Icons.history_outlined, Icons.history, '足迹'),
    (Icons.tune_outlined, Icons.tune, '设置'),
  ];

  void settle(double target) {
    final velocity = lens.velocity;
    lens.stop();
    if (reduced) {
      lens.value = target;
      return;
    }
    lens.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 430, damping: 31),
        lens.value,
        target,
        velocity.clamp(-12, 12),
      ),
    );
  }

  void select(int index) {
    preview = null;
    contact.reverse();
    settle(index.toDouble());
    if (widget.selectedIndex != index) {
      if (widget.haptics) HapticFeedback.selectionClick();
      widget.onSelected(index);
    } else {
      setState(() {});
    }
  }

  void scrub(double x) {
    final value = ((x - 6) / slotWidth - .5).clamp(0.0, 3.0);
    lens.stop();
    lens.value = value;
    final index = value.round();
    if (preview != index) {
      setState(() => preview = index);
      if (widget.haptics) HapticFeedback.selectionClick();
    }
  }

  @override
  void didUpdateWidget(FrostedNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex && preview == null) {
      settle(widget.selectedIndex.toDouble());
    }
  }

  @override
  void dispose() {
    lens.dispose();
    contact.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = Theme.of(context).colorScheme.onSurface;
    final accent = Theme.of(context).colorScheme.primary;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: LayoutBuilder(
              builder: (context, box) {
                slotWidth = (box.maxWidth - 14) / 4;
                return Listener(
                  onPointerDown: (_) => cancelled = false,
                  onPointerCancel: (_) {
                    cancelled = true;
                    setState(() => preview = null);
                    contact.reverse();
                    settle(widget.selectedIndex.toDouble());
                  },
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
                    onHorizontalDragCancel: () {
                      setState(() => preview = null);
                      contact.reverse();
                      settle(widget.selectedIndex.toDouble());
                    },
                    child: AnimatedBuilder(
                      animation: Listenable.merge([lens, contact]),
                      builder: (context, _) {
                        final press = reduced
                            ? 0.0
                            : Curves.easeOut.transform(contact.value);
                        return Transform.scale(
                          scale: 1 - .018 * press,
                          child: MilkGlass(
                            radius: 35,
                            high: widget.highQuality,
                            tintOpacity: widget.highQuality
                                ? (dark ? .38 : .19)
                                : (dark ? .93 : .92),
                            blurSigma: 28,
                            shadow: true,
                            child: SizedBox(
                              height: 74,
                              child: Stack(
                                children: [
                                  Positioned(
                                    left:
                                        6 +
                                        lens.value.clamp(-.1, 3.1) * slotWidth,
                                    top: 7 + press,
                                    bottom: 7 + press,
                                    width: slotWidth,
                                    child: Transform.scale(
                                      scaleX:
                                          1 +
                                          (reduced
                                              ? 0
                                              : lens.velocity.abs().clamp(
                                                      0,
                                                      10,
                                                    ) *
                                                    .014),
                                      scaleY: 1 - .035 * press,
                                      child: DecoratedBox(
                                        key: const ValueKey('navigation-lens'),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            28,
                                          ),
                                          gradient: LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: [
                                              Colors.white.withValues(
                                                alpha: dark ? .18 : .75,
                                              ),
                                              accent.withValues(
                                                alpha: dark ? .17 : .10,
                                              ),
                                              Colors.white.withValues(
                                                alpha: dark ? .06 : .30,
                                              ),
                                            ],
                                          ),
                                          border: Border.all(
                                            color: Colors.white.withValues(
                                              alpha: dark ? .24 : .9,
                                            ),
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: accent.withValues(
                                                alpha: .09,
                                              ),
                                              blurRadius: 9,
                                              offset: const Offset(0, 3),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                    ),
                                    child: Row(
                                      children: List.generate(4, (index) {
                                        final active =
                                            (preview ?? widget.selectedIndex) ==
                                            index;
                                        final focus =
                                            (1 - (lens.value - index).abs())
                                                .clamp(0.0, 1.0);
                                        final label = translate(
                                          items[index].$3,
                                          Localizations.localeOf(context),
                                        );
                                        return Expanded(
                                          child: Semantics(
                                            button: true,
                                            selected:
                                                widget.selectedIndex == index,
                                            label: label,
                                            excludeSemantics: true,
                                            onTap: () => select(index),
                                            child: Tooltip(
                                              message: label,
                                              child: Material(
                                                color: Colors.transparent,
                                                child: InkWell(
                                                  borderRadius:
                                                      BorderRadius.circular(30),
                                                  onTap: () => select(index),
                                                  onTapDown: (_) {
                                                    if (!reduced) {
                                                      contact.forward();
                                                    }
                                                  },
                                                  onTapCancel: () =>
                                                      contact.reverse(),
                                                  onTapUp: (_) =>
                                                      contact.reverse(),
                                                  child: SizedBox(
                                                    height: 74,
                                                    child: Column(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .center,
                                                      children: [
                                                        Transform.translate(
                                                          offset: Offset(
                                                            0,
                                                            -2 * focus,
                                                          ),
                                                          child: Transform.scale(
                                                            scale:
                                                                1 + .09 * focus,
                                                            child: Icon(
                                                              active
                                                                  ? items[index]
                                                                        .$2
                                                                  : items[index]
                                                                        .$1,
                                                              size: 23,
                                                              color: Color.lerp(
                                                                ink.withValues(
                                                                  alpha: .60,
                                                                ),
                                                                accent,
                                                                focus,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          height: 4,
                                                        ),
                                                        Text(
                                                          label,
                                                          maxLines: 1,
                                                          overflow:
                                                              TextOverflow.fade,
                                                          style: TextStyle(
                                                            fontSize: 10.5,
                                                            height: 1.2,
                                                            fontWeight: active
                                                                ? FontWeight
                                                                      .w600
                                                                : FontWeight
                                                                      .w400,
                                                            color: active
                                                                ? accent
                                                                : ink.withValues(
                                                                    alpha: .64,
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
                                        );
                                      }),
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
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Cover colours stay behind the scrolling surface, so the dock has real
/// content to sample even in the quiet areas between books.
class ReadingAtmosphere extends StatelessWidget {
  const ReadingAtmosphere({
    super.key,
    required this.comic,
    required this.web,
    this.highQuality = true,
  });
  final Comic? comic;
  final bool web, highQuality;
  @override
  Widget build(BuildContext context) {
    if (comic == null || !highQuality || MediaQuery.highContrastOf(context)) {
      return const SizedBox.expand();
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, box) {
          final width = math.min(box.maxWidth * 1.35, 650.0);
          return ClipRect(
            child: Stack(
              children: [
                Positioned(
                  width: width,
                  height: width * 1.35,
                  bottom: -width * .62,
                  left: -width * .23,
                  child: Opacity(
                    opacity: dark ? .24 : .19,
                    child: ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(sigmaX: 52, sigmaY: 52),
                      child: AnimatedSwitcher(
                        duration: Duration(
                          milliseconds: MediaQuery.disableAnimationsOf(context)
                              ? 0
                              : 600,
                        ),
                        child: SizedBox.expand(
                          key: ValueKey(comic!.cover),
                          child: ComicCover(comic!, web: web),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
