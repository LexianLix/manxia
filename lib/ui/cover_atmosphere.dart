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
  static final _cache = <(String, bool), Uint8List>{};
  Uint8List? _artwork;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  int _request = 0;

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
    final identity = (url, web);
    _stopListening();
    final request = ++_request;
    final cached = _cache.remove(identity);
    _artwork = cached;
    if (cached != null) {
      _cache[identity] = cached;
    } else if (url.isNotEmpty) {
      unawaited(_loadCover(identity, widget.coverWidth, request));
    }
  }

  Future<void> _loadCover(
    (String, bool) identity,
    int width,
    int request,
  ) async {
    final (url, web) = identity;
    try {
      final provider =
          immediateComicImageProvider(url, web) ??
          await comicImageProvider(url, web);
      if (!mounted || request != _request) return;
      final stream = ResizeImage.resizeIfNeeded(
        width,
        null,
        provider,
      ).resolve(ImageConfiguration.empty);
      final listener = ImageStreamListener((info, _) {
        _stopListening();
        unawaited(_blurAndStore(info, identity, request));
      }, onError: (_, _) => _stopListening());
      _stream = stream;
      _listener = listener;
      stream.addListener(listener);
    } catch (_) {
      // An unavailable cover leaves the theme surface visible.
    }
  }

  Future<void> _blurAndStore(
    ImageInfo info,
    (String, bool) identity,
    int request,
  ) async {
    final cover = info.image;
    ui.Picture? picture;
    ui.Image? thumbnail;
    try {
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
      if (data == null || !mounted || request != _request) return;
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      _cache[identity] = bytes;
      if (_cache.length > 24) _cache.remove(_cache.keys.first);
      setState(() => _artwork = bytes);
    } catch (_) {
      // The foreground image remains usable if thumbnail rasterization fails.
    } finally {
      thumbnail?.dispose();
      picture?.dispose();
      info.dispose();
    }
  }

  void _stopListening() {
    final listener = _listener;
    if (listener != null) _stream?.removeListener(listener);
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (MediaQuery.highContrastOf(context)) return const SizedBox.expand();
    final image = _artwork;
    return IgnorePointer(
      child: AnimatedOpacity(
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
                    colors: [Colors.white, Colors.white, Colors.transparent],
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
      ),
    );
  }
}
