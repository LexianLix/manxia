import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../data/appearance.dart';
import '../data/library.dart';

/// Behind the Navigator, so the same image survives route changes. A missing
/// local image (e.g. after importing a JSON backup) falls back to the theme.
class RoomBackdrop extends StatefulWidget {
  const RoomBackdrop({
    super.key,
    required this.library,
    required this.child,
    this.store,
  });
  final Library library;
  final Widget child;
  final WallpaperStore? store;
  @override
  State<RoomBackdrop> createState() => _RoomBackdropState();
}

class _RoomBackdropState extends State<RoomBackdrop> {
  String? key;
  Future<Uint8List?>? bytes;
  @override
  Widget build(BuildContext context) {
    final appearance = RoomAppearance(widget.library.options);
    if (key != appearance.wallpaper) {
      key = appearance.wallpaper;
      bytes = key == null
          ? null
          : (widget.store ?? WallpaperStore.shared).read(key!);
    }
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: ColoredBox(
                color: scheme.surface,
                child: FutureBuilder<Uint8List?>(
                  future: bytes,
                  builder: (_, snapshot) {
                    final data = key == null ? null : snapshot.data;
                    if (data == null) return const SizedBox.expand();
                    Widget image = Image.memory(
                      data,
                      key: ValueKey(key),
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      excludeFromSemantics: true,
                      errorBuilder: (_, _, _) => const SizedBox.expand(),
                    );
                    if (appearance.blur > 0) {
                      image = ImageFiltered(
                        imageFilter: ui.ImageFilter.blur(
                          sigmaX: appearance.blur,
                          sigmaY: appearance.blur,
                        ),
                        child: image,
                      );
                    }
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        image,
                        ColoredBox(
                          color: scheme.surface.withValues(
                            alpha: MediaQuery.highContrastOf(context)
                                ? .94
                                : (appearance.veil + (dark ? .08 : 0)).clamp(
                                    0,
                                    .96,
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
        widget.child,
      ],
    );
  }
}
