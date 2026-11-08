import 'dart:math' as math;
import 'comic.dart';

String readingDay(DateTime at) =>
    '${at.year.toString().padLeft(4, '0')}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}';

/// Per-device grow-only day counters merge without counting the same backup twice.
class ReadingJournal {
  String device = List.generate(
    16,
    (_) => math.Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  int resetAt = 0;
  final Map<String, Map<String, dynamic>> activity = {};
  final List<ReadingRecord> positions = [];

  bool add(
    ReadingRecord record,
    int milliseconds,
    DateTime at, {
    bool seen = false,
    int visiblePages = 1,
  }) {
    if (milliseconds <= 0 || record.total <= 0) return false;
    final day = readingDay(at), key = '$day|$device|${record.comic.path}';
    final old = activity[key] ?? {};
    final pages = Map<String, dynamic>.from(old['pages'] as Map? ?? {});
    if (seen) {
      final visited = Set<int>.from(pages[record.chapterPath] as List? ?? []);
      for (
        var i = 0;
        i < visiblePages.clamp(1, 2) && record.page + i < record.total;
        i++
      ) {
        visited.add(record.page + i);
      }
      pages[record.chapterPath] = visited.toList()..sort();
    }
    activity[key] = {
      'day': day,
      'comic': {
        ...record.comic.toJson(),
        'description': '',
        'tags': <String>[],
      },
      'epoch': resetAt,
      'milliseconds': ((old['milliseconds'] as int? ?? 0) + milliseconds).clamp(
        0,
        86400000,
      ),
      'pages': pages,
    };
    return true;
  }

  bool remember(ReadingRecord record, {bool force = false}) {
    if (record.total <= 0 ||
        record.page < 0 ||
        record.page >= record.total ||
        !record.position.isFinite) {
      return false;
    }
    final last = forComic(record.comic).firstOrNull;
    final same = positions
        .where(
          (r) =>
              r.comic.path == record.comic.path &&
              r.chapterPath == record.chapterPath &&
              r.page == record.page &&
              (r.position - record.position).abs() < .02,
        )
        .firstOrNull;
    if (same != null && same.updatedAt > record.updatedAt) return false;
    if (last != null &&
        !force &&
        last.chapterPath == record.chapterPath &&
        (last.page - record.page).abs() < 6 &&
        record.updatedAt - last.updatedAt < 120000) {
      return false;
    }
    positions.removeWhere(
      (r) =>
          r.comic.path == record.comic.path &&
          r.chapterPath == record.chapterPath &&
          r.page == record.page &&
          (r.position - record.position).abs() < .02,
    );
    positions.insert(0, record);
    final own = forComic(record.comic).skip(20).toSet();
    positions.removeWhere(own.contains);
    return true;
  }

  List<ReadingRecord> forComic(Comic comic) =>
      positions.where((r) => r.comic.path == comic.path).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  void removePositions(String path) =>
      positions.removeWhere((r) => r.comic.path == path);
  void clearStatistics(int at) {
    resetAt = math.max(resetAt + 1, at);
    activity.clear();
  }

  Map<String, dynamic> toJson() => {
    'resetAt': resetAt,
    'activity': activity,
    'positions': positions
        .map(
          (r) => {
            ...r.toJson(),
            'comic': {
              ...r.comic.toJson(),
              'description': '',
              'tags': <String>[],
            },
          },
        )
        .toList(),
  };

  void merge(dynamic raw, Map<String, int> tombstones) {
    if (raw is! Map) return;
    final incomingReset = raw['resetAt'];
    if (incomingReset is int && incomingReset > resetAt) {
      resetAt = incomingReset;
      activity.clear();
    }
    for (final entry
        in (raw['activity'] is Map ? raw['activity'] as Map : {}).entries) {
      try {
        if (entry.key is! String || entry.value is! Map) continue;
        final value = Map<String, dynamic>.from(entry.value);
        if ((value['epoch'] ?? 0) != resetAt ||
            value['day'] is! String ||
            !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value['day'])) {
          continue;
        }
        final comic = Comic.fromJson(Map<String, dynamic>.from(value['comic']));
        if (comic.path.isEmpty || value['milliseconds'] is! int) continue;
        final old = activity[entry.key] ?? {};
        final pages = Map<String, dynamic>.from(old['pages'] as Map? ?? {});
        for (final e
            in (value['pages'] is Map ? value['pages'] as Map : {}).entries) {
          if (e.key is! String || e.value is! List) continue;
          pages[e.key] = {
            ...List<int>.from(pages[e.key] as List? ?? []),
            ...((e.value as List).whereType<int>().where(
              (p) => p >= 0 && p < 100000,
            )),
          }.toList()..sort();
        }
        activity[entry.key] = {
          ...value,
          'pages': pages,
          'milliseconds': math.max(
            old['milliseconds'] as int? ?? 0,
            (value['milliseconds'] as int).clamp(0, 86400000),
          ),
        };
      } catch (_) {
        /* A malformed optional journal row cannot erase the library. */
      }
    }
    for (final rawPoint
        in raw['positions'] is List ? raw['positions'] as List : []) {
      try {
        final point = ReadingRecord.fromJson(
          Map<String, dynamic>.from(rawPoint),
        );
        final deleted = math.max(
          tombstones['history:${point.comic.path}'] ?? -1,
          tombstones['positions:all'] ?? -1,
        );
        if (point.updatedAt > deleted) remember(point, force: true);
      } catch (_) {
        /* Skip invalid optional positions. */
      }
    }
    positions.removeWhere(
      (r) =>
          r.updatedAt <=
          math.max(
            tombstones['history:${r.comic.path}'] ?? -1,
            tombstones['positions:all'] ?? -1,
          ),
    );
    positions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }
}

class ReadingTotals {
  ReadingTotals(ReadingJournal journal, {DateTime? since}) {
    final first = since == null ? null : readingDay(since);
    final unique = <String>{};
    for (final row in journal.activity.values) {
      final day = row['day'] as String;
      if (first != null && day.compareTo(first) < 0) continue;
      final comic = Comic.fromJson(Map<String, dynamic>.from(row['comic']));
      final time = row['milliseconds'] as int;
      milliseconds += time;
      byDay[day] = (byDay[day] ?? 0) + time;
      byBook[comic.path] = (byBook[comic.path] ?? 0) + time;
      books[comic.path] = comic;
      for (final e in (row['pages'] as Map).entries) {
        for (final p in e.value as List) {
          unique.add('${comic.path}|${e.key}|$p');
        }
      }
    }
    pages = unique.length;
  }
  int milliseconds = 0, pages = 0;
  final Map<String, int> byDay = {}, byBook = {};
  final Map<String, Comic> books = {};
}

/// A monotonic clock excludes hidden routes, unloaded pages and idle time.
class ReadingClock {
  ReadingClock({
    required this.elapsed,
    required this.now,
    required this.onSlice,
  });
  final int Function() elapsed;
  final DateTime Function() now;
  final void Function(
    ReadingRecord record,
    int milliseconds,
    DateTime at,
    bool seen,
  )
  onSlice;
  int? _last, _touch;
  bool _active = false;
  ReadingRecord? _record;
  int _dwell = 0;
  void update(
    ReadingRecord? record, {
    required bool active,
    bool interaction = false,
  }) {
    final time = elapsed();
    if (_last != null && _record != null && _active) {
      final until = math.min(time, (_touch ?? time) + 90000);
      final duration = math.max(0, until - _last!);
      if (duration > 0) {
        _dwell += duration;
        var end = now().subtract(Duration(milliseconds: time - until));
        var remaining = duration;
        while (remaining > 0) {
          final startOfDay = DateTime(end.year, end.month, end.day);
          final part = math.min(
            remaining,
            end.difference(startOfDay).inMilliseconds,
          );
          if (part == 0) {
            end = end.subtract(const Duration(milliseconds: 1));
            continue;
          }
          onSlice(
            _record!,
            part,
            end.subtract(const Duration(milliseconds: 1)),
            _dwell >= 2000,
          );
          remaining -= part;
          end = startOfDay;
        }
      }
    }
    if (!_active && active || interaction || _touch == null) _touch = time;
    if (record?.chapterPath != _record?.chapterPath ||
        record?.page != _record?.page ||
        record?.comic.path != _record?.comic.path) {
      _dwell = 0;
    }
    _last = time;
    _active = active;
    _record = record;
  }
}
