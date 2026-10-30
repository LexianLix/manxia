import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/search_relevance.dart';

void main() {
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
