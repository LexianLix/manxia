import 'dart:convert';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'comic.dart';
import 'dm5_source.dart';
import '../platform/source_parse.dart';

/// Trusted, compiled adapters. They use the platform network stack and never
/// run a site's JavaScript or require the optional script-plugin sandbox.
class BuiltinSource {
  BuiltinSource(this.id, this.client, {this.gateway});
  final String id;
  final http.Client client;
  final Uri? gateway;
  static const names = {'mangabz': 'Mangabz', 'dongman': '咚漫漫画'};
  static const origins = {
    'mangabz': 'https://www.mangabz.com',
    'dongman': 'https://www.dongmanmanhua.cn',
  };
  String get origin => origins[id]!;
  String get name => names[id]!;
  bool get paginated => true;
  final _cache = <String, (DateTime, String)>{};
  final _pending = <String, Future<String>>{};
  final _pageLists = <String, (DateTime, List<String>)>{};
  final _pageTasks = <String, Future<List<String>>>{};
  final _catalogs = <String, (DateTime, List<Comic>)>{};
  final _catalogTasks = <String, Future<List<Comic>>>{};

  Future<http.Response> _get(Uri target, Map<String, String>? headers) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await client.get(target, headers: headers);
      } catch (_) {
        if (attempt == 1) throw SourceException('$name 连接中断，请检查网络后重试。');
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
    throw StateError('Unreachable');
  }

  static String encode(String id, String path) =>
      'builtin:$id:${Uri.encodeComponent(path)}';
  static String? sourceId(String path) =>
      path.startsWith('builtin:') ? path.split(':').elementAtOrNull(1) : null;
  Uri decode(String key) {
    if (sourceId(key) != id) throw SourceException('漫画源与作品地址不一致。');
    return checked(Uri.decodeComponent(key.substring('builtin:$id:'.length)));
  }

  Uri checked(String path) {
    final uri = Uri.parse(origin).resolve(path);
    if (uri.origin != origin || uri.userInfo.isNotEmpty || uri.hasFragment) {
      throw SourceException('漫画源返回了不支持的地址。');
    }
    return uri;
  }

  Future<String> fetch(String path) async {
    final uri = checked(path);
    final key = uri.toString();
    final cached = _cache[key];
    if (cached != null &&
        DateTime.now().difference(cached.$1) < const Duration(seconds: 60)) {
      return cached.$2;
    }
    if (_pending[key] case final task?) return task;
    final target =
        gateway
            ?.resolve('/api/builtin')
            .replace(queryParameters: {'id': id, 'path': _relative(uri)}) ??
        uri;
    final task = Dm5Source.requestText(
      () => _get(
        target,
        gateway == null
            ? {
                'User-Agent':
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/130.0 Safari/537.36',
                'Referer': '$origin/',
              }
            : null,
      ),
      sourceName: name,
    );
    _pending[key] = task;
    try {
      final body = await task;
      if (body.length <= 2 * 1024 * 1024) {
        _cache[key] = (DateTime.now(), body);
        while (_cache.length > 16 ||
            _cache.values.fold(0, (sum, entry) => sum + entry.$2.length) >
                4 * 1024 * 1024) {
          _cache.remove(_cache.keys.first);
        }
      }
      return body;
    } finally {
      _pending.remove(key);
    }
  }

  String get catalogPath =>
      id == 'mangabz' ? '/manga-list-p1/' : '/dailySchedule';
  Future<List<Comic>> catalog({int page = 1, String? query}) async {
    if (page < 1 || page > 1000) throw SourceException('漫画列表页码无效。');
    final path = query == null
        ? (id == 'mangabz' ? '/manga-list-p$page/' : catalogPath)
        : '${id == 'mangabz' ? '/search?title=' : '/search?keyword='}${Uri.encodeComponent(query.trim())}&page=$page';
    final cached = _catalogs[path];
    late final List<Comic> books;
    if (cached != null &&
        DateTime.now().difference(cached.$1) < const Duration(seconds: 60)) {
      books = cached.$2;
    } else {
      final task = _catalogTasks[path] ??= () async {
        final result = await runSourceParse(parseBuiltinCatalogData, (
          id,
          await fetch(path),
          query != null,
          page > 1,
        ));
        for (final book in result) {
          if (book.cover.isNotEmpty) image(book.cover);
        }
        _catalogs[path] = (DateTime.now(), List<Comic>.unmodifiable(result));
        if (_catalogs.length > 8) _catalogs.remove(_catalogs.keys.first);
        return result;
      }();
      try {
        books = await task;
      } finally {
        _catalogTasks.remove(path);
      }
    }
    // Dongman's public schedule is one large HTML document. Retain the parsed
    // catalog once and expose small pages rather than mounting 1,000+ entries.
    return id == 'dongman' && query == null
        ? books.skip((page - 1) * 24).take(24).toList()
        : books;
  }

  String _text(Element? e) =>
      e?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
  String image(String value) {
    if (value.isEmpty) return '';
    final uri = Uri.parse(origin).resolve(value);
    final allowed = id == 'mangabz'
        ? uri.host.endsWith('.mangabz.com')
        : uri.host.endsWith('.dongmanmanhua.cn');
    if (uri.scheme != 'https' ||
        !allowed ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort) {
      throw SourceException('$name 返回了不支持的图片地址。');
    }
    Dm5Source.imageOrigins[uri.host] = '$origin/';
    return uri.toString();
  }

  List<Comic> parseCatalog(
    String body, {
    bool search = false,
    bool allowEmpty = false,
  }) {
    final doc = html.parse(body);
    final result = <String, Comic>{};
    final entries = id == 'mangabz'
        ? doc.querySelectorAll('.mh-item')
        : doc.querySelectorAll(
            '.daily_section li a, .daily_lst li a, a.card_item',
          );
    for (final e in entries) {
      final a = id == 'mangabz' ? e.querySelector('h2 a[href]') : e;
      if (a == null) continue;
      final uri = checked(a.attributes['href'] ?? '');
      if (id == 'mangabz' && !RegExp(r'^/\d+bz/$').hasMatch(uri.path)) continue;
      if (id == 'dongman' &&
          !uri.queryParameters.containsKey('title_no') &&
          !uri.queryParameters.containsKey('titleNo')) {
        continue;
      }
      final title = id == 'mangabz'
          ? _text(a)
          : _text(e.querySelector('.subj'));
      if (title.isEmpty) continue;
      final relative = id == 'dongman'
          ? '/episodeList?titleNo=${uri.queryParameters['title_no'] ?? uri.queryParameters['titleNo']}'
          : _relative(uri);
      final path = encode(id, relative);
      result.putIfAbsent(
        path,
        () => Comic(
          path: path,
          title: title,
          sourceId: id,
          cover: image(e.querySelector('img')?.attributes['src'] ?? ''),
          author: _text(e.querySelector('.author')),
          latest: _text(e.querySelector('.chapter a')),
          tags: [
            _text(e.querySelector('.genre')),
          ].where((s) => s.isNotEmpty).toList(),
        ),
      );
    }
    // An empty search is valid only on an actual search page, never a loading
    // shell, login gate or an upstream layout we no longer recognise.
    if (result.isEmpty &&
        !((search || allowEmpty) &&
            (id == 'mangabz'
                ? doc.querySelector('.mh-list, .search-main, .search-title') !=
                      null
                : doc.querySelector('.card_wrap.search') != null))) {
      throw SourceException('$name 未返回漫画列表，请重试或打开原站检查。');
    }
    return result.values.toList();
  }

  String _relative(Uri uri) => uri.path + (uri.hasQuery ? '?${uri.query}' : '');

  Future<ComicDetail> detail(Comic book) async {
    final uri = decode(book.path);
    final doc = html.parse(await fetch(_relative(uri)));
    final chapters = <String, Chapter>{};
    void addChapters(Document page) {
      final anchors = page.querySelectorAll(
        id == 'mangabz'
            ? '.detail-list-form-con a[href]'
            : '#_listUl li a[href]',
      );
      for (final a in anchors) {
        final target = checked(a.attributes['href']!);
        if (id == 'mangabz' && !RegExp(r'^/m\d+/$').hasMatch(target.path)) {
          continue;
        }
        if (id == 'dongman' &&
            !target.queryParameters.containsKey('episode_no')) {
          continue;
        }
        final path = encode(id, _relative(target));
        chapters.putIfAbsent(
          path,
          () => Chapter(
            path,
            _text(id == 'mangabz' ? a : a.querySelector('.subj')),
            group: id == 'dongman' ? '公开章节' : '连载',
          ),
        );
      }
    }

    addChapters(doc);
    if (id == 'dongman') {
      final pending = <Uri>[];
      final seen = <int>{1};
      final titleId =
          uri.queryParameters['title_no'] ?? uri.queryParameters['titleNo'];
      void enqueue(Document page) {
        for (final a in page.querySelectorAll('.paginate a[href]')) {
          if ((a.attributes['href'] ?? '').startsWith('#')) continue;
          final target = checked(a.attributes['href']!);
          if ((target.queryParameters['title_no'] ??
                  target.queryParameters['titleNo']) !=
              titleId) {
            continue;
          }
          final n = int.tryParse(target.queryParameters['page'] ?? '');
          if (n != null && n > 1 && seen.add(n)) {
            if (seen.length > 100 || n > 100) {
              throw SourceException('$name 的目录过长，请打开原站查看。');
            }
            pending.add(target);
          }
        }
      }

      enqueue(doc);
      while (pending.isNotEmpty) {
        final batch = pending.take(3).toList();
        pending.removeRange(0, batch.length);
        final docs = await Future.wait([
          for (final target in batch) fetch(_relative(target)).then(html.parse),
        ]);
        for (final page in docs) {
          addChapters(page);
          enqueue(page);
        }
      }
    }
    if (chapters.isEmpty) {
      final notice = _text(
        doc.querySelector('.warning-bar, .notice, .error_msg'),
      );
      if (RegExp(r'版权|版權').hasMatch(notice) &&
          RegExp(r'下架|刪除|删除|移除|無|无').hasMatch(notice)) {
        throw SourceCopyrightException(notice, comic: book);
      }
      throw SourceException('$name 没有返回公开章节。可能需要原站登录、购买，或页面暂时不可用。');
    }
    final info = id == 'mangabz'
        ? doc.querySelector('.detail-info')
        : doc.querySelector('.detail_header .info');
    final title = _text(
      id == 'mangabz'
          ? doc.querySelector('.detail-info-title')
          : info?.querySelector('.subj'),
    );
    final cover = id == 'mangabz'
        ? doc.querySelector('img.detail-info-cover')?.attributes['src']
        : null;
    final result = chapters.values.toList();
    if (id == 'dongman') {
      result.sort(
        (a, b) => int.parse(
          decode(b.path).queryParameters['episode_no']!,
        ).compareTo(int.parse(decode(a.path).queryParameters['episode_no']!)),
      );
    }
    return ComicDetail(
      Comic(
        path: book.path,
        title: title.isEmpty ? book.title : title,
        cover: cover == null ? book.cover : image(cover),
        sourceId: id,
        author: _text(
          id == 'mangabz'
              ? info?.querySelector('.detail-info-tip a')
              : info?.querySelector('.author, .author_area'),
        ),
        description: _text(
          doc.querySelector(
            id == 'mangabz' ? '.detail-info-content' : '#_asideDetail .summary',
          ),
        ),
        latest: book.latest,
        tags: book.tags,
      ),
      result,
    );
  }

  Future<List<String>> pages(String key) async {
    final cached = _pageLists[key];
    if (cached != null &&
        DateTime.now().difference(cached.$1) < const Duration(seconds: 60)) {
      return cached.$2;
    }
    if (_pageTasks[key] case final task?) return task;
    final task = _loadPages(key);
    _pageTasks[key] = task;
    try {
      final result = List<String>.unmodifiable(await task);
      _pageLists[key] = (DateTime.now(), result);
      if (_pageLists.length > 4) _pageLists.remove(_pageLists.keys.first);
      return result;
    } finally {
      _pageTasks.remove(key);
    }
  }

  Future<List<String>> _loadPages(String key) async {
    final uri = decode(key);
    final body = await fetch(_relative(uri));
    if (id == 'dongman') {
      final result = (await parseBuiltinImagePaths(body)).map(image).toList();
      if (result.isEmpty) throw SourceException('此章节需要在咚漫原站登录、购买或使用原站 App 阅读。');
      return result;
    }
    final cid = RegExp(r'^/m(\d+)/$').firstMatch(uri.path)?.group(1);
    final count = int.tryParse(
      RegExp(r'MANGABZ_IMAGE_COUNT\s*=\s*(\d+)').firstMatch(body)?.group(1) ??
          '',
    );
    if (cid == null || count == null || count < 1 || count > 1500) {
      throw SourceException('此章节没有返回公开图片，请在 Mangabz 原站核对。');
    }
    Future<List<String>> batch(int page) async {
      final data = Dm5Source.unpack(
        await fetch('${uri.path}chapterimage.ashx?cid=$cid&page=$page'),
      );
      final prefix = RegExp(
        r'''\bpix\s*=\s*"([^"]+)"''',
      ).firstMatch(data)?.group(1);
      final paths = RegExp(
        r'''\bpvalue\s*=\s*\[([^\]]+)\]''',
      ).firstMatch(data)?.group(1);
      // The endpoint returns a data-only path list and a query token. Decode
      // these literals; never execute its packed function.
      final keyToken = RegExp(
        "\\bkey\\s*=\\s*'([^']+)'",
      ).firstMatch(data)?.group(1);
      if (prefix == null || paths == null || keyToken == null) {
        throw SourceException('Mangabz 图片地址格式已变化，请打开原站核对。');
      }
      final values = (jsonDecode('[$paths]') as List).cast<String>();
      if (values.isEmpty) throw SourceException('Mangabz 返回了空的图片列表。');
      return [
        for (final value in values)
          image(
            '$prefix$value?cid=$cid&key=${Uri.encodeComponent(keyToken)}&uk=',
          ),
      ];
    }

    final first = await batch(1);
    final result = <String>[...first];
    // The public endpoint normally returns two pages (occasionally a cached
    // larger batch). Fetch bounded batches concurrently, preserving page order.
    // At most three new requests per 800 ms; avoid serial waits on long volumes.
    final stride = first.length;
    for (var start = stride + 1; start <= count; start += stride * 3) {
      final watch = Stopwatch()..start();
      final groups = await Future.wait([
        for (var p = start; p < start + stride * 3 && p <= count; p += stride)
          batch(p),
      ]);
      for (var i = 0; i < groups.length; i++) {
        final remaining = count - result.length;
        result.addAll(groups[i].take(remaining < stride ? remaining : stride));
      }
      final pause = const Duration(milliseconds: 800) - watch.elapsed;
      if (pause > Duration.zero && result.length < count) {
        await Future<void>.delayed(pause);
      }
    }
    if (result.length != count) throw SourceException('Mangabz 未返回完整图片列表，请重试。');
    return result.take(count).toList();
  }
}

/// Top-level callback keeps the transport and widget state out of the isolate.
List<Comic> parseBuiltinCatalogData((String, String, bool, bool) input) {
  final client = http.Client();
  try {
    return BuiltinSource(
      input.$1,
      client,
    ).parseCatalog(input.$2, search: input.$3, allowEmpty: input.$4);
  } finally {
    client.close();
  }
}
