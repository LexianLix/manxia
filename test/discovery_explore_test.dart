import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/discovery.dart';
import 'package:manxia/data/discovery_explore.dart';

void main() {
  test(
    'outside-chart picks require recommendation provenance and deduplicate',
    () {
      const hot = Comic(path: '/hot', title: '热门', cover: '', tags: ['冒险']);
      const hidden = Comic(
        path: '/hidden',
        title: '小众',
        cover: '',
        tags: ['日常'],
      );
      const ordinary = Comic(path: '/other', title: '普通目录', cover: '');
      final explore = DiscoveryExplore(
        Discovery(
          books: [hot, hidden, ordinary],
          sections: {
            '强势安利': [hot, hidden],
            '完结佳作': [hidden],
            '上升最快': [ordinary],
            'VIP推荐': [ordinary],
          },
          ranks: {
            '人气': [hot],
          },
          capturedAt: 'fixture',
        ),
      );
      expect(explore.outsideCharts, {
        '强势安利': [hidden],
      });
      expect(explore.all, hasLength(3));
      expect(explore.filter(explore.all, '日常'), [hidden]);
      expect(explore.availableTopics.toSet(), {'冒险', '日常'});
    },
  );
  test('missing metadata does not invent genres or curated picks', () {
    const book = Comic(path: '/book', title: '故事', cover: '');
    final explore = DiscoveryExplore(
      Discovery(books: [book], sections: {}, ranks: {}, capturedAt: 'fixture'),
    );
    expect(explore.availableTopics, isEmpty);
    expect(explore.outsideCharts, isEmpty);
  });
}
