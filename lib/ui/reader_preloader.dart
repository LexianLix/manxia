import 'dart:async';

/// Keep speculative decoding behind the page the reader actually requested.
/// Replacing the window drops queued work; an in-flight codec can finish once.
class ReaderPreloader {
  ReaderPreloader(this.load);
  final Future<bool> Function(String url, int width) load;
  final _queue = <(String, int)>[];
  final _completed = <(String, int)>{};
  (String, int)? _active;
  bool _busy = false, _disposed = false;

  void replace(Iterable<String> urls, int width) {
    if (_disposed) return;
    _queue.clear();
    for (final key in urls.map((url) => (url, width)).toSet()) {
      if (key != _active && !_completed.contains(key)) _queue.add(key);
    }
    if (!_busy) unawaited(_drain());
  }

  void clear() => _queue.clear();

  Future<void> _drain() async {
    _busy = true;
    try {
      while (!_disposed && _queue.isNotEmpty) {
        final key = _queue.removeAt(0);
        _active = key;
        var success = false;
        try {
          success = await load(key.$1, key.$2);
        } catch (_) {
          // Speculation must not prevent foreground reading or future retries.
        }
        if (!_disposed && success) {
          _completed.remove(key);
          _completed.add(key);
          while (_completed.length > 12) {
            _completed.remove(_completed.first);
          }
        }
        _active = null;
      }
    } finally {
      _busy = false;
    }
  }

  void dispose() {
    _disposed = true;
    clear();
    _completed.clear();
  }
}
