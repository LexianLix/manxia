import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'comic_image.dart';
import 'room_motion.dart';

/// Renders a small blurred copy once so a route transition only paints a
/// texture. The foreground cover keeps its normal decode and image cache.
class CoverAtmosphere extends StatefulWidget {
  const CoverAtmosphere({
    super.key,
    required this.url,
    required this.web,
    required this.coverWidth,
    required this.motion,
  });

  final String url;
  final bool web, motion;
  final int coverWidth;

  @override
  State<CoverAtmosphere> createState() => _CoverAtmosphereState();
}

class _CoverAtmosphereState extends State<CoverAtmosphere> {
  static final _cache = <(String, bool), Future<Uint8List?>>{};
  Future<Uint8List?>? _artwork;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(CoverAtmosphere oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.web != widget.web) _prepare();
  }

  void _prepare() {
    final url = widget.url;
    final web = widget.web;
    final width = widget.coverWidth;
    final identity = (url, web);
    _artwork = null;
    if (url.isEmpty) return;
    final cached = _cache.remove(identity);
    final artwork = cached ?? _blurCover(url, web, width);
    _cache[identity] = artwork;
    _artwork = artwork;
    if (cached == null) {
      unawaited(
        artwork.then((bytes) {
          if (bytes == null && identical(_cache[identity], artwork)) {
            _cache.remove(identity);
          }
        }),
      );
    }
    if (_cache.length > 24) _cache.remove(_cache.keys.first);
  }

  static Future<Uint8List?> _blurCover(String url, bool web, int width) async {
    ui.Image? cover;
    ui.Picture? picture;
    ui.Image? thumbnail;
    try {
      final provider =
          immediateComicImageProvider(url, web) ??
          await comicImageProvider(url, web);
      final stream = ResizeImage.resizeIfNeeded(
        width,
        null,
        provider,
      ).resolve(ImageConfiguration.empty);
      final decoded = Completer<ui.Image?>();
      final listener = ImageStreamListener(
        (info, _) {
          if (!decoded.isCompleted) decoded.complete(info.image.clone());
          info.dispose();
        },
        onError: (_, _) {
          if (!decoded.isCompleted) decoded.complete(null);
        },
      );
      stream.addListener(listener);
      try {
        cover = await decoded.future.timeout(
          const Duration(seconds: 8),
          onTimeout: () => null,
        );
      } finally {
        stream.removeListener(listener);
      }
      if (cover == null) return null;
      const bounds = Rect.fromLTWH(0, 0, 80, 72);
      final source = Size(cover.width.toDouble(), cover.height.toDouble());
      final fitted = applyBoxFit(BoxFit.cover, source, bounds.size);
      final sample = Alignment.topCenter.inscribe(
        fitted.source,
        Offset.zero & source,
      );
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawImageRect(
        cover,
        sample,
        bounds,
        ui.Paint()
          ..filterQuality = FilterQuality.medium
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: 5,
            sigmaY: 5,
            tileMode: ui.TileMode.clamp,
          ),
      );
      picture = recorder.endRecording();
      thumbnail = await picture.toImage(80, 72);
      final data = await thumbnail.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (_) {
      return null;
    } finally {
      thumbnail?.dispose();
      picture?.dispose();
      cover?.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (MediaQuery.highContrastOf(context)) return const SizedBox.expand();
    return IgnorePointer(
      child: FutureBuilder<Uint8List?>(
        key: ValueKey((widget.url, widget.web)),
        future: _artwork,
        builder: (context, snapshot) {
          final image = snapshot.data;
          return AnimatedOpacity(
            opacity: image == null ? 0 : (dark ? .24 : .28),
            duration: widget.motion
                ? RoomMotion.duration(context, RoomMotion.feedback)
                : Duration.zero,
            curve: RoomMotion.ease,
            child: image == null
                ? const SizedBox.expand()
                : RepaintBoundary(
                    child: ShaderMask(
                      shaderCallback: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white,
                          Colors.white,
                          Colors.transparent,
                        ],
                        stops: [0, .24, 1],
                      ).createShader,
                      blendMode: BlendMode.dstIn,
                      child: Image.memory(
                        image,
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        excludeFromSemantics: true,
                        filterQuality: FilterQuality.low,
                      ),
                    ),
                  ),
          );
        },
      ),
    );
  }
}
