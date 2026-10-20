import 'dart:ui' as ui;

/// A tiny readback, once per cover, rather than repeatedly reading the full
/// decoded GPU texture when focus moves. No image handles remain in the cache.
class CoverPalette {
  static final _colors = <String, Future<ui.Color?>>{};
  static Future<ui.Color?> average(String key, ui.Image image) {
    final cached = _colors.remove(key);
    if (cached != null) {
      _colors[key] = cached;
      return cached;
    }
    final retained = image.clone();
    final work = Future<ui.Color?>(() async {
      ui.Image? small;
      ui.Picture? picture;
      try {
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder).drawImageRect(
          retained,
          ui.Rect.fromLTWH(
            0,
            0,
            retained.width.toDouble(),
            retained.height.toDouble(),
          ),
          const ui.Rect.fromLTWH(0, 0, 32, 32),
          ui.Paint(),
        );
        picture = recorder.endRecording();
        small = await picture.toImage(32, 32);
        final data = await small.toByteData();
        if (data == null) return null;
        final pixels = data.buffer.asUint8List();
        var red = 0, green = 0, blue = 0, count = 0;
        for (var i = 0; i < pixels.length; i += 4) {
          final brightness = pixels[i] + pixels[i + 1] + pixels[i + 2];
          if (brightness > 90 && brightness < 680) {
            red += pixels[i];
            green += pixels[i + 1];
            blue += pixels[i + 2];
            count++;
          }
        }
        return count == 0
            ? null
            : ui.Color.fromARGB(
                255,
                red ~/ count,
                green ~/ count,
                blue ~/ count,
              );
      } catch (_) {
        return null;
      } finally {
        small?.dispose();
        picture?.dispose();
        retained.dispose();
      }
    });
    _colors[key] = work;
    while (_colors.length > 48) {
      _colors.remove(_colors.keys.first);
    }
    return work;
  }
}
