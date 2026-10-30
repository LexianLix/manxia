import 'comic.dart';

String normalizedTitle(String value) {
  final folded = String.fromCharCodes(
    value.runes.map((r) => r >= 0xff01 && r <= 0xff5e ? r - 0xfee0 : r),
  );
  return folded.toLowerCase().replaceAll(RegExp(r'[\s·・:：\-—_()（）\[\]【】]'), '');
}

/// Exact and normalized names first; retain source order within each tier.
List<Comic> relevantComics(List<Comic> books, String query) {
  final q = normalizedTitle(query);
  int score(Comic comic) {
    if (comic.title.trim().toLowerCase() == query.trim().toLowerCase()) {
      return 0;
    }
    final title = normalizedTitle(comic.title);
    if (title == q) return 1;
    if (title.startsWith(q)) return 2;
    if (title.contains(q)) return 3;
    return 4;
  }

  final unique = <String, Comic>{};
  for (final book in books) {
    unique.putIfAbsent('${book.sourceId}:${book.path}', () => book);
  }
  final indexed = unique.values.indexed.toList();
  indexed.sort((a, b) {
    final order = score(a.$2).compareTo(score(b.$2));
    return order == 0 ? a.$1.compareTo(b.$1) : order;
  });
  return indexed.map((e) => e.$2).toList();
}
