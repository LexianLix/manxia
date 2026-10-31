import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/data/chapter_links.dart';
import 'package:manxia/data/dm5_source.dart';

class _Source extends Dm5Source {
  _Source(this.links);
  final List<String> links;
  @override
  Future<List<String>> networkPages(String path) async => links;
}

void main() {
  test('refresh refuses changed page count or completed page order', () async {
    final source = _Source([
      'https://images.cdndm5.com/2.png?new',
      'https://images.cdndm5.com/1.png?new',
    ]);
    addTearDown(source.close);
    const original = [
      'https://images.cdndm5.com/1.png?old',
      'https://images.cdndm5.com/2.png?old',
    ];
    await expectLater(
      refreshChapterLinks(source, '/chapter/', original, completed: 1),
      throwsA(isA<SourceException>()),
    );
    source.links.removeLast();
    await expectLater(
      refreshChapterLinks(source, '/chapter/', original, completed: 0),
      throwsA(isA<SourceException>()),
    );
  });
}
