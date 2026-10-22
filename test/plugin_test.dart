import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:manxia/data/library.dart';
import 'package:manxia/data/plugin_registry.dart';
import 'package:manxia/data/source_hub.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Library library;
  late PluginRegistry registry;
  late List<ManxiaPlugin> plugins;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    library = Library(await SharedPreferences.getInstance());
    await library.load();
    registry = PluginRegistry(library);
    plugins = await PluginCatalog.bundled();
  });

  test(
    'bundled catalog and published index describe exactly the same bytes',
    () async {
      final index =
          jsonDecode(await File('plugins/index.json').readAsString()) as Map;
      expect(plugins, hasLength(5));
      for (final item in index['plugins']) {
        final name = Uri.parse(item['url']).pathSegments.last;
        final bytes = await File('plugins/packages/$name').readAsBytes();
        expect(sha256.convert(bytes).toString(), item['sha256']);
        expect(
          ManxiaPlugin(
            Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes))),
          ).id,
          item['id'],
        );
      }
    },
  );

  test(
    'theme install, configuration, mutual exclusion and removal preserve preferences',
    () async {
      await library.setOption('personal', 'kept');
      final warm = plugins.firstWhere((p) => p.id == 'manxia.warm-paper');
      await registry.install(warm);
      expect(registry.snapshot.theme['seed'], '#826246');
      await registry.configure(warm.id, 'accent', '#345678');
      expect(registry.snapshot.theme['seed'], '#345678');
      await registry.enable(warm.id, false);
      expect(registry.snapshot.theme, isEmpty);
      await registry.enable(warm.id, true);
      expect(registry.snapshot.theme['seed'], '#345678');
      await registry.install(
        plugins.firstWhere((p) => p.id == 'manxia.blue-hour'),
      );
      expect(registry.entry(warm.id)!['enabled'], false);
      await registry.uninstall('manxia.blue-hour');
      expect(registry.snapshot.theme, isEmpty);
      expect(library.option<String>('personal', ''), 'kept');
      final restored = Library(await SharedPreferences.getInstance());
      await restored.load();
      expect(
        PluginRegistry(restored).entry(warm.id)!['config']['accent'],
        '#345678',
      );
      expect(() => warm.resolve({'accent': 'broken'}), throwsFormatException);
    },
  );

  test(
    'reader defaults apply without replacing per-book preferences or books',
    () async {
      final comic = library.samples.first;
      await library.setOption('readerDefaults', {'background': 'sepia'});
      await registry.install(
        plugins.firstWhere((p) => p.id == 'manxia.manga-reader'),
      );
      expect(library.readerOptions(comic)['rtl'], true);
      expect(library.readerOptions(comic)['turn'], 'paper');
      library.metadata[comic.path] = {
        'reader': {'rtl': false, 'mode': 'strip'},
      };
      expect(library.readerOptions(comic)['rtl'], false);
      await registry.uninstall('manxia.manga-reader');
      expect(library.readerOptions(comic)['background'], 'sepia');
      expect(library.samples, hasLength(7));
    },
  );

  test(
    'source plugin serves the real parser and is unavailable when disabled',
    () async {
      final p = ManxiaPlugin(
        Map<String, dynamic>.from(
          jsonDecode(
            await File('plugins/examples/source-template.json').readAsString(),
          ),
        ),
      );
      await registry.install(p);
      await library.setOption('source', 'your-static-library');
      final source = SourceHub(
        library,
        transport: MockClient(
          (request) async => http.Response(
            '<div class="comic"><a href="/book"><span class="title">My comic</span><img src="/cover.jpg"></a></div>',
            200,
          ),
        ),
      );
      expect(source.selected!.id, 'your-static-library');
      expect((await source.home()).single.title, 'My comic');
      await registry.enable(p.id, false);
      expect(source.selected, isNull);
      source.close();
    },
  );

  test(
    'invalid restored plugin state never breaks startup or effective settings',
    () {
      expect(PluginSnapshot({'plugins.installed': 'broken'}).reader, isEmpty);
      expect(
        PluginSnapshot({
          'plugins.installed': [
            {
              'enabled': true,
              'manifest': {'apiVersion': 99},
            },
          ],
        }).theme,
        isEmpty,
      );
      expect(
        () => ManxiaPlugin({...plugins.first.json, 'apiVersion': 9}),
        throwsFormatException,
      );
      expect(
        () => ManxiaPlugin({
          ...plugins.first.json,
          'contributes': {'execute': 'arbitrary code'},
        }),
        throwsFormatException,
      );
    },
  );

  test(
    'remote packages are rejected on hash mismatch before installation',
    () async {
      final bytes = utf8.encode(jsonEncode(plugins.first.json));
      final index = {
        'schemaVersion': 1,
        'plugins': [
          {
            'id': plugins.first.id,
            'version': plugins.first.version,
            'url': 'https://plugins.example/package.json',
            'sha256': '0' * 64,
          },
        ],
      };
      final transport = MockClient(
        (request) async => http.Response.bytes(
          request.url.path.endsWith('index.json')
              ? utf8.encode(jsonEncode(index))
              : bytes,
          200,
        ),
      );
      await expectLater(
        PluginCatalog.remote(
          'https://plugins.example/index.json',
          transport: transport,
        ),
        throwsFormatException,
      );
      expect(registry.installed, isEmpty);
      index['plugins'] = [
        {
          'id': plugins.first.id,
          'version': plugins.first.version,
          'url': 'https://plugins.example/package.json',
          'sha256': sha256.convert(bytes).toString(),
        },
      ];
      final fetched = await PluginCatalog.remote(
        'https://plugins.example/index.json',
        transport: transport,
      );
      await registry.install(fetched.single);
      expect(
        registry.snapshot.theme['seed'],
        plugins.first.resolve({})['theme']['seed'],
      );
      transport.close();
    },
  );
}
