import 'comic.dart';
import 'discovery.dart';

/// Recommendation provenance stays explicit; a shuffled catalog is not a review.
class DiscoveryExplore {
  DiscoveryExplore(this.snapshot);
  final Discovery snapshot;
  List<Comic> get all => {
    for (final book in [
      ...snapshot.books,
      ...snapshot.sections.entries
          .where((e) => !e.key.contains('VIP'))
          .expand((e) => e.value),
      ...snapshot.ranks.values.expand((e) => e),
    ])
      '${book.sourceId}/${book.path}': book,
  }.values.toList();

  Set<String> topics(Comic book) =>
      book.tags.where((t) => t.trim().isNotEmpty).toSet();
  List<String> get availableTopics {
    final counts = <String, int>{};
    for (final book in all) {
      for (final tag in topics(book)) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    return counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  }

  List<Comic> filter(Iterable<Comic> books, String? topic) =>
      books.where((b) => topic == null || topics(b).contains(topic)).toList();

  Map<String, List<Comic>> get outsideCharts {
    final popular = snapshot.ranks.values
        .expand((e) => e)
        .map((b) => '${b.sourceId}/${b.path}')
        .toSet();
    final used = <String>{};
    return {
      for (final section in snapshot.sections.entries.where(
        (e) =>
            RegExp('精选|推荐|安利|佳作|书单').hasMatch(e.key) && !e.key.contains('VIP'),
      ))
        section.key: section.value.where((b) {
          final key = '${b.sourceId}/${b.path}';
          return !popular.contains(key) && used.add(key);
        }).toList(),
    }..removeWhere((_, books) => books.isEmpty);
  }
}
