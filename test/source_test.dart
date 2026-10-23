import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/dm5_source.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const fallback = Comic(path: '/manhua-test/', title: '测试', cover: '');
  test(
    'external search and recommended chapters do not become this comic catalog',
    () {
      expect(
        () => Dm5Source.parseDetail(
          '''<p class="detail-main-info-title">古见同学有交流障碍症</p>
      <div class="detail-fix-bottom"><a class="detail-bottom-btn">全网搜索(10000个结果)</a></div>
      <div class="manga-list"><a href="/m987689/">同类作品</a></div>''',
          fallback,
        ),
        throwsA(
          isA<SourceException>().having(
            (e) => e.message,
            'actual availability',
            contains('外部搜索'),
          ),
        ),
      );
    },
  );
  test(
    'an unrecognized mobile directory falls back to the public desktop edition',
    () async {
      final hosts = <String>[];
      final source = Dm5Source(
        client: MockClient((request) async {
          hosts.add(request.url.host);
          if (request.url.host == 'www.dm5.com') {
            expect(request.headers['User-Agent'], contains('Windows'));
            expect(request.headers['Referer'], 'https://www.dm5.com/');
          }
          return http.Response(
            request.url.host == 'm.dm5.com'
                ? '<p class="detail-main-info-title">火影忍者</p>'
                : '''<div class="banner_detail_form"><div class="cover"><img src="https://img.cdndm5.com/naruto.jpg"></div>
          <div class="info"><p class="title">火影忍者<span>9.1分</span></p><p class="subtitle">作者：岸本齐史</p></div></div>
          <ul id="detail-list-select-1"><li><a href="/m5196/">第1卷</a></li></ul>''',
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }),
      );
      addTearDown(source.close);
      final result = await source.detail(fallback);
      expect(hosts, ['m.dm5.com', 'www.dm5.com']);
      expect(result.chapters.single.path, '/m5196/');
      expect(result.comic.title, '火影忍者');
      expect(result.comic.author, '岸本齐史');
      final attempts =
          source.detailDiagnostics[fallback.path]!['attempts'] as List;
      expect((attempts.first as Map)['chapters'], 0);
      expect((attempts.last as Map)['chapters'], 1);
    },
  );
  test('a known site notice does not silently try another edition', () async {
    var requests = 0;
    final source = Dm5Source(
      client: MockClient((_) async {
        requests++;
        return http.Response(
          '<p class="detail-main-info-title">漫画</p><div class="warning-bar">作品已下架</div>',
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      }),
    );
    addTearDown(source.close);
    await expectLater(
      source.detail(fallback),
      throwsA(
        isA<SourceException>().having(
          (e) => e.message,
          'notice',
          contains('下架'),
        ),
      ),
    );
    expect(requests, 1);
  });
  test(
    'an empty parse is a retryable failure, not a successful empty book',
    () {
      expect(
        () => Dm5Source.parseDetail(
          '<p class="detail-main-info-title">测试</p>',
          fallback,
        ),
        throwsA(isA<SourceException>()),
      );
    },
  );
  test(
    'recognize the actual app migration notice separately from parse failure',
    () {
      expect(
        () => Dm5Source.parseDetail(
          '''<p class="detail-main-info-title">英雄再临</p>
      <div class="warning-bar"><p>为了提升用户阅读体验故全篇转移到<b>漫画人APP</b></p></div>''',
          fallback,
        ),
        throwsA(
          isA<SourceException>().having(
            (e) => e.message,
            'reason',
            contains('迁移'),
          ),
        ),
      );
    },
  );
  test(
    'normalize thumbnail chapters using the source sort flag and title node',
    () {
      final result = Dm5Source.parseDetail(
        '''<script>var DM5_COMIC_SORT = 1;</script>
    <p class="detail-main-info-title">山海逆战</p>
    <ul class="detail-list-2 detail-list-select" id="detail-list-select-1">
      <li><a href="/m518896/" class="chapteritem"><div><p class="detail-list-2-info-title">第1回 第一回（上）</p><p>2017-08-17</p></div></a></li>
      <li><a href="/m518898/" class="chapteritem"><div><p class="detail-list-2-info-title">第2回 第一回（中）</p><p>2017-08-17</p></div></a></li>
    </ul>''',
        fallback,
      );
      expect(result.chapters.map((c) => c.path), ['/m518898/', '/m518896/']);
      expect(result.chapters.last.title, '第1回 第一回（上）');
    },
  );
  test(
    'chapter links accept the canonical source hosts without losing groups',
    () {
      final result = Dm5Source.parseDetail(
        '''<p class="detail-main-info-title">测试</p>
    <ul id="detail-list-select-2"><li><a href="https://www.dm5.com/m3/?x=1">第1卷</a></li>
    <li><a href="//m.dm5.com/m4/">第2卷</a></li><li><a href="https://example.com/m5/">外链</a></li></ul>''',
        fallback,
      );
      expect(result.chapters.map((c) => c.path), ['/m3/', '/m4/']);
      expect(result.chapters.map((c) => c.group), ['卷', '卷']);
    },
  );
  test(
    'retry uses a new response and populates the catalog after an empty page',
    () async {
      var requests = 0;
      final source = Dm5Source(
        client: MockClient((_) async {
          requests++;
          return http.Response(
            '''<p class="detail-main-info-title">测试</p>${requests <= 2 ? '' : '<ul class="detail-list-select"><li><a href="/m1/">第1话</a></li></ul>'}''',
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }),
      );
      addTearDown(source.close);
      await expectLater(
        source.detail(fallback),
        throwsA(isA<SourceException>()),
      );
      final result = await source.detail(fallback);
      expect(result.chapters.single.path, '/m1/');
      expect(Dm5Source.chapterCatalogs[fallback.path]!.single.path, '/m1/');
    },
  );
  test(
    'read catalog entries from home and search layouts, discard non-comic links',
    () {
      final result = Dm5Source.parseCatalog(
        '''<title>漫画搜索</title><ul><li><div class="book-list-cover"><a href="/manhua-test/" title="测试漫画"><img src="https://img.cdndm5.com/cover.jpg"></a></div></li><li><div class="manga-list-2-cover"><a href="/login/" title="广告"><img src="https://img.cdndm5.com/ad.jpg"></a></div></li></ul>''',
      );
      expect(result.length, 1);
      expect(result.first.title, '测试漫画');
      expect(result.first.path, '/manhua-test/');
    },
  );
  test('keep separate chapter groups and discard duplicate navigation links', () {
    final result = Dm5Source.parseDetail(
      '''<p class="detail-main-info-title">测试漫画</p><ul id="detail-list-select-1" class="detail-list-select"><li><a href="/m2/">第2话</a></li><li><a href="/m1/">第1话</a></li><li><a href="/m1/">重复</a></li></ul><ul id="detail-list-select-2" class="detail-list-select"><li><a href="/m3/">第1卷</a></li></ul>''',
      const Comic(path: '/manhua-test/', title: '原名', cover: ''),
    );
    expect(result.chapters.map((c) => c.group), ['连载', '连载', '卷']);
    expect(result.comic.title, '测试漫画');
  });
  test('decode packed chapter data without evaluating JavaScript', () {
    const packed =
        r"eval(function(p,a,c,k,e,d){return p;}('0 1=[\'2://3.4.5/6.7\'];',8,8,'var|newImgs|https|images|cdndm5|com|page|jpg'.split('|'),0,{}))";
    expect(Dm5Source.parsePages(packed), [
      'https://images.cdndm5.com/page.jpg',
    ]);
  });
  test('reject missing image data and unrelated image hosts', () {
    expect(
      () => Dm5Source.parsePages('<html>请登录后阅读</html>'),
      throwsA(isA<SourceException>()),
    );
    expect(
      () => Dm5Source.parsePages("var newImgs=['https://example.com/a.jpg'];"),
      throwsA(isA<SourceException>()),
    );
  });
}
