import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/data/chapter_matching.dart';
import 'package:manxia/data/comic.dart';

void main() {
  test('chapter candidates separate volumes, extras and upper/lower parts', () {
    final matches = matchChapters(const Chapter('/old/', '第十二话（上）'), const [
      Chapter('/lower/', '第12回（下）'),
      Chapter('/volume/', '第12卷'),
      Chapter('/extra/', '番外 第12话'),
      Chapter('/upper/', '第12回（上）'),
      Chapter('/unclear/', '第12话'),
    ]);
    expect(matches.first.chapter.path, '/upper/');
    expect(matches.first.score, 80);
    expect(
      matches
          .where(
            (m) => ['/lower/', '/volume/', '/extra/'].contains(m.chapter.path),
          )
          .every((m) => m.score == 0),
      true,
    );
    expect(chapterNumber('第一百零二话'), 102);
    expect(chapterNumber('第壹佰贰拾叁回'), 123);
  });
}
