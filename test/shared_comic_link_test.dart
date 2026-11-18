import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/data/builtin_source.dart';
import 'package:manxia/data/shared_comic_link.dart';

void main() {
  test('shared book links use the same identities as browsing', () {
    expect(
      comicFromSharedText(
        'https://m.dm5.com/manhua-huoyingrenzhe/?from=share',
      )?.path,
      '/manhua-huoyingrenzhe/',
    );
    expect(
      comicFromSharedText('火影忍者 https://www.mangabz.com/142bz/)')?.path,
      BuiltinSource.encode('mangabz', '/142bz/'),
    );
    final dongman = BuiltinSource.encode(
      'dongman',
      '/episodeList?titleNo=1954',
    );
    expect(
      comicFromSharedText(
        'https://www.dongmanmanhua.cn/episodeList?titleNo=1954',
      )?.path,
      dongman,
    );
    expect(
      comicFromSharedText(
        'https://www.dongmanmanhua.cn/SUSPENSE/ruchuyizhedenver/list?title_no=1954。',
      )?.path,
      dongman,
    );
  });

  test(
    'unrelated links and ambiguous detail IDs stay out of source requests',
    () {
      for (final text in [
        'A comic without a link',
        'https://mangabz.com.example.org/142bz/',
        'https://user@www.mangabz.com/142bz/',
        'https://www.dm5.com:8080/manhua-huoyingrenzhe/',
        'https://www.mangabz.com/m12345/',
        'https://www.dongmanmanhua.cn/search?titleNo=1954',
        'https://www.dongmanmanhua.cn/episodeList?titleNo=1954&title_no=2',
      ]) {
        expect(comicFromSharedText(text), isNull, reason: text);
      }
    },
  );
}
