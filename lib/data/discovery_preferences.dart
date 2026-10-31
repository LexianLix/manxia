import 'comic.dart';
import 'library_features.dart';

String interestKey(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

extension DiscoveryPreferences on LibraryFeatures {
  List<String> blocked(String key) => List<String>.from(option<List>(key, []));
  Future<void> blockInterest(String key, String value, bool block) async {
    final values = blocked(key)
      ..removeWhere((s) => interestKey(s) == interestKey(value));
    if (block && value.trim().isNotEmpty) values.add(value.trim());
    await setOption(key, values);
  }

  Future<void> hideDiscoveryBook(Comic book, bool hide) => setMeta(book, {
    'discoveryHidden': hide,
    'discoveryHiddenBook': book.toJson(),
  });
  List<Comic> discoveryBooks(Iterable<Comic> books) {
    final authors = blocked('blockedAuthors').map(interestKey).toSet();
    final tags = blocked('blockedTags').map(interestKey).toSet();
    final favoritePaths = favorites.map((b) => b.path).toSet();
    return browseBooks(books).where((book) {
      if (meta(book)['discoveryHidden'] == true) return false;
      if (option<bool>('discoveryHideFavorites', false) &&
          favoritePaths.contains(book.path)) {
        return false;
      }
      if (option<bool>('discoveryHideRead', false) &&
          meta(book)['status'] == '已读') {
        return false;
      }
      if (book.tags.any((t) => tags.contains(interestKey(t)))) return false;
      final names = {
        interestKey(book.author),
        ...book.author.split(RegExp(r'[、，,;/]')).map(interestKey),
      };
      return !names.any(authors.contains);
    }).toList();
  }
}
