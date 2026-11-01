import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/data/character_assets.dart';
import 'package:manxia/data/character_definition.dart';
import 'package:manxia/data/plugin_registry.dart';
import 'package:manxia/data/plugin_package.dart';
import 'package:manxia/platform/blob_store.dart';
import 'features_test.dart' as fixtures;

Future<ManxiaPlugin> character(String id) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const ui.Color(0xff716189), ui.BlendMode.src);
  final picture = recorder.endRecording(), image = await picture.toImage(8, 12);
  final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  image.dispose();
  picture.dispose();
  return ManxiaPlugin(
    {
      'apiVersion': 1,
      'id': id,
      'name': '测试角色',
      'version': '1.0.0',
      'author': 'Test',
      'license': 'MIT',
      'contributes': {
        'character': {
          'states': {
            'idle': {
              'file': 'idle.png',
              'sha256': sha256.convert(bytes).toString(),
            },
          },
        },
      },
    },
    resources: {'idle.png': bytes},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'role images roundtrip outside preferences and removing shared assets is safe',
    () async {
      final library = await fixtures.library(), store = MemoryBlobStore();
      final assets = CharacterAssets(store: store, bundled: {}),
          registry = PluginRegistry(library, characterAssets: assets);
      final first = await character('test.first'),
          second = await character('test.second');
      await registry.install(first);
      await registry.install(second);
      expect(registry.entry(first.id)!['enabled'], false);
      expect(registry.entry(first.id)!['disabledBy'], second.id);
      expect(registry.snapshot.origins['character']!.id, second.id);
      expect(library.prefs.getString('features.v2')!.length, lessThan(8192));
      final exported = await PluginPackage.encode(second, assets);
      final imported = PluginPackage.decode(exported);
      expect(imported.id, second.id);
      expect(imported.resources['idle.png'], second.resources['idle.png']);
      await registry.uninstall(first.id);
      expect(store.data, isNotEmpty);
      await registry.uninstall(second.id);
      expect(store.data, isEmpty);
      expect(registry.snapshot.character, isNull);
      library.dispose();
    },
  );
  test(
    'a corrupt replacement never disables the installed character or changes its preferences',
    () async {
      final library = await fixtures.library(),
          assets = CharacterAssets(store: MemoryBlobStore(), bundled: {});
      final registry = PluginRegistry(library, characterAssets: assets),
          original = await character('test.original');
      await registry.install(original);
      final broken = ManxiaPlugin(
        {...original.json, 'id': 'test.bad'},
        resources: {
          'idle.png': Uint8List.fromList([1, 2, 3]),
        },
      );
      final before = library.prefs.getString('features.v2');
      await expectLater(registry.install(broken), throwsFormatException);
      expect(library.prefs.getString('features.v2'), before);
      expect(registry.snapshot.origins['character']!.id, original.id);
      library.dispose();
    },
  );
  test(
    'character ZIPs reject traversal and undeclared files before installation',
    () async {
      final original = await character('test.safe');
      final archive = Archive();
      final json = utf8.encode(jsonEncode(original.json));
      archive.addFile(ArchiveFile('manifest.json', json.length, json));
      archive.addFile(ArchiveFile('../idle.png', 3, [1, 2, 3]));
      expect(
        () => PluginPackage.decode(
          Uint8List.fromList(ZipEncoder().encode(archive)),
        ),
        throwsFormatException,
      );
      expect(
        () => ManxiaPlugin({
          ...original.json,
          'contributes': {
            'character': {
              'states': {
                'idle': {'file': '../secret.png', 'sha256': '0' * 64},
              },
            },
          },
        }),
        throwsFormatException,
      );
    },
  );
  test('the SDK-generated official ZIP decodes in the Flutter host', () async {
    final role = PluginPackage.decode(
      await File('plugins/packages/xiaxia.zip').readAsBytes(),
    );
    final assets = CharacterAssets.shared;
    await assets.prepare(
      CharacterDefinition(
        Map<String, dynamic>.from(role.contributions['character']),
      ),
      role.resources,
    );
    final encoded = await PluginPackage.encode(role, assets);
    expect(PluginPackage.decode(encoded).id, role.id);
  });
  test(
    'an install waiting for image IO cannot overwrite another queued plugin install',
    () async {
      final library = await fixtures.library(), store = _WaitingStore();
      final registry = PluginRegistry(
        library,
        characterAssets: CharacterAssets(store: store, bundled: {}),
      );
      final role = await character('test.queued');
      final first = registry.install(role);
      await store.started.future;
      final second = registry.install(
        ManxiaPlugin({
          'apiVersion': 1,
          'id': 'test.theme',
          'name': 'Theme',
          'author': 'Test',
          'version': '1.0.0',
          'license': 'MIT',
          'contributes': {
            'theme': {'seed': '#345678'},
          },
        }),
      );
      store.release.complete();
      await Future.wait([first, second]);
      expect(registry.installed.map((e) => e['manifest']['id']).toSet(), {
        role.id,
        'test.theme',
      });
      expect(registry.snapshot.character, isNotNull);
      library.dispose();
    },
  );
}

class _WaitingStore extends MemoryBlobStore {
  final started = Completer<void>(), release = Completer<void>();
  @override
  Future<void> write(String key, Uint8List bytes) async {
    if (!started.isCompleted) started.complete();
    await release.future;
    await super.write(key, bytes);
  }
}
