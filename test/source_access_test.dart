import 'package:flutter_test/flutter_test.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:manxia/data/library.dart';
import 'package:manxia/data/dm5_source.dart';
import 'package:manxia/data/source_hub.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final entry in {
    401: '登录',
    403: '访问限制',
    429: '频繁',
    503: '稍后重试',
  }.entries) {
    test('HTTP ${entry.key} does not imply missing copyright', () async {
      final source = Dm5Source(
        client: MockClient((_) async => http.Response('', entry.key)),
      );
      addTearDown(source.close);
      await expectLater(
        source.fetchPage('/manhua-test/'),
        throwsA(
          isA<SourceException>()
              .having(
                (e) => e.message,
                'actionable message',
                contains(entry.value),
              )
              .having((e) => e is SourceCopyrightException, 'copyright', false),
        ),
      );
    });
  }
  test('timeout remains a network failure without edition fallback', () async {
    var requests = 0;
    final source = Dm5Source(
      client: MockClient((_) async {
        requests++;
        throw TimeoutException('test');
      }),
    );
    addTearDown(source.close);
    await expectLater(
      source.fetchPage('/manhua-test/'),
      throwsA(
        isA<SourceException>().having(
          (e) => e.message,
          'network',
          contains('超时'),
        ),
      ),
    );
    expect(requests, 1);
  });
  test('custom source verification is reported before catalog parsing', () async {
    SharedPreferences.setMockInitialValues({});
    final library = Library(await SharedPreferences.getInstance());
    await library.load();
    library.sourceProfiles.add({
      'id': 'test',
      'name': '测试源',
      'baseUrl': 'https://source.example',
      'cards': '.book',
      'title': '.name',
      'link': 'a',
      'cover': 'img',
      'chapters': '.chapters a',
      'pages': '.pages img',
    });
    await library.setOption('source', 'test');
    final hub = SourceHub(
      library,
      transport: MockClient(
        (_) async => http.Response(
          '<title>Just a moment...</title><script src="/cdn-cgi/challenge-platform/a.js"></script>',
          200,
        ),
      ),
    );
    addTearDown(hub.close);
    await expectLater(
      hub.home(),
      throwsA(
        isA<SourceException>().having(
          (e) => e.message,
          'verification message',
          contains('验证'),
        ),
      ),
    );
  });
  test(
    'expired detail URLs give a distinct message without implying copyright',
    () async {
      final source = Dm5Source(
        client: MockClient((_) async => http.Response('', 404)),
      );
      addTearDown(source.close);
      await expectLater(
        source.fetchPage('/manhua-old/'),
        throwsA(
          isA<SourceException>().having(
            (e) => e.message,
            'expired entry',
            contains('入口'),
          ),
        ),
      );
    },
  );
}
