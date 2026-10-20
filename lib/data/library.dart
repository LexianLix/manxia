import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'comic.dart';

class Library extends ChangeNotifier {
  Library(this.prefs);
  final SharedPreferences prefs;
  List<Comic> favorites = [];
  List<Comic> samples = [];
  List<ReadingRecord> history = [];
  bool demo = true, dark = false, motion = true, grid = false, rtl = false;
  String mode = 'page';
  Future<void> load() async {
    samples = Comic.decode(await rootBundle.loadString('assets/catalog.json'));
    demo = prefs.getBool('demo') ?? true;
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

  List<Comic> get books => demo && favorites.isEmpty ? samples : favorites;
  bool contains(Comic c) => favorites.any((b) => b.path == c.path);
  ReadingRecord? record(Comic c) =>
      history.where((h) => h.comic.path == c.path).firstOrNull;
  Future<void> toggle(Comic c) async {
    if (contains(c)) {
      favorites.removeWhere((b) => b.path == c.path);
    } else {
      favorites.add(c);
    }
    demo = false;
    notifyListeners();
    await prefs.setBool('demo', demo);
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
    history.clear();
    notifyListeners();
    await prefs.remove('history');
  }
}
