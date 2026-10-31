import 'dart:convert';
import 'comic.dart';
import 'source_profile.dart';

void validateBackup(Map<String, dynamic> value) {
  if (value['format'] != 'manxia' ||
      (value['schema'] != null && value['schema'] is! num) ||
      (value['schema'] as num? ?? 0) > 2) {
    throw const FormatException('这不是受支持的漫匣备份。');
  }
  for (final key in ['favorites', 'history', 'bookmarks', 'sources']) {
    if (value[key] != null && value[key] is! List) {
      throw FormatException('备份字段格式错误：$key');
    }
  }
  for (final key in ['metadata', 'options', 'tombstones', 'favoriteTimes']) {
    if (value[key] != null && value[key] is! Map) {
      throw FormatException('备份字段格式错误：$key');
    }
  }
  for (final c in value['favorites'] as List? ?? []) {
    Comic.fromJson(Map<String, dynamic>.from(c));
  }
  for (final r in value['history'] as List? ?? []) {
    ReadingRecord.fromJson(Map<String, dynamic>.from(r));
  }
  for (final p in value['sources'] as List? ?? []) {
    SourceProfile(Map<String, dynamic>.from(p));
  }
  for (final e in (value['metadata'] as Map? ?? {}).entries) {
    if (e.key is! String || e.value is! Map) {
      throw const FormatException('逐本资料格式错误');
    }
    final m = e.value as Map;
    if (m['updatedAt'] != null && m['updatedAt'] is! num) {
      throw const FormatException('资料时间格式错误');
    }
    if (m['tags'] != null) List<String>.from(m['tags']);
    if (m['chapterPaths'] != null) List<String>.from(m['chapterPaths']);
    if (m['reader'] != null) Map<String, dynamic>.from(m['reader']);
  }
  for (final key in ['tombstones', 'favoriteTimes']) {
    Map<String, int>.from(value[key] ?? {});
  }
  for (final b in value['bookmarks'] as List? ?? []) {
    if (b is! Map ||
        b['id'] is! String ||
        (b['createdAt'] != null && b['createdAt'] is! num)) {
      throw const FormatException('书签格式错误');
    }
  }
}

class BackupPreview {
  BackupPreview(this.current, this.incoming) {
    validateBackup(incoming);
  }
  final Map<String, dynamic> current, incoming;
  Map<String, Map> records(String key, String id) => {
    for (final e in current[key] as List? ?? [])
      (key == 'history' ? e['comic']['path'] : e[id]) as String: e as Map,
  };
  int get newBooks {
    final paths = (current['favorites'] as List).map((e) => e['path']).toSet();
    return (incoming['favorites'] as List? ?? [])
        .where((e) => !paths.contains(e['path']))
        .length;
  }

  List<Map> get progressChanges {
    final local = records('history', '');
    return (incoming['history'] as List? ?? [])
        .whereType<Map>()
        .where((e) => jsonEncode(e) != jsonEncode(local[e['comic']['path']]))
        .toList();
  }

  int get conflicts {
    final local = records('history', '');
    var count = progressChanges
        .where((e) => local.containsKey(e['comic']['path']))
        .length;
    final meta = current['metadata'] as Map? ?? {};
    count += (incoming['metadata'] as Map? ?? {}).entries
        .where(
          (e) =>
              meta.containsKey(e.key) &&
              jsonEncode(meta[e.key]) != jsonEncode(e.value),
        )
        .length;
    final marks = records('bookmarks', 'id');
    count += (incoming['bookmarks'] as List? ?? [])
        .where(
          (e) =>
              marks.containsKey(e['id']) &&
              jsonEncode(marks[e['id']]) != jsonEncode(e),
        )
        .length;
    return count;
  }

  Map<String, dynamic> mergeInput({
    bool keepLocal = false,
    bool applyDeletions = false,
  }) {
    final result = Map<String, dynamic>.from(jsonDecode(jsonEncode(incoming)));
    if (!applyDeletions) result['tombstones'] = <String, int>{};
    if (keepLocal) {
      final local = records('history', '');
      result['history'] = (result['history'] as List? ?? [])
          .where((e) => !local.containsKey(e['comic']['path']))
          .toList();
      final meta = current['metadata'] as Map? ?? {};
      result['metadata'] = Map<String, dynamic>.from(result['metadata'] ?? {})
        ..removeWhere((key, _) => meta.containsKey(key));
      final marks = records('bookmarks', 'id');
      result['bookmarks'] = (result['bookmarks'] as List? ?? [])
          .where((e) => !marks.containsKey(e['id']))
          .toList();
    }
    return result;
  }
}
