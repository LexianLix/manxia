import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'comic.dart';
import 'source_profile.dart';
import 'plugin.dart';

mixin LibraryFeatures on ChangeNotifier {
  SharedPreferences get prefs;
  List<Comic> get favorites;
  List<ReadingRecord> get history;
  final Map<String, Map<String, dynamic>> metadata = {};
  final Map<String, dynamic> options = {};
  final List<String> searchHistory = [];
  final List<Map<String, dynamic>> bookmarks = [], sourceProfiles = [];
  final Map<String, Map<String, dynamic>> updates = {};
  final Map<String, int> tombstones = {}, favoriteTimes = {};
  T option<T>(String key, T fallback) =>
      options[key] is T ? options[key] as T : fallback;
  Map<String, dynamic> meta(Comic comic) => metadata[comic.path] ?? {};
  List<String> get groups => {
    '全部',
    ...metadata.values.map((m) => m['group'] as String? ?? '未分组'),
  }.toList();
  Map<String, dynamic> readerOptions(Comic comic) => {
    'mode': prefs.getString('readerMode') ?? 'page',
    'rtl': prefs.getBool('rtl') ?? false,
    'brightness': 1.0,
    'warmth': 0.0,
    'crop': 0.0,
    'doublePage': true,
    'turn': 'paper',
    'background': 'theme',
    'autoScroll': 0.0,
    'tapZones': true,
    ...option<Map<String, dynamic>>('readerDefaults', {}),
    ...PluginSnapshot(options).reader,
    ...Map<String, dynamic>.from(meta(comic)['reader'] as Map? ?? {}),
  };
  void loadFeatures() {
    try {
      final j = jsonDecode(prefs.getString('features.v2') ?? '{}') as Map;
      for (final e in (j['metadata'] as Map? ?? {}).entries) {
        metadata[e.key] = Map<String, dynamic>.from(e.value);
      }
      options.addAll(Map<String, dynamic>.from(j['options'] ?? {}));
      tombstones.addAll(Map<String, int>.from(j['tombstones'] ?? {}));
      favoriteTimes.addAll(Map<String, int>.from(j['favoriteTimes'] ?? {}));
      searchHistory.addAll(List<String>.from(j['searchHistory'] ?? []));
      bookmarks.addAll(
        (j['bookmarks'] as List? ?? []).map(
          (e) => Map<String, dynamic>.from(e),
        ),
      );
      for (final item in j['sources'] as List? ?? []) {
        try {
          sourceProfiles.add(
            SourceProfile(Map<String, dynamic>.from(item)).json,
          );
        } catch (_) {}
      }
      for (final e in (j['updates'] as Map? ?? {}).entries) {
        updates[e.key] = Map<String, dynamic>.from(e.value);
      }
    } catch (_) {}
  }

  Future<void> persistFeatures() async {
    notifyListeners();
    await prefs.setString(
      'features.v2',
      jsonEncode({
        'metadata': metadata,
        'options': options,
        'searchHistory': searchHistory,
        'bookmarks': bookmarks,
        'sources': sourceProfiles,
        'updates': updates,
        'tombstones': tombstones,
        'favoriteTimes': favoriteTimes,
      }),
    );
  }

  Future<void> setOption(String key, dynamic value) async {
    options[key] = value;
    await persistFeatures();
  }

  Future<void> setMeta(Comic comic, Map<String, dynamic> change) async {
    metadata[comic.path] = {
      ...meta(comic),
      ...change,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };
    await persistFeatures();
  }

  Future<void> setReaderOption(Comic comic, String key, dynamic value) =>
      setMeta(comic, {
        'reader': {...readerOptions(comic), key: value},
      });
  Future<void> clearSearchHistory() async {
    searchHistory.clear();
    await persistFeatures();
  }

  Future<void> rememberSearch(String query) async {
    if (query.trim().isEmpty) return;
    searchHistory.remove(query);
    searchHistory.insert(0, query);
    if (searchHistory.length > 20) {
      searchHistory.removeRange(20, searchHistory.length);
    }
    await persistFeatures();
  }

  Future<void> addBookmark(
    ReadingRecord r, {
    String note = '',
    bool favorite = false,
  }) async {
    for (final b in bookmarks.where(
      (b) =>
          b['comicPath'] == r.comic.path &&
          b['chapterPath'] == r.chapterPath &&
          b['page'] == r.page,
    )) {
      tombstones['bookmark:${b['id']}'] = DateTime.now().millisecondsSinceEpoch;
    }
    bookmarks.removeWhere(
      (b) =>
          b['comicPath'] == r.comic.path &&
          b['chapterPath'] == r.chapterPath &&
          b['page'] == r.page,
    );
    bookmarks.insert(0, {
      'id': '${DateTime.now().microsecondsSinceEpoch}',
      'comicPath': r.comic.path,
      'comic': r.comic.toJson(),
      'chapterPath': r.chapterPath,
      'chapterTitle': r.chapterTitle,
      'page': r.page,
      'position': r.position,
      'note': note,
      'favorite': favorite,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
    await persistFeatures();
  }

  Future<void> removeBookmark(String id) async {
    tombstones['bookmark:$id'] = DateTime.now().millisecondsSinceEpoch;
    bookmarks.removeWhere((b) => b['id'] == id);
    await persistFeatures();
  }

  Future<void> removeHistory(Comic comic) async {
    tombstones['history:${comic.path}'] = DateTime.now().millisecondsSinceEpoch;
    history.removeWhere((r) => r.comic.path == comic.path);
    notifyListeners();
    await prefs.setString(
      'history',
      jsonEncode(history.map((r) => r.toJson()).toList()),
    );
    await persistFeatures();
  }

  Future<void> reorder(List<Comic> ordered) async {
    final retained = ordered.map((c) => c.path).toSet();
    for (final c in favorites.where((c) => !retained.contains(c.path))) {
      tombstones['book:${c.path}'] = DateTime.now().millisecondsSinceEpoch;
    }
    favorites
      ..clear()
      ..addAll(ordered);
    notifyListeners();
    await prefs.setString(
      'favorites',
      jsonEncode(favorites.map((b) => b.toJson()).toList()),
    );
    await persistFeatures();
  }

  Map<String, dynamic> backup() => {
    'format': 'manxia',
    'schema': 2,
    'exportedAt': DateTime.now().toUtc().toIso8601String(),
    'favorites': favorites.map((c) => c.toJson()).toList(),
    'history': history.map((h) => h.toJson()).toList(),
    'metadata': metadata,
    'bookmarks': bookmarks,
    'options': {
      for (final e in options.entries)
        if (!e.key.startsWith('webdav.')) e.key: e.value,
    },
    'tombstones': tombstones,
    'favoriteTimes': favoriteTimes,
    'sources': sourceProfiles,
  };
  Future<void> restore(
    Map<String, dynamic> j, {
    bool restoreOptions = false,
  }) async {
    if (j['format'] != 'manxia' || (j['schema'] as num? ?? 0) > 2) {
      throw const FormatException('这不是受支持的漫匣备份。');
    }
    final imported = (j['favorites'] as List? ?? [])
        .map((e) => Comic.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    final records = (j['history'] as List? ?? [])
        .map((e) => ReadingRecord.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    final profiles = (j['sources'] as List? ?? [])
        .map((p) => SourceProfile(Map<String, dynamic>.from(p)).json)
        .toList();
    for (final pair in {
      'tombstones': tombstones,
      'favoriteTimes': favoriteTimes,
    }.entries) {
      for (final e in Map<String, int>.from(j[pair.key] ?? {}).entries) {
        if (e.value > (pair.value[e.key] ?? -1)) pair.value[e.key] = e.value;
      }
    }
    final books = {
      for (final b in favorites) b.path: b,
      for (final b in imported) b.path: b,
    };
    favorites
      ..clear()
      ..addAll(
        books.values.where(
          (b) =>
              (favoriteTimes[b.path] ?? 0) >
              (tombstones['book:${b.path}'] ?? -1),
        ),
      );
    final merged = {for (final r in history) r.comic.path: r};
    for (final r in records) {
      if (r.updatedAt > (merged[r.comic.path]?.updatedAt ?? 0)) {
        merged[r.comic.path] = r;
      }
    }
    history
      ..clear()
      ..addAll(
        merged.values
            .where(
              (r) =>
                  r.updatedAt > (tombstones['history:${r.comic.path}'] ?? -1),
            )
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
      );
    for (final e in (j['metadata'] as Map? ?? {}).entries) {
      final incoming = Map<String, dynamic>.from(e.value);
      if ((incoming['updatedAt'] as num? ?? 0) >=
          (metadata[e.key]?['updatedAt'] as num? ?? 0)) {
        metadata[e.key] = incoming;
      }
    }
    final marks = {for (final b in bookmarks) b['id']: b};
    for (final b in j['bookmarks'] as List? ?? []) {
      marks[b['id']] = Map<String, dynamic>.from(b);
    }
    bookmarks
      ..clear()
      ..addAll(
        marks.values.where(
          (b) =>
              (b['createdAt'] as num? ?? 0) >
              (tombstones['bookmark:${b['id']}'] ?? -1),
        ),
      );
    for (final p in profiles) {
      if (!sourceProfiles.any((s) => s['id'] == p['id'])) {
        sourceProfiles.add(Map<String, dynamic>.from(p));
      }
    }
    await prefs.setString(
      'favorites',
      jsonEncode(favorites.map((b) => b.toJson()).toList()),
    );
    await prefs.setString(
      'history',
      jsonEncode(history.map((r) => r.toJson()).toList()),
    );
    await prefs.setBool('demo', false);
    if (restoreOptions) {
      for (final e in Map<String, dynamic>.from(j['options'] ?? {}).entries) {
        if (!e.key.startsWith('webdav.')) options[e.key] = e.value;
      }
    }
    // Device addresses, passwords and appearance remain local. Reader preferences
    // live with each comic's timestamped metadata and are merged above.
    await persistFeatures();
  }
}
