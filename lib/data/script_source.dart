import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import '../platform/script_source_http.dart';
import 'comic.dart';
import 'dm5_source.dart';
import 'script_source_policy.dart';
import 'source_profile.dart';

enum ScriptFailureKind { permission, request, parse, execution, empty }

class ScriptSourceFailure extends SourceException {
  ScriptSourceFailure(this.kind, super.message);
  final ScriptFailureKind kind;
}

class ScriptSourceRuntime {
  ScriptSourceRuntime({
    this.evaluate = evaluateOnAndroid,
    this.fetch = fetchScriptResource,
  });

  static const _channel = MethodChannel('io.manxia/source-script');
  final Future<String> Function(String code) evaluate;
  final Future<Uint8List> Function(
    Uri url, {
    required int maxBytes,
    Future<void>? abort,
  })
  fetch;
  final _closed = Completer<void>();
  Future<void> get closed => _closed.future;

  static Future<String> evaluateOnAndroid(String code) async {
    try {
      final value = await _channel.invokeMethod<String>('evaluate', code);
      if (value == null) throw SourceException('脚本未返回结果');
      return value;
    } on MissingPluginException {
      throw SourceException('脚本漫画源需要支持隔离执行的 Android WebView');
    } on PlatformException catch (error) {
      throw SourceException(error.message ?? '脚本执行失败');
    }
  }

  void close() {
    if (!_closed.isCompleted) _closed.complete();
  }

  String _program(SourceProfile source, String expression) =>
      '''
(() => {
  const stringify = JSON.stringify;
  const api = (${source.script}
  );
  return stringify($expression);
})()
''';

  Future<void> validate(SourceProfile source) async {
    final result = await evaluate(
      _program(source, '''
      api != null && ['search','detail','pages'].every(key => typeof api[key] === 'function')
        && (api.discover === undefined || typeof api.discover === 'function')
    '''),
    );
    if (result != 'true') {
      throw SourceException('脚本必须提供 search、detail 和 pages 函数');
    }
  }

  Future<Object?> _call(
    SourceProfile source,
    String hook,
    Map<String, Object?> args,
  ) async {
    final responses = <String>[];
    final watch = Stopwatch()..start();
    const budget = Duration(seconds: 15);
    var phase = ScriptFailureKind.execution;
    try {
      for (var step = 0; step <= 3; step++) {
        if (_closed.isCompleted) throw SourceException('书源请求已取消');
        final input = jsonEncode({
          'baseUrl': source.base.toString(),
          ...args,
          'responses': responses,
        });
        final expression = hook == 'discover'
            ? '(api.discover ?? api.search).call(api, $input)'
            : 'api.$hook($input)';
        final remaining = budget - watch.elapsed;
        phase = ScriptFailureKind.execution;
        if (remaining <= Duration.zero) throw TimeoutException('script source');
        final raw = await evaluate(
          _program(source, expression),
        ).timeout(remaining);
        if (_closed.isCompleted) throw SourceException('书源请求已取消');
        phase = ScriptFailureKind.parse;
        final value = jsonDecode(raw);
        if (value is Map && value.length == 1 && value.containsKey('result')) {
          return value['result'];
        }
        if (value is! Map || value.length != 1 || value['request'] is! String) {
          throw const FormatException('脚本需返回 {request: 地址} 或 {result: 数据}');
        }
        if (step == 3) throw const FormatException('每项操作最多请求 3 次');
        phase = ScriptFailureKind.permission;
        final url = checkedScriptUrl(
          source.base.resolve(value['request'] as String),
        );
        if (!source.requestHosts.contains(url.host)) {
          throw FormatException('脚本请求的域名未获许可：${url.host}');
        }
        phase = ScriptFailureKind.request;
        final requestTime = budget - watch.elapsed;
        if (requestTime <= Duration.zero) {
          throw TimeoutException('script source');
        }
        final abort = Completer<void>();
        try {
          final data = await fetch(
            url,
            maxBytes: 256 * 1024,
            abort: Future.any([abort.future, _closed.future]),
          ).timeout(requestTime);
          responses.add(utf8.decode(data, allowMalformed: true));
        } finally {
          abort.complete();
        }
      }
    } on TimeoutException {
      throw ScriptSourceFailure(phase, '${source.name} 的 $hook 超时');
    } on FormatException catch (error) {
      throw ScriptSourceFailure(
        phase,
        '${source.name} 的 $hook：${error.message}',
      );
    } on SourceException catch (error) {
      throw ScriptSourceFailure(phase, error.message);
    } catch (_) {
      final message = phase == ScriptFailureKind.request ? '请求失败' : '执行失败';
      throw ScriptSourceFailure(phase, '${source.name} 的 $hook $message');
    }
    throw SourceException('${source.name} 的 $hook 没有结果');
  }

  String _path(SourceProfile source, Object? raw) {
    final uri = checkedScriptUrl(
      source.url(_text(raw, required: true, limit: 2048)),
    );
    return source.encode(uri);
  }

  String _image(SourceProfile source, Object? raw) {
    final address = _text(raw, required: true, limit: 2048);
    final url = source.base.resolve(address);
    try {
      checkedScriptUrl(url);
    } on FormatException catch (error) {
      throw ScriptSourceFailure(ScriptFailureKind.permission, error.message);
    }
    if (!source.imageHosts.contains(url.host)) {
      throw ScriptSourceFailure(
        ScriptFailureKind.permission,
        '图片域名未获许可：${url.host}',
      );
    }
    Dm5Source.imageOrigins[url.host] = source.base.toString();
    return '$scriptImagePrefix${Uri.encodeComponent(url.toString())}';
  }

  String _text(Object? raw, {bool required = false, int limit = 400}) {
    if (raw == null && !required) return '';
    if (raw is! String ||
        raw.length > limit ||
        (required && raw.trim().isEmpty)) {
      throw SourceException('脚本返回了无效的文本或链接');
    }
    return raw.trim();
  }

  List _items(Object? raw, int max) {
    if (raw is! List || raw.length > max) throw SourceException('脚本返回的列表无效或过长');
    return raw;
  }

  Future<List<Comic>> catalog(
    SourceProfile source, {
    String? query,
    int page = 1,
  }) async {
    final raw = await _call(source, query == null ? 'discover' : 'search', {
      'query': query ?? '',
      'page': page,
    });
    final books = <String, Comic>{};
    for (final row in _items(raw, 100)) {
      if (row is! Map) throw SourceException('脚本返回的作品格式无效');
      final path = _path(source, row['path']);
      books[path] = Comic(
        path: path,
        sourceId: source.id,
        title: _text(row['title'], required: true),
        author: _text(row['author']),
        latest: _text(row['latest']),
        cover: row['cover'] == null || row['cover'] == ''
            ? ''
            : _image(source, row['cover']),
      );
    }
    return books.values.toList();
  }

  Future<ComicDetail> detail(SourceProfile source, Comic comic) async {
    final raw = await _call(source, 'detail', {
      'url': source.decode(comic.path).toString(),
    });
    if (raw is! Map) throw SourceException('脚本返回的详情格式无效');
    final chapters = <String, Chapter>{};
    for (final row in _items(raw['chapters'], 2000)) {
      if (row is! Map) throw SourceException('脚本返回的章节格式无效');
      final path = _path(source, row['path']);
      chapters[path] = Chapter(
        path,
        _text(row['title'], required: true),
        group: _text(row['group'] ?? '连载'),
      );
    }
    if (chapters.isEmpty) {
      throw ScriptSourceFailure(ScriptFailureKind.empty, '脚本未返回可阅读的章节');
    }
    return ComicDetail(
      Comic(
        path: comic.path,
        sourceId: source.id,
        title: comic.title,
        cover: comic.cover,
        author: comic.author,
        latest: comic.latest,
        tags: comic.tags,
        description: _text(
          raw['description'] ?? comic.description,
          limit: 5000,
        ),
      ),
      chapters.values.toList(),
    );
  }

  Future<List<String>> pages(SourceProfile source, String path) async {
    final raw = await _call(source, 'pages', {
      'url': source.decode(path).toString(),
    });
    final pages = _items(raw, 500).map((row) => _image(source, row)).toList();
    if (pages.isEmpty) {
      throw ScriptSourceFailure(ScriptFailureKind.empty, '脚本未返回章节图片');
    }
    return pages;
  }
}
