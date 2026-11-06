import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/search_relevance.dart';

void main() {
  test('same-source editions and missing authors are kept distinct', () {
    Comic book(String id, String path, String author) =>
        Comic(sourceId: id, path: path, title: '星光', author: author, cover: '');
    final first = book('dm5', '/one', '同作者');
    final second = book('external', '/two', '同作者');
    final unknown = book('external', '/unknown', '');
    expect(groupSearchComics([first, second, unknown]), [
      [first, second],
      [unknown],
    ]);
    final edition = book('dm5', '/special', '同作者');
    expect(groupSearchComics([first, second, edition, unknown]), [
      [first],
      [second],
      [edition],
      [unknown],
    ]);
  });
  test(
    'exact and full-width normalized names precede related works without shuffling ties',
    () {
      Comic book(String path, String title) =>
          Comic(path: path, title: title, cover: '');
      final books = [
        book('/a', '忍者神龟 x 火影忍者'),
        book('/b', '火影忍者特典'),
        book('/c', '火影忍者'),
        book('/d', '火影忍者画集'),
      ];
      expect(relevantComics(books, '火影忍者').map((c) => c.path), [
        '/c',
        '/b',
        '/d',
        '/a',
      ]);
      expect(normalizedTitle('ＯＮＥ　ＰＩＥＣＥ'), normalizedTitle('one piece'));
      expect(relevantComics([...books, books.first], '火影忍者'), hasLength(4));
    },
  );
}
