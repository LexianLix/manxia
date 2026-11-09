import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'glass_navigation.dart';
import 'destination_icon.dart';
import 'localized_text.dart';
import 'materials.dart';
import 'room_motion.dart';

/// Scroll distance, rather than direction changes, controls the compact dock.
class BrowseChrome extends ValueNotifier<bool> {
  BrowseChrome() : super(false);
  double distance = 0;
  bool dragging = false;

  void expand() {
    distance = 0;
    dragging = false;
    value = false;
  }

  bool observe(ScrollNotification notice) {
    if (notice.depth != 0 || notice.metrics.axis != Axis.vertical) return false;
    if (notice is ScrollStartNotification && notice.dragDetails != null) {
      dragging = true;
      distance = 0;
    }
    if (notice is UserScrollNotification &&
        notice.direction != ScrollDirection.idle) {
      dragging = true;
    }
    if (notice.metrics.extentBefore <= 3) {
      distance = 0;
      value = false;
    } else if (notice is ScrollUpdateNotification && dragging) {
      distance += (notice.scrollDelta ?? 0).abs();
      if (distance >= 40) value = true;
    }
    if (notice is ScrollEndNotification) dragging = false;
    return false;
  }
}

/// A single glass surface morphs between the dock and its left-hand handle.
class BrowseNavigation extends StatelessWidget {
  const BrowseNavigation({
    super.key,
    required this.chrome,
    required this.selectedIndex,
    required this.destinations,
    required this.onSelected,
    this.anchors = const {},
    this.highQuality = true,
    this.haptics = true,
    this.liquid = true,
  });
  final BrowseChrome chrome;
  final int selectedIndex;
  final List<RoomDestination> destinations;
  final ValueChanged<int> onSelected;
  final Map<int, GlobalKey> anchors;
  final bool highQuality, haptics, liquid;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: chrome,
    builder: (context, compact, _) => TweenAnimationBuilder<double>(
      tween: Tween(end: compact ? 1 : 0),
      duration: RoomMotion.duration(context, RoomMotion.scene),
      curve: RoomMotion.ease,
      child: FrostedNavigation(
        embedded: true,
        anchors: compact ? const {} : anchors,
        selectedIndex: selectedIndex,
        destinations: destinations,
        highQuality: highQuality,
        haptics: haptics,
        liquid: liquid,
        onSelected: (index) {
          chrome.expand();
          onSelected(index);
        },
      ),
      builder: (context, t, navigation) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: LayoutBuilder(
            builder: (context, box) {
              final width = math.min(
                box.maxWidth,
                destinations.length * 60 + 14.0,
              );
              final height = math.max(
                52.0,
                36 + MediaQuery.textScalerOf(context).scale(11) * 1.35,
              );
              final current = destinations[selectedIndex];
              final dark = Theme.of(context).brightness == Brightness.dark;
              final x = (box.maxWidth - width) / 2 * (1 - t);
              final iconX =
                  7 + (selectedIndex + .5) / destinations.length * (width - 14);
              return Align(
                alignment: Alignment.centerLeft,
                heightFactor: 1,
                child: Transform.translate(
                  offset: Offset(x, 0),
                  child: SizedBox(
                    key: const ValueKey('browse-dock'),
                    width: width + (52 - width) * t,
                    height: height,
                    child: MilkGlass(
                      radius: 28,
                      role: GlassRole.chrome,
                      high: highQuality,
                      tintOpacity: dark ? .28 : .20,
                      blurSigma: 18,
                      shadow: true,
                      child: ClipRect(
                        child: Stack(
                          children: [
                            Positioned(
                              left: (26 - iconX) * t,
                              top: 0,
                              width: width,
                              height: height,
                              child: IgnorePointer(
                                ignoring: compact,
                                child: ExcludeSemantics(
                                  excluding: compact,
                                  child: Opacity(
                                    opacity: (1 - t * 1.7).clamp(0, 1),
                                    child: navigation,
                                  ),
                                ),
                              ),
                            ),
                            Positioned.fill(
                              child: IgnorePointer(
                                ignoring: !compact,
                                child: ExcludeSemantics(
                                  excluding: !compact,
                                  child: Opacity(
                                    opacity: ((t - .35) / .65).clamp(0, 1),
                                    child: Center(
                                      child: IconButton(
                                        key: compact ? anchors[0] : null,
                                        tooltip:
                                            '${translate('展开导航', Localizations.localeOf(context))} · ${translate(current.label, Localizations.localeOf(context))}',
                                        onPressed: chrome.expand,
                                        icon: DestinationMotionIcon(
                                          destination: current,
                                          selected: true,
                                          reduced:
                                              MediaQuery.disableAnimationsOf(
                                                context,
                                              ),
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                        ),
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

/// Small edge veils soften scroll boundaries without an offscreen texture the
/// size of the whole page. They never intercept scrolling or navigation.
class BrowseEdges extends StatefulWidget {
  const BrowseEdges({super.key, required this.child});
  final Widget child;
  @override
  State<BrowseEdges> createState() => _BrowseEdgesState();
}

class _BrowseEdgesState extends State<BrowseEdges> {
  bool top = false, bottom = false;
  bool update(ScrollMetrics metrics) {
    if (metrics.axis != Axis.vertical) return false;
    final up = metrics.extentBefore > 1, down = metrics.extentAfter > 1;
    if (top != up || bottom != down) {
      setState(() {
        top = up;
        bottom = down;
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollMetricsNotification>(
        onNotification: (n) => n.depth == 0 ? update(n.metrics) : false,
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) => n.depth == 0 ? update(n.metrics) : false,
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              RepaintBoundary(child: widget.child),
              for (final upper in [true, false])
                Positioned(
                  left: 0,
                  right: 0,
                  top: upper ? 0 : null,
                  bottom: upper ? null : 0,
                  height: 24,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: (upper ? top : bottom) ? 1 : 0,
                      duration: RoomMotion.duration(context, RoomMotion.press),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: upper
                                ? Alignment.topCenter
                                : Alignment.bottomCenter,
                            end: upper
                                ? Alignment.bottomCenter
                                : Alignment.topCenter,
                            colors: [
                              Theme.of(
                                context,
                              ).colorScheme.surface.withValues(alpha: .92),
                              Theme.of(
                                context,
                              ).colorScheme.surface.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
}
