import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/discovery.dart';
import 'package:manxia/data/dm5_source.dart';

void main() {
  test('source more links survive caching without mixing unrelated URLs', () {
    const cover =
        '<ul><li><div class="manga-list-2-cover"><a href="/manhua-first/" title="第一册"><img src="https://images.cdndm5.com/1.jpg"></a></div></li></ul>';
    final data = Dm5Source.parseDiscovery('''
      <div class="manga-list"><div class="manga-list-title">精选书单<a href="/manhua-curated/">更多</a></div>$cover</div>
      <div class="manga-list"><div class="manga-list-title">外部广告<a href="https://other.example/manhua-ad/">更多</a></div>$cover</div>
      <div class="manga-list-title-right-item">人气</div><div id="rank_1">$cover<a href="/manhua-ranking/">更多</a></div>
    ''');
    expect(data.sectionPaths, {'精选书单': '/manhua-curated/'});
    expect(data.rankPaths, {'人气': '/manhua-ranking/'});
    final restored = Discovery.fromJson(data.toJson());
    expect(restored.sectionPaths, data.sectionPaths);
    expect(restored.rankPaths, data.rankPaths);
    final old = data.toJson()
      ..remove('sectionPaths')
      ..remove('rankPaths');
    expect(Discovery.fromJson(old).sectionPaths, isEmpty);
  });
  test('daily edition contains twelve unique real books', () {
    final books = List.generate(
      30,
      (i) => Comic(path: '/manhua-$i/', title: '$i', cover: ''),
    );
    final discovery = Discovery(
      books: books,
      sections: {},
      ranks: {},
      capturedAt: '2026-10-22',
    );
    expect(
      discovery.daily(DateTime(2026, 10, 22)).map((b) => b.path).toSet(),
      hasLength(12),
    );
  });
  test('catalog retains lazy covers instead of dropping valid books', () {
    final books = Dm5Source.parseCatalog('''<title>搜索</title><ul>
      <li><div class="manga-list-2-cover"><a href="/manhua-first/" title="第一册"><img src="https://m.dm5.com/loading.gif" data-src="https://images.cdndm5.com/first.jpg"></a></div></li>
      <li><div class="book-list-cover"><a href="https://m.dm5.com/manhua-second/"><img data-original="//images.cdndm5.com/second.jpg"></a></div><p class="book-list-info-title">第二册</p></li>
      <li><div class="book-list-cover"><a href="https://other.example/manhua-ad/" title="广告"><img src="https://images.cdndm5.com/ad.jpg"></a></div></li>
    </ul>''');
    expect(books.map((b) => b.title), ['第一册', '第二册']);
    expect(books.first.cover, 'https://images.cdndm5.com/first.jpg');
  });
}
