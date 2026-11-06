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

/// Leave ambiguous editions and works with missing author metadata separate.
List<List<Comic>> groupSearchComics(List<Comic> books) {
  (String, String) identity(Comic book) =>
      (normalizedTitle(book.title), normalizedTitle(book.author));

  final matches = <(String, String), List<Comic>>{};
  for (final book in books) {
    final key = identity(book);
    if (key.$1.isNotEmpty && key.$2.isNotEmpty) {
      (matches[key] ??= []).add(book);
    }
  }
  matches.removeWhere(
    (_, variants) =>
        variants.map((variant) => variant.sourceId).toSet().length !=
        variants.length,
  );
  final emitted = <(String, String)>{};
  final groups = <List<Comic>>[];
  for (final book in books) {
    final key = identity(book);
    final variants = matches[key];
    if (variants == null) {
      groups.add([book]);
    } else if (emitted.add(key)) {
      groups.add(variants);
    }
  }
  return groups;
}
