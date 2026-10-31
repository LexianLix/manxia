import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/discovery_preferences.dart';
import 'features_test.dart' as fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'discovery filtering is reversible and never hides the actual library or explicit searches',
    () async {
      final library = await fixtures.library();
      const a = Comic(
        path: '/a/',
        title: 'A',
        cover: '',
        author: 'Alice',
        tags: ['Fantasy'],
      );
      const b = Comic(path: '/b/', title: 'B', cover: '', author: 'Bob');
      await library.toggle(a);
      await library.setOption('discoveryHideFavorites', true);
      expect(library.discoveryBooks([a, b]), [b]);
      expect(library.favorites, [a]);
      expect(library.browseBooks([a, b]), [a, b]);
      await library.setOption('discoveryHideFavorites', false);
      await library.hideDiscoveryBook(b, true);
      expect(library.discoveryBooks([a, b]), [a]);
      await library.hideDiscoveryBook(b, false);
      await library.blockInterest('blockedAuthors', ' alice ', true);
      expect(library.discoveryBooks([a, b]), [b]);
      await library.blockInterest('blockedAuthors', 'ALICE', false);
      await library.blockInterest('blockedTags', 'fantasy', true);
      expect(library.discoveryBooks([a, b]), [b]);
      await library.blockInterest('blockedTags', 'Fantasy', false);
      await library.setMeta(b, {'status': '已读'});
      await library.setOption('discoveryHideRead', true);
      expect(library.discoveryBooks([a, b]), [a]);
    },
  );
}
