import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'comic.dart';
import 'library_features.dart';
import 'metadata_backups.dart';

class Library extends ChangeNotifier with LibraryFeatures {
  Library(this.prefs);
  @override
  final SharedPreferences prefs;
  MetadataBackups? backups;
  @override
  void dispose() {
    backups?.dispose();
    super.dispose();
  }

  @override
  List<Comic> favorites = [];
  List<Comic> samples = [];
  @override
  List<ReadingRecord> history = [];
  bool demo = false, dark = false, motion = true, grid = false, rtl = false;
  String mode = 'page';
  @override
  Future<void> restore(
    Map<String, dynamic> j, {
    bool restoreOptions = false,
  }) async {
    await super.restore(j, restoreOptions: restoreOptions);
    demo = false;
    notifyListeners();
  }

  Future<void> load() async {
    loadFeatures();
    samples = Comic.decode(await rootBundle.loadString('assets/catalog.json'));
    // Old demo preferences must never populate the user's collection.
    dark = prefs.getBool('dark') ?? false;
    motion = prefs.getBool('motion') ?? true;
    grid = prefs.getBool('grid') ?? false;
    rtl = prefs.getBool('rtl') ?? false;
    mode = prefs.getString('readerMode') ?? 'page';
    try {
      favorites = Comic.decode(prefs.getString('favorites') ?? '[]');
    } catch (_) {
      favorites = [];
    }
    try {
      history = (jsonDecode(prefs.getString('history') ?? '[]') as List)
          .map((j) => ReadingRecord.fromJson(j))
          .toList();
    } catch (_) {
      history = [];
    }
    notifyListeners();
  }

  List<Comic> get books => favorites;
  bool contains(Comic c) => favorites.any((b) => b.path == c.path);
  ReadingRecord? record(Comic c) =>
      history.where((h) => h.comic.path == c.path).firstOrNull;
  Future<void> toggle(Comic c) async {
    if (contains(c)) {
      tombstones['book:${c.path}'] = DateTime.now().millisecondsSinceEpoch;
      favorites.removeWhere((b) => b.path == c.path);
    } else {
      final now = DateTime.now().millisecondsSinceEpoch;
      favoriteTimes[c.path] = now > (tombstones['book:${c.path}'] ?? -1)
          ? now
          : tombstones['book:${c.path}']! + 1;
      favorites.add(c);
    }
    demo = false;
    notifyListeners();
    await prefs.setBool('demo', demo);
    await persistFeatures();
    await prefs.setString(
      'favorites',
      jsonEncode(favorites.map((b) => b.toJson()).toList()),
    );
  }

  Future<void> save(ReadingRecord record) async {
    history.removeWhere((h) => h.comic.path == record.comic.path);
    history.insert(0, record);
    if (history.length > 100) history.removeLast();
    notifyListeners();
    await prefs.setString(
      'history',
      jsonEncode(history.map((r) => r.toJson()).toList()),
    );
  }

  Future<void> setting(String key, bool value) async {
    switch (key) {
      case 'dark':
        dark = value;
      case 'motion':
        motion = value;
      case 'grid':
        grid = value;
      case 'demo':
        demo = value;
      case 'rtl':
        rtl = value;
    }
    notifyListeners();
    await prefs.setBool(key, value);
  }

  Future<void> setMode(String value) async {
    mode = value;
    notifyListeners();
    await prefs.setString('readerMode', value);
  }

  Future<void> clearHistory() async {
    for (final r in history) {
      tombstones['history:${r.comic.path}'] =
          DateTime.now().millisecondsSinceEpoch;
    }
    history.clear();
    notifyListeners();
    await prefs.remove('history');
    await persistFeatures();
  }
}
