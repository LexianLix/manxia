import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

import '../data/comic.dart';
import '../data/library.dart';
import 'comic_image.dart';

/// Copies only the display fields to Android. Reading positions stay in Library.
class AndroidReadingWidget {
  AndroidReadingWidget(this.library, this.latest, this.open);

  static const channel = MethodChannel('io.manxia/reading-widget');
  final Library library;
  final ReadingRecord? Function() latest;
  final void Function(String bookKey) open;

  Timer? _queued;
  ReadingRecord? _lastRecord;
  String? _attemptedCover;
  bool _sent = false;
  bool _started = false;

  static String bookKey(Comic comic) =>
      _digest(jsonEncode([comic.sourceId, comic.path]));

  static String _digest(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  void start() {
    if (_started) return;
    _started = true;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'available') await _consumeTap();
    });
    library.addListener(_queue);
    unawaited(_consumeTap());
    _queue();
  }

  void refresh() {
    if (!_started) return;
    _attemptedCover = null;
    _sent = false;
    _queue();
  }

  Future<void> _consumeTap() async {
    try {
      final key = await channel.invokeMethod<String>('take');
      if (_started && key != null) open(key);
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  void _queue() {
    if (_sent && identical(latest(), _lastRecord)) {
      _queued?.cancel();
      return;
    }
    // Use the latest record at the trailing edge. A frame-by-frame scroll
    // does not send a frame-by-frame launcher update.
    _queued?.cancel();
    _queued = Timer(const Duration(milliseconds: 300), _publish);
  }

  Future<void> _publish() async {
    if (!_started) return;
    final record = latest();
    _lastRecord = record;
    _sent = true;
    final book = record == null ? null : bookKey(record.comic);
    final url = record?.comic.cover ?? '';
    final cover = url.isEmpty ? null : _digest(jsonEncode([book, url]));
    try {
      final needsCover = await channel.invokeMethod<bool>(
        'publish',
        record == null
            ? null
            : {
                'book': book,
                'title': record.comic.title,
                'chapter': record.chapterTitle,
                'page': record.page + 1,
                'total': record.total,
                'cover': cover,
              },
      );
      if (!_started ||
          needsCover != true ||
          cover == null ||
          cover == _attemptedCover) {
        return;
      }
      _attemptedCover = cover;
      final bytes = await _thumbnail(url);
      if (_started && bytes != null) {
        await channel.invokeMethod<void>('setCover', {
          'cover': cover,
          'bytes': bytes,
        });
      }
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  Future<Uint8List?> _thumbnail(String url) async {
    final budget = const Duration(seconds: 4);
    try {
      final provider = await comicImageProvider(url, false).timeout(budget);
      final stream = ResizeImage(
        provider,
        width: 96,
        height: 136,
        policy: ResizeImagePolicy.fit,
      ).resolve(ImageConfiguration.empty);
      final ready = Completer<ImageInfo>();
      final listener = ImageStreamListener(
        (image, _) {
          if (ready.isCompleted) {
            image.dispose();
          } else {
            ready.complete(image);
          }
        },
        onError: (error, stack) {
          if (!ready.isCompleted) ready.completeError(error, stack);
        },
      );
      stream.addListener(listener);
      try {
        final cover = await ready.future.timeout(budget);
        try {
          final bytes = await cover.image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          return bytes?.buffer.asUint8List(
            bytes.offsetInBytes,
            bytes.lengthInBytes,
          );
        } finally {
          cover.dispose();
        }
      } finally {
        stream.removeListener(listener);
      }
    } catch (_) {
      // Title and resume still work when an upstream cover is unavailable.
      return null;
    }
  }

  void dispose() {
    if (!_started) return;
    _started = false;
    _queued?.cancel();
    library.removeListener(_queue);
    channel.setMethodCallHandler(null);
  }
}
