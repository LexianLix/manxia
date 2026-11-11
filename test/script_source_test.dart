import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/data/library.dart';
import 'package:manxia/data/plugin_package.dart';
import 'package:manxia/data/plugin_registry.dart';
import 'package:manxia/data/script_source.dart';
import 'package:manxia/data/script_source_policy.dart';
import 'package:manxia/data/source_hub.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Library library;
  late Map<String, dynamic> manifest;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    library = Library(await SharedPreferences.getInstance());
    await library.load();
    manifest = jsonDecode(
      File('plugins/packages/manxia.script-demo.json').readAsStringSync(),
    );
  });

  test(
    'paginated script catalogs keep the source identity across selection changes',
    () async {
      final runtime = ScriptSourceRuntime(
        evaluate: (code) async {
          if (code.contains('every(key =>')) return 'true';
          return jsonEncode({
            'result': [
              {
                'path': code.contains('"page":2') ? '/comic/2/' : '/comic/1/',
                'title': 'Page',
              },
            ],
          });
        },
      );
      final registry = PluginRegistry(library, scripts: runtime);
      final plugin = PluginPackage.decode(
        File('plugins/packages/manxia.source-manhuagui.json').readAsBytesSync(),
      );
      await registry.install(plugin);
      await library.setOption('source', 'manhuagui');
      final hub = SourceHub(library, scripts: runtime);
      addTearDown(hub.close);
      expect((await hub.categories()).values, ['/']);
      final first = await hub.catalog('/');
      expect(first.canPaginate, true);
      expect(first.books.single.sourceId, 'manhuagui');
      await library.setOption('source', 'dm5');
      final next = await hub.catalogNext(first.parameters, 2);
      expect(next.single.sourceId, 'manhuagui');
      expect(next.single.path, contains('2%2F'));
      await registry.enable(plugin.id, false);
      await expectLater(hub.catalogNext(first.parameters, 3), throwsException);
    },
  );
  test(
    'enabled script source reaches the normal catalog, detail and reader paths',
    () async {
      final body = File('assets/characters/index.json').readAsStringSync();
      const book = {
        'title': '漫匣试读',
        'path': 'assets/characters/index.json?book=xiaxia',
      };
      const chapter = {
        'title': '第1话',
        'path': 'assets/characters/index.json?chapter=1',
      };
      final requests = <Uri>[];
      final runtime = ScriptSourceRuntime(
        evaluate: (code) async {
          if (code.contains('every(key =>')) return 'true';
          if (code.contains('"responses":[]')) {
            return '{"request":"assets/characters/index.json"}';
          }
          final result = code.contains('return stringify(api.detail(')
              ? {
                  'chapters': [chapter],
                }
              : code.contains('return stringify(api.pages(')
              ? [
                  'idle',
                  'blink',
                  'happy',
                ].map((name) => 'assets/characters/xiaxia/$name.png').toList()
              : [book];
          return jsonEncode({'result': result});
        },
        fetch: (url, {required maxBytes, abort}) async {
          requests.add(url);
          return Uint8List.fromList(utf8.encode(body));
        },
      );
      final registry = PluginRegistry(library, scripts: runtime);
      final plugin = PluginPackage.decode(
        File('plugins/packages/manxia.script-demo.json').readAsBytesSync(),
      );
      await registry.install(plugin);
      await library.setOption('source', 'xiaxia-demo');
      final hub = SourceHub(library, scripts: runtime);
      addTearDown(hub.close);
      final result = (await hub.search('Manxia Demo')).single;
      expect(result.sourceId, 'xiaxia-demo');
      expect(result.path, startsWith('custom:xiaxia-demo:'));
      final detail = await hub.detail(result);
      final pages = await hub.pages(detail.chapters.single.path);
      expect(decodeScriptImage(pages.first).host, 'raw.githubusercontent.com');
      expect(pages.length, 3);
      expect(requests.length, 3);
      expect(
        requests.every(
          (url) => url.path.endsWith('/assets/characters/index.json'),
        ),
        true,
      );
      await registry.enable(plugin.id, false);
      await expectLater(
        hub.searchIn('xiaxia-demo', 'Manxia Demo'),
        throwsException,
      );
    },
  );

  test(
    'restoring portable preferences requires fresh script permission approval',
    () async {
      final registry = PluginRegistry(
        library,
        scripts: ScriptSourceRuntime(evaluate: (_) async => 'true'),
      );
      final first = ManxiaPlugin(manifest);
      await registry.install(first);
      await registry.install(ManxiaPlugin({...manifest, 'version': '1.1.0'}));
      final backup = library.backup();
      await library.restore(backup, restoreOptions: true);
      expect(registry.snapshot.sources, isEmpty);
      expect(registry.entry(first.id)!['enabled'], false);
      expect(registry.entry(first.id)!['previous'], isNull);
    },
  );

  test(
    'unapproved request and image addresses never reach the network',
    () async {
      final source = SourceProfile.scripted(
        Map<String, dynamic>.from(manifest['contributes']['source']),
      );
      final runtime = ScriptSourceRuntime(
        evaluate: (_) async => '{"request":"https://elsewhere.example/book"}',
        fetch: (_, {required maxBytes, abort}) async =>
            throw StateError('Unexpected network call'),
      );
      await expectLater(
        runtime.catalog(source, query: 'trial'),
        throwsA(
          isA<ScriptSourceFailure>()
              .having(
                (error) => error.kind,
                'kind',
                ScriptFailureKind.permission,
              )
              .having((error) => error.message, 'message', contains('域名未获许可')),
        ),
      );
      final pictures = ScriptSourceRuntime(
        evaluate: (_) async =>
            '{"result":["https://elsewhere.example/page.png"]}',
      );
      await expectLater(
        pictures.pages(source, source.encode(source.base)),
        throwsA(
          isA<ScriptSourceFailure>().having(
            (error) => error.kind,
            'kind',
            ScriptFailureKind.permission,
          ),
        ),
      );
      expect(
        () => checkedScriptUrl(Uri.parse('https://127.0.0.1/')),
        throwsFormatException,
      );
    },
  );

  test(
    'failed install preserves the active source and a validated previous version can roll back',
    () async {
      var valid = true;
      final registry = PluginRegistry(
        library,
        scripts: ScriptSourceRuntime(
          evaluate: (_) async => valid ? 'true' : 'false',
        ),
      );
      final first = ManxiaPlugin(manifest);
      await registry.install(first);
      valid = false;
      final next = ManxiaPlugin({...manifest, 'version': '1.1.0'});
      await expectLater(registry.install(next), throwsException);
      expect(registry.entry(first.id)!['manifest']['version'], '1.0.0');
      valid = true;
      await registry.install(next);
      await registry.rollback(first.id);
      expect(registry.entry(first.id)!['manifest']['version'], '1.0.0');
      expect(registry.entry(first.id)!['previous'], isNull);
    },
  );
}
