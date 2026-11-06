import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'library.dart';
import 'plugin.dart';
import 'plugin_package.dart';
import 'character_assets.dart';
import 'character_definition.dart';
import 'script_source.dart';
import 'source_profile.dart';
export 'plugin.dart';

class PluginRegistry {
  PluginRegistry(
    this.library, {
    CharacterAssets? characterAssets,
    ScriptSourceRuntime? scripts,
  }) : assets = characterAssets ?? CharacterAssets.shared,
       scripts = scripts ?? ScriptSourceRuntime();
  final Library library;
  final CharacterAssets assets;
  final ScriptSourceRuntime scripts;
  static final _operations = Expando<Future<void>>();
  Future<void> _run(Future<void> Function() action) {
    final prior = _operations[library] ?? Future<void>.value();
    final next = prior.then((_) => action());
    final quiet = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    _operations[library] = quiet;
    return next.whenComplete(() {
      if (identical(_operations[library], quiet)) _operations[library] = null;
    });
  }

  List<Map<String, dynamic>> get installed {
    final raw = library.options['plugins.installed'];
    if (raw is! List) return [];
    final result = <Map<String, dynamic>>[];
    for (final e in raw) {
      try {
        final item = Map<String, dynamic>.from(e);
        final plugin = ManxiaPlugin(
          Map<String, dynamic>.from(item['manifest']),
        );
        plugin.resolve(Map<String, dynamic>.from(item['config'] ?? {}));
        result.add(item);
      } catch (_) {}
    }
    return result;
  }

  Map<String, dynamic>? entry(String id) =>
      installed.where((e) => e['manifest']['id'] == id).firstOrNull;
  PluginSnapshot get snapshot => PluginSnapshot(library.options);
  Future<void> save(List<Map<String, dynamic>> list) =>
      library.setOption('plugins.installed', list);

  Future<void> install(ManxiaPlugin plugin) => _run(() => _install(plugin));
  Future<void> _install(
    ManxiaPlugin plugin, {
    Map<String, dynamic>? restoredConfig,
    bool enabled = true,
  }) async {
    final list = installed;
    final old = entry(plugin.id);
    if (restoredConfig == null &&
        old != null &&
        compareVersions(plugin.version, old['manifest']['version']) < 0) {
      throw const FormatException('不支持降级安装，请先卸载旧版');
    }
    if (old != null &&
        (old['manifest']['apiVersion'] == 2 || plugin.apiVersion == 2) &&
        old['manifest']['contributes']['source']?['id'] !=
            plugin.contributions['source']?['id']) {
      throw const FormatException('更新脚本源时必须保留漫画源 id');
    }
    for (final item in list) {
      if ((plugin.contributions.containsKey('theme') &&
              (item['manifest']['contributes'] as Map).containsKey('theme')) ||
          (plugin.contributions.containsKey('reader') &&
              (item['manifest']['contributes'] as Map).containsKey('reader')) ||
          (plugin.contributions.containsKey('character') &&
              (item['manifest']['contributes'] as Map).containsKey(
                'character',
              ))) {
        if (item['enabled'] == true && item['manifest']['id'] != plugin.id) {
          item['disabledBy'] = plugin.id;
        }
        item['enabled'] = false;
      }
      if (plugin.contributions['source'] is Map &&
          item['manifest']['id'] != plugin.id &&
          item['manifest']['contributes']['source']?['id'] ==
              plugin.contributions['source']['id']) {
        throw const FormatException('漫画源 id 与其他已安装插件冲突');
      }
    }
    if (plugin.contributions['source'] is Map &&
        library.sourceProfiles.any(
          (p) => p['id'] == plugin.contributions['source']['id'],
        )) {
      throw const FormatException('漫画源 id 与手动配置冲突');
    }
    list.removeWhere((e) => e['manifest']['id'] == plugin.id);
    var config =
        restoredConfig ?? Map<String, dynamic>.from(old?['config'] ?? {});
    try {
      plugin.resolve(config);
    } catch (_) {
      config = {};
    }
    final resolved = plugin.resolve(config);
    if (plugin.apiVersion == 2) {
      if (list.where((item) => item['manifest']['apiVersion'] == 2).length >=
          12) {
        throw const FormatException('最多可安装 12 个脚本漫画源');
      }
      await scripts.validate(
        SourceProfile.scripted(Map<String, dynamic>.from(resolved['source'])),
      );
    }
    if (resolved['character'] is Map) {
      final count = installed
          .where(
            (e) =>
                (e['manifest']['contributes'] as Map).containsKey('character'),
          )
          .length;
      if (count >= 10 &&
          (old?['manifest']['contributes'] as Map?)?.containsKey('character') !=
              true) {
        throw const FormatException('最多安装 10 个角色包');
      }
      await assets.prepare(
        CharacterDefinition(Map<String, dynamic>.from(resolved['character'])),
        plugin.resources,
      );
    }
    final previous =
        restoredConfig != null || plugin.apiVersion != 2 || old == null
        ? null
        : old['manifest']['apiVersion'] == 2 &&
              old['manifest']['version'] != plugin.version
        ? {'manifest': old['manifest'], 'config': old['config']}
        : old['previous'];
    list.add({
      'manifest': plugin.json,
      'enabled': enabled,
      'config': config,
      'previous': ?previous,
    });
    await save(list);
  }

  Future<void> rollback(String id) => _run(() async {
    final current = entry(id);
    final previous = current?['previous'];
    if (previous is! Map || previous['manifest'] is! Map) {
      throw const FormatException('没有可回退的脚本源版本');
    }
    final plugin = ManxiaPlugin(
      Map<String, dynamic>.from(previous['manifest']),
    );
    if (plugin.id != id || plugin.apiVersion != 2) {
      throw const FormatException('上一个脚本源版本无效');
    }
    await _install(
      plugin,
      restoredConfig: Map<String, dynamic>.from(previous['config'] ?? {}),
      enabled: current?['enabled'] == true,
    );
  });

  Future<void> enable(String id, bool enabled) => _run(() async {
    final item = entry(id);
    if (item == null) return;
    if (enabled) {
      if (item['manifest']['apiVersion'] == 2) {
        throw const FormatException('请在插件商城确认脚本域名权限后启用');
      }
      await _install(ManxiaPlugin(Map<String, dynamic>.from(item['manifest'])));
    } else {
      final list = installed;
      list.firstWhere((e) => e['manifest']['id'] == id)['enabled'] = false;
      list.firstWhere((e) => e['manifest']['id'] == id).remove('disabledBy');
      await save(list);
    }
  });

  Future<void> uninstall(String id) => _run(() async {
    final old = entry(id);
    await save(installed..removeWhere((e) => e['manifest']['id'] == id));
    if (old?['manifest']['contributes']['character'] is! Map) return;
    final removed = CharacterDefinition(
      Map<String, dynamic>.from(old!['manifest']['contributes']['character']),
    );
    final retained = <String>{};
    for (final item in installed) {
      final c = item['manifest']['contributes']['character'];
      if (c is Map) {
        retained.addAll(
          CharacterDefinition(
            Map<String, dynamic>.from(c),
          ).frames.values.map((f) => f.sha256),
        );
      }
    }
    for (final hash
        in removed.frames.values
            .map((f) => f.sha256)
            .toSet()
            .difference(retained)) {
      try {
        await assets.remove(hash);
      } catch (_) {
        /* Preferences are already safely removed. */
      }
    }
  });
  Future<void> configure(String id, String key, dynamic value) => _run(
    () async {
      final list = installed;
      final item = list.firstWhere((e) => e['manifest']['id'] == id);
      final config = Map<String, dynamic>.from(item['config'] ?? {})
        ..[key] = value;
      final resolved = ManxiaPlugin(
        Map<String, dynamic>.from(item['manifest']),
      ).resolve(config);
      if (resolved['character'] is Map) {
        await assets.prepare(
          CharacterDefinition(Map<String, dynamic>.from(resolved['character'])),
          const {},
        );
      }
      item['config'] = config;
      await save(list);
    },
  );

  static int compareVersions(String a, String b) {
    final x = a.split('.').map(int.parse).toList(),
        y = b.split('.').map(int.parse).toList();
    for (var i = 0; i < 3; i++) {
      final n = x[i].compareTo(y[i]);
      if (n != 0) return n;
    }
    return 0;
  }
}

class PluginCatalog {
  static const official =
      'https://raw.githubusercontent.com/LexianLix/manxia/main/plugins/v2/index.json';
  static Uri address(String text) {
    final uri = Uri.parse(text);
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      throw const FormatException('插件仓库和包需使用不含凭据的 HTTPS 地址');
    }
    return uri;
  }

  static Future<List<int>> download(
    String url, {
    http.Client? transport,
  }) async {
    final client = transport ?? http.Client();
    try {
      final response = await client
          .send(http.Request('GET', address(url)))
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw StateError('插件下载 HTTP ${response.statusCode}');
      }
      final bytes = <int>[];
      await response.stream
          .forEach((chunk) {
            bytes.addAll(chunk);
            if (bytes.length > 2 * 1024 * 1024) {
              throw const FormatException('插件目录或包超过 2 MB');
            }
          })
          .timeout(const Duration(seconds: 12));
      return bytes;
    } finally {
      if (transport == null) client.close();
    }
  }

  static Future<List<ManxiaPlugin>> bundled() async {
    final root =
        jsonDecode(await rootBundle.loadString('assets/plugins/catalog.json'))
            as Map;
    return (root['plugins'] as List)
        .map((e) => ManxiaPlugin(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Future<List<ManxiaPlugin>> remote(
    String url, {
    http.Client? transport,
  }) async {
    final root =
        jsonDecode(utf8.decode(await download(url, transport: transport)))
            as Map;
    if (root['schemaVersion'] != 1 ||
        root['plugins'] is! List ||
        (root['plugins'] as List).length > 20) {
      throw const FormatException('插件仓库格式无效');
    }
    final plugins = <ManxiaPlugin>[];
    for (final e in root['plugins'] as List) {
      final bytes = await download(e['url'], transport: transport);
      if (e['sha256'] != sha256.convert(bytes).toString()) {
        throw const FormatException('插件内容与 SHA-256 不一致');
      }
      final plugin = PluginPackage.decode(Uint8List.fromList(bytes));
      if (plugin.id != e['id'] || plugin.version != e['version']) {
        throw const FormatException('插件 id 或版本与目录不一致');
      }
      plugins.add(plugin);
    }
    return plugins;
  }
}
