import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/dm5_source.dart';

void main() {
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
