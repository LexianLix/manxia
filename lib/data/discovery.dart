import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'comic.dart';

class Discovery {
  Discovery({
    required this.books,
    required this.sections,
    required this.ranks,
    required this.capturedAt,
    this.cached = false,
    this.sectionPaths = const {},
    this.rankPaths = const {},
  });
  final List<Comic> books;
  final Map<String, List<Comic>> sections, ranks;
  final String capturedAt;
  final bool cached;
  final Map<String, String> sectionPaths, rankPaths;
  Map<String, dynamic> toJson() => {
    'books': books.map((b) => b.toJson()).toList(),
    'sections': sections.map(
      (k, v) => MapEntry(k, v.map((b) => b.toJson()).toList()),
    ),
    'ranks': ranks.map(
      (k, v) => MapEntry(k, v.map((b) => b.toJson()).toList()),
    ),
    'capturedAt': capturedAt,
    'sectionPaths': sectionPaths,
    'rankPaths': rankPaths,
  };
  factory Discovery.fromJson(Map<String, dynamic> j, {bool cached = false}) {
    List<Comic> list(dynamic v) => (v as List)
        .map((e) => Comic.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    Map<String, List<Comic>> groups(dynamic v) =>
        (v as Map).map((k, v) => MapEntry(k.toString(), list(v)));
    return Discovery(
      books: list(j['books']),
      sections: groups(j['sections']),
      ranks: groups(j['ranks']),
      capturedAt: j['capturedAt'],
      cached: cached,
      sectionPaths: Map<String, String>.from(j['sectionPaths'] ?? {}),
      rankPaths: Map<String, String>.from(j['rankPaths'] ?? {}),
    );
  }
  List<Comic> daily(DateTime day, {int edition = 0, int count = 12}) {
    final date = day.toIso8601String().substring(0, 10);
    final sorted = {for (final book in books) book.path: book}.values.toList()
      ..sort((a, b) {
        String score(Comic c) =>
            sha256.convert(utf8.encode('$date/$edition/${c.path}')).toString();
        return score(a).compareTo(score(b));
      });
    return sorted.take(count).toList();
  }

  List<Comic> forYou(Iterable<Comic> liked, {int count = 8}) {
    final seen = liked.map((c) => c.path).toSet();
    final weights = <String, int>{};
    final memberships = <String, Set<String>>{};
    for (final e in sections.entries) {
      for (final c in e.value) {
        (memberships[c.path] ??= {}).add(e.key);
      }
    }
    Set<String> features(Comic c) => {...c.tags, ...?memberships[c.path]};
    for (final c in liked) {
      for (final tag in features(c)) {
        weights[tag] = (weights[tag] ?? 0) + 1;
      }
    }
    int score(Comic c) => features(c).fold(0, (s, t) => s + (weights[t] ?? 0));
    final candidates = books.where((c) => !seen.contains(c.path)).toList()
      ..sort((a, b) {
        final compared = score(b).compareTo(score(a));
        return compared == 0 ? a.path.compareTo(b.path) : compared;
      });
    return candidates.take(count).toList();
  }
}
