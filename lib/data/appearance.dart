import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import '../platform/blob_store.dart';
import '../platform/storage.dart';

/// Small, portable preferences; image bytes stay in local blob storage.
class RoomAppearance {
  RoomAppearance(Map<String, dynamic> options)
    : values = Map<String, dynamic>.from(
        options['appearance'] is Map
            ? options['appearance'] as Map
            : const <String, dynamic>{},
      );
  final Map<String, dynamic> values;
  static const defaultSeed = Color(0xff397fa9);
  String? get wallpaper =>
      values['wallpaper'] is String &&
          RegExp(r'^[a-f0-9]{64}$').hasMatch(values['wallpaper'])
      ? values['wallpaper'] as String
      : null;
  String get name => values['name'] is String ? values['name'] as String : '';
  bool get follow => values['follow'] != false;
  double get veil => _number('veil', .58).clamp(.20, .90);
  double get blur => _number('blur', 0).clamp(0, 12);
  double _number(String key, double fallback) {
    final value = values[key];
    return value is num && value.isFinite ? value.toDouble() : fallback;
  }

  Color get seed => follow && wallpaper != null && values['seed'] is int
      ? Color(values['seed'] as int).withValues(alpha: 1)
      : defaultSeed;

  static Color surface(Color seed, bool dark) {
    final hue = HSLColor.fromColor(seed).hue;
    return HSLColor.fromAHSL(
      1,
      hue,
      dark ? .18 : .20,
      dark ? .085 : .976,
    ).toColor();
  }
}

class PreparedWallpaper {
  const PreparedWallpaper(this.key, this.bytes, this.seed);
  final String key;
  final Uint8List bytes;
  final Color seed;
}

class WallpaperStore {
  WallpaperStore({BlobStore? store}) : _provided = store;
  final BlobStore? _provided;
  static final shared = WallpaperStore();
  Future<BlobStore>? _pending;
  Future<BlobStore> get _store => _pending ??= _provided != null
      ? Future.value(_provided)
      : createWallpaperStore();
  String? _cachedKey;
  Uint8List? _cachedBytes;

  Future<Uint8List?> read(String key) async {
    if (_cachedKey == key && _cachedBytes != null) return _cachedBytes;
    final bytes = await (await _store).read(key);
    if (bytes != null) {
      _cachedKey = key;
      _cachedBytes = bytes;
    }
    return bytes;
  }

  Future<void> remove(String key) async {
    await (await _store).delete(key);
    if (_cachedKey == key) {
      _cachedKey = null;
      _cachedBytes = null;
    }
  }

  /// Validate before replacing preferences. Decode once at a bounded size and
  /// save a still frame, so animated/very large wallpapers never tick in UI.
  Future<PreparedWallpaper> save(Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > 20 * 1024 * 1024) {
      throw const FormatException('请选择 20 MB 以内的背景图片。');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image, sample;
    ui.Picture? picture;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width * descriptor.height > 80000000) {
        throw const FormatException('图片尺寸过大，请先缩小图片。');
      }
      final ratio = math.min(
        1.0,
        1920 / math.max(descriptor.width, descriptor.height),
      );
      codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (descriptor.width * ratio).round()),
        targetHeight: math.max(1, (descriptor.height * ratio).round()),
      );
      image = (await codec.getNextFrame()).image;
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        const Rect.fromLTWH(0, 0, 32, 32),
        Paint(),
      );
      picture = recorder.endRecording();
      sample = await picture.toImage(32, 32);
      final pixels = await sample.toByteData();
      final seed = pixels == null
          ? RoomAppearance.defaultSeed
          : wallpaperSeed(pixels.buffer.asUint8List());
      final encoded = await image.toByteData(format: ui.ImageByteFormat.png);
      if (encoded == null) throw const FormatException('无法读取这张图片。');
      final normalized = encoded.buffer.asUint8List();
      final key = sha256.convert(normalized).toString();
      await (await _store).write(key, normalized);
      _cachedKey = key;
      _cachedBytes = normalized;
      return PreparedWallpaper(key, normalized, seed);
    } finally {
      sample?.dispose();
      picture?.dispose();
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  }
}

/// Pick the dominant chromatic family instead of averaging opposite colors
/// into brown. Near-white/black pixels don't overwhelm a small accent region.
Color wallpaperSeed(Uint8List rgba) {
  final weights = List<double>.filled(12, 0);
  final red = List<double>.filled(12, 0),
      green = List<double>.filled(12, 0),
      blue = List<double>.filled(12, 0);
  for (var i = 0; i + 3 < rgba.length; i += 4) {
    if (rgba[i + 3] < 128) continue;
    final color = Color.fromARGB(255, rgba[i], rgba[i + 1], rgba[i + 2]);
    final hsl = HSLColor.fromColor(color);
    if (hsl.lightness < .08 || hsl.lightness > .94 || hsl.saturation < .12) {
      continue;
    }
    final bin = (hsl.hue / 30).floor().clamp(0, 11);
    final weight = hsl.saturation * (1 - (hsl.lightness - .5).abs());
    weights[bin] += weight;
    red[bin] += rgba[i] * weight;
    green[bin] += rgba[i + 1] * weight;
    blue[bin] += rgba[i + 2] * weight;
  }
  final best = weights.indexOf(weights.reduce(math.max));
  if (weights[best] == 0) return RoomAppearance.defaultSeed;
  final dominant = Color.fromARGB(
    255,
    (red[best] / weights[best]).round(),
    (green[best] / weights[best]).round(),
    (blue[best] / weights[best]).round(),
  );
  return HSLColor.fromColor(dominant)
      .withSaturation(HSLColor.fromColor(dominant).saturation.clamp(.28, .62))
      .withLightness(.43)
      .toColor();
}
