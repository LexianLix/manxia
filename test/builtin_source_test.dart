import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:manxia/data/builtin_source.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/dm5_source.dart';
import 'package:manxia/data/library.dart';
import 'package:manxia/data/plugin.dart';
import 'package:manxia/data/retired_sources.dart';
import 'package:manxia/data/source_hub.dart';

const catalog =
    '''<div class="mh-item"><a><img src="https://cover.mangabz.com/a.jpg"></a>
<h2><a href="/142bz/">测试漫画</a></h2><p class="chapter"><a>第2话</a></p></div>''';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'native discovery search detail and reader require no script sandbox',
    () async {
      SharedPreferences.setMockInitialValues({});
      final library = Library(await SharedPreferences.getInstance());
      await library.load();
      await library.setOption('source', 'mangabz');
      final requests = <Uri>[];
      final hub = SourceHub(
        library,
        transport: MockClient((r) async {
          requests.add(r.url);
          final body = switch (r.url.path) {
            '/142bz/' =>
              '<p class="detail-info-title">测试漫画</p><div class="detail-list-form-con"><a href="/m11/">第1话（2P）</a></div>',
            '/m11/' => 'var MANGABZ_IMAGE_COUNT=2;',
            '/m11/chapterimage.ashx' =>
              '''var pix="https://image.mangabz.com/a";var pvalue=["/1.jpg","/2.jpg"];var key='token';''',
            _ => catalog,
          };
          return http.Response(
            body,
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }),
      );
      addTearDown(hub.close);
      expect((await hub.discover()).books.single.sourceId, 'mangabz');
      final first = await hub.catalog('/');
      expect(first.canPaginate, true);
      expect(requests.where((u) => u.path == '/manga-list-p1/').length, 1);
      final search = await hub.search('火影 &');
      expect(requests.last.queryParameters['title'], '火影 &');
      final detail = await hub.detail(search.single);
      final pages = await hub.pages(detail.chapters.single.path);
      expect(pages.length, 2);
      expect(
        pages.first,
        'https://image.mangabz.com/a/1.jpg?cid=11&key=token&uk=',
      );
      expect(
        hub.originalUrl(search.single.path).toString(),
        'https://www.mangabz.com/142bz/',
      );
      await library.setOption('source', 'dm5');
      expect(
        (await hub.catalogNext(first.parameters, 2)).single.sourceId,
        'mangabz',
      );
      expect(requests.last.path, '/manga-list-p2/');
    },
  );
  test('concurrent requests coalesce and failures can be retried', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return http.Response(
        calls == 1 ? 'down' : catalog,
        calls == 1 ? 503 : 200,
        headers: {'content-type': 'text/html; charset=utf-8'},
      );
    });
    addTearDown(client.close);
    final source = BuiltinSource('mangabz', client);
    await expectLater(source.catalog(), throwsA(isA<SourceException>()));
    final result = await Future.wait([source.catalog(), source.catalog()]);
    expect(result.every((b) => b.isNotEmpty), true);
    expect(calls, 2);
  });
  test(
    'Dongman traverses public catalog pages and ignores selected pagination anchors',
    () async {
      final client = MockClient((r) async {
        if (r.url.path == '/dailySchedule') {
          return http.Response(
            '<div class="daily_section"><a class="card_item" href="/episodeList?titleNo=1"><p class="subj">试读</p></a></div>',
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }
        final n =
            r.url.path != '/episodeList' && r.url.queryParameters['page'] == '2'
            ? 1
            : 2;
        final body = r.url.path.endsWith('/viewer')
            ? '<div id="_imageList"><img data-url="https://cdn.dongmanmanhua.cn/1.jpg"></div>'
            : '''<div class="detail_header"><div class="info"><h1 class="subj">公开试读</h1></div></div>
          <ul id="_listUl"><li><a href="/FANTASY/demo/$n/viewer?title_no=1&amp;episode_no=$n"><span class="subj">第$n话</span></a></li></ul>
          <div class="paginate"><a href="#">1</a><a href="/FANTASY/demo/list?title_no=1&amp;page=2">2</a></div>''';
        return http.Response(
          body,
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      });
      addTearDown(client.close);
      final source = BuiltinSource('dongman', client);
      final detail = await source.detail(
        Comic(
          path: BuiltinSource.encode('dongman', '/episodeList?titleNo=1'),
          title: '试读',
          cover: '',
          sourceId: 'dongman',
        ),
      );
      expect(detail.chapters.map((c) => c.title), ['第2话', '第1话']);
      expect(
        (await source.pages(detail.chapters.last.path)).single,
        'https://cdn.dongmanmanhua.cn/1.jpg',
      );
      expect(await source.catalog(page: 2), isEmpty);
    },
  );
  test(
    'unrecognised loading shells and foreign addresses fail explicitly',
    () async {
      final client = MockClient(
        (_) async => http.Response('<title>Loading...</title>', 200),
      );
      addTearDown(client.close);
      final source = BuiltinSource('mangabz', client);
      await expectLater(
        source.catalog(query: '不存在'),
        throwsA(isA<SourceException>()),
      );
      expect(
        () => source.checked('//evil.com/path'),
        throwsA(isA<SourceException>()),
      );
      expect(
        () => source.image('https://mangabz.com.evil.test/a.jpg'),
        throwsA(isA<SourceException>()),
      );
      await expectLater(
        source.pages(BuiltinSource.encode('mangabz', '/m1/')),
        throwsA(isA<SourceException>()),
      );
    },
  );
  test(
    'withdrawal retains personal books across startup and backup restore',
    () async {
      const book = Comic(
        path: 'custom:kanman:old',
        title: '保留的收藏',
        cover: '',
        sourceId: 'kanman',
      );
      final entries = [
        for (final id in retiredSourcePlugins)
          {
            'manifest': {'id': id},
            'enabled': true,
          },
      ];
      SharedPreferences.setMockInitialValues({
        'favorites': jsonEncode([book.toJson()]),
        'features.v2': jsonEncode({
          'options': {'source': 'kanman', 'plugins.installed': entries},
        }),
      });
      final library = Library(await SharedPreferences.getInstance());
      await library.load();
      expect(library.favorites.single.path, book.path);
      expect(library.option<String>('source', ''), 'mangabz');
      expect(library.options['plugins.installed'], isEmpty);
      expect(PluginSnapshot({'plugins.installed': entries}).sources, isEmpty);
      await library.restore({
        'format': 'manxia',
        'schema': 2,
        'favorites': [],
        'options': {'source': 'manhuagui', 'plugins.installed': entries},
      }, restoreOptions: true);
      expect(library.favorites.single.path, book.path);
      expect(library.options['plugins.installed'], isEmpty);
      expect(library.option<String>('source', ''), 'mangabz');
    },
  );
}
