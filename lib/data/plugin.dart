import 'dart:convert';
import 'source_profile.dart';

/// Public declarative extension contract. No downloaded Dart/JS is evaluated.
class ManxiaPlugin {
  factory ManxiaPlugin(Map<String, dynamic> input) {
    final encoded = jsonEncode(input);
    if (utf8.encode(encoded).length > 128 * 1024) {
      throw const FormatException('插件 manifest 超过 128 KB');
    }
    return ManxiaPlugin._(Map<String, dynamic>.from(jsonDecode(encoded)));
  }
  ManxiaPlugin._(this.json) {
    validate();
  }
  final Map<String, dynamic> json;
  String get id => json['id'];
  String get name => json['name'];
  String get version => json['version'];
  String get author => json['author'];
  String get description => json['description'] ?? '';
  Map<String, dynamic> get contributions =>
      Map<String, dynamic>.from(json['contributes']);
  List<Map<String, dynamic>> get settings => (json['settings'] as List? ?? [])
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
  List<String> get capabilities => contributions.keys.toList();

  void validate() {
    if (json['apiVersion'] != 1) {
      throw const FormatException('插件接口版本不兼容，需要 API 1');
    }
    if (!RegExp(
      r'^[a-z][a-z0-9_-]{0,31}\.[a-z0-9][a-z0-9_.-]{0,63}$',
    ).hasMatch(json['id']?.toString() ?? '')) {
      throw const FormatException('插件 id 必须采用 author.name 格式');
    }
    if (!RegExp(
      r'^\d+\.\d+\.\d+$',
    ).hasMatch(json['version']?.toString() ?? '')) {
      throw const FormatException('版本需为 x.y.z');
    }
    for (final key in ['name', 'author', 'license']) {
      if (json[key] is! String ||
          (json[key] as String).trim().isEmpty ||
          (json[key] as String).length > 100) {
        throw FormatException('插件 $key 无效');
      }
    }
    if (json['description'] != null &&
        (json['description'] is! String ||
            (json['description'] as String).length > 1200)) {
      throw const FormatException('插件说明过长或格式无效');
    }
    if (json['contributes'] is! Map ||
        contributions.isEmpty ||
        contributions.keys.any(
          (k) => !['theme', 'reader', 'source', 'navigation'].contains(k),
        )) {
      throw const FormatException('插件贡献类型不受支持');
    }
    final keys = <String>{};
    for (final setting in settings) {
      if (!RegExp(
            r'^[a-z][a-zA-Z0-9_]{0,39}$',
          ).hasMatch(setting['key']?.toString() ?? '') ||
          !keys.add(setting['key']) ||
          setting['label'] is! String ||
          !['boolean', 'number', 'choice', 'color'].contains(setting['type'])) {
        throw const FormatException('插件设置定义无效或重复');
      }
      if (setting['type'] == 'number' &&
          (setting['min'] is! num ||
              setting['max'] is! num ||
              setting['min'] > setting['max'])) {
        throw const FormatException('数值设置必须提供有效范围');
      }
      if (setting['type'] == 'choice' &&
          (setting['choices'] is! List ||
              (setting['choices'] as List).isEmpty ||
              (setting['choices'] as List).any((v) => v is! String))) {
        throw const FormatException('选择设置需提供字符串选项');
      }
      validateSetting(setting, setting['default']);
    }
    resolve(const {});
  }

  static void validateSetting(Map<String, dynamic> s, dynamic value) {
    final valid = switch (s['type']) {
      'boolean' => value is bool,
      'number' =>
        value is num &&
            value.isFinite &&
            value >= s['min'] &&
            value <= s['max'],
      'choice' => (s['choices'] as List).contains(value),
      'color' =>
        value is String && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value),
      _ => false,
    };
    if (!valid) throw FormatException('插件设置 ${s['key']} 的值无效');
  }

  Map<String, dynamic> resolve(Map<String, dynamic> config) {
    final definitions = {for (final s in settings) s['key'] as String: s};
    for (final key in config.keys) {
      if (!definitions.containsKey(key)) throw FormatException('未知插件设置 $key');
      validateSetting(definitions[key]!, config[key]);
    }
    dynamic value(dynamic v) {
      if (v is Map && v.length == 1 && v.containsKey('setting')) {
        final key = v['setting'];
        if (!definitions.containsKey(key)) {
          throw FormatException('未定义的插件设置 $key');
        }
        return config[key] ?? definitions[key]!['default'];
      }
      if (v is Map) return v.map((k, v) => MapEntry(k.toString(), value(v)));
      if (v is List) return v.map(value).toList();
      return v;
    }

    final result = Map<String, dynamic>.from(value(contributions));
    if (result['theme'] case final Map theme) {
      if (theme.keys.any(
        (k) => !['seed', 'lightSurface', 'darkSurface'].contains(k),
      )) {
        throw const FormatException('未知主题字段');
      }
      for (final color in theme.values) {
        if (color is! String || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(color)) {
          throw const FormatException('主题颜色必须为 #RRGGBB');
        }
      }
    } else if (result.containsKey('theme')) {
      throw const FormatException('主题定义无效');
    }
    if (result['reader'] case final Map reader) {
      const choices = {
        'mode': ['page', 'strip'],
        'background': ['ink', 'paper', 'sepia'],
        'turn': ['slide', 'paper'],
      };
      for (final e in reader.entries) {
        final valid = choices.containsKey(e.key)
            ? choices[e.key]!.contains(e.value)
            : ['rtl', 'doublePage', 'tapZones'].contains(e.key)
            ? e.value is bool
            : e.key == 'warmth'
            ? e.value is num && e.value >= 0 && e.value <= .8
            : false;
        if (!valid) throw FormatException('阅读贡献字段 ${e.key} 无效');
      }
    } else if (result.containsKey('reader')) {
      throw const FormatException('阅读预设无效');
    }
    if (result.containsKey('source')) {
      SourceProfile(Map<String, dynamic>.from(result['source']));
    }
    if (result.containsKey('navigation')) {
      final ids = result['navigation'];
      if (ids is! List ||
          ids.length < 3 ||
          ids.length > 6 ||
          ids.any((v) => v is! int || v < 0 || v > 5) ||
          ids.toSet().length != ids.length ||
          !ids.contains(0) ||
          !ids.contains(3)) {
        throw const FormatException('导航需含书架和设置，共 3–6 个不重复入口');
      }
    }
    return result;
  }
}

/// Compute effective contributions without overwriting personal preferences.
/// Disabling/removing a plugin immediately restores the underlying settings.
class PluginSnapshot {
  factory PluginSnapshot(Map<String, dynamic> options) {
    final token = options['plugins.installed'];
    final cached = _cache[options];
    if (cached != null && identical(cached.$1, token)) return cached.$2;
    final snapshot = PluginSnapshot._(token);
    _cache[options] = (token, snapshot);
    return snapshot;
  }
  static final _cache = Expando<(Object?, PluginSnapshot)>();
  PluginSnapshot._(dynamic token) {
    if (token is! List) return;
    for (final raw in token) {
      try {
        final entry = Map<String, dynamic>.from(raw);
        if (entry['enabled'] != true) continue;
        final plugin = ManxiaPlugin(
          Map<String, dynamic>.from(entry['manifest']),
        );
        final resolved = plugin.resolve(
          Map<String, dynamic>.from(entry['config'] ?? {}),
        );
        if (resolved['theme'] is Map) {
          theme = Map<String, dynamic>.from(resolved['theme']);
        }
        if (resolved['reader'] is Map) {
          reader.addAll(Map<String, dynamic>.from(resolved['reader']));
        }
        if (resolved['source'] is Map) {
          sources.add(Map<String, dynamic>.from(resolved['source']));
        }
        if (resolved['navigation'] is List) {
          navigation = List<int>.from(resolved['navigation']);
        }
      } catch (_) {
        // A malformed restored extension cannot prevent the host from starting.
      }
    }
  }
  Map<String, dynamic> theme = {}, reader = {};
  List<Map<String, dynamic>> sources = [];
  List<int>? navigation;
}
