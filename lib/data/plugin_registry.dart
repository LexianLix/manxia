import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'library.dart';
import 'plugin.dart';
export 'plugin.dart';

class PluginRegistry {
  PluginRegistry(this.library);
  final Library library;
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

  Future<void> install(ManxiaPlugin plugin) async {
    final list = installed;
    final old = entry(plugin.id);
    if (old != null &&
        compareVersions(plugin.version, old['manifest']['version']) < 0) {
      throw const FormatException('不支持降级安装，请先卸载旧版');
    }
    for (final item in list) {
      if ((plugin.contributions.containsKey('theme') &&
              (item['manifest']['contributes'] as Map).containsKey('theme')) ||
          (plugin.contributions.containsKey('reader') &&
              (item['manifest']['contributes'] as Map).containsKey('reader'))) {
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
    var config = Map<String, dynamic>.from(old?['config'] ?? {});
    try {
      plugin.resolve(config);
    } catch (_) {
      config = {};
    }
    list.add({'manifest': plugin.json, 'enabled': true, 'config': config});
    await save(list);
  }

  Future<void> enable(String id, bool enabled) async {
    final item = entry(id);
    if (item == null) return;
    if (enabled) {
      await install(ManxiaPlugin(Map<String, dynamic>.from(item['manifest'])));
    } else {
      final list = installed;
      list.firstWhere((e) => e['manifest']['id'] == id)['enabled'] = false;
      await save(list);
    }
  }

  Future<void> uninstall(String id) async =>
      save(installed..removeWhere((e) => e['manifest']['id'] == id));
  Future<void> configure(String id, String key, dynamic value) async {
    final list = installed;
    final item = list.firstWhere((e) => e['manifest']['id'] == id);
    final config = Map<String, dynamic>.from(item['config'] ?? {})
      ..[key] = value;
    ManxiaPlugin(Map<String, dynamic>.from(item['manifest'])).resolve(config);
    item['config'] = config;
    await save(list);
  }

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
      'https://raw.githubusercontent.com/LexianLix/manxia/main/plugins/index.json';
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
      final plugin = ManxiaPlugin(
        Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes))),
      );
      if (plugin.id != e['id'] || plugin.version != e['version']) {
        throw const FormatException('插件 id 或版本与目录不一致');
      }
      plugins.add(plugin);
    }
    return plugins;
  }
}
