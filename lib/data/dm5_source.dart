import 'dart:convert';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'comic.dart';
import 'discovery.dart';
import 'source_catalog.dart';

/// Public DM5 pages only. No embedded cookies, account credentials, or remote JS execution.
class Dm5Source {
  static Future<List<String>?> Function(String path)? offlinePages;
  static Future<ComicDetail?> Function(Comic comic)? offlineDetail;
  Dm5Source({this.gateway, http.Client? client})
    : _client = client ?? http.Client();
  final Uri? gateway;
  final http.Client _client;
  static const origin = 'https://m.dm5.com';
  static final Map<String, String> imageOrigins = {};
  static Map<String, String> headersForImage(String url) => {
    'Referer': imageOrigins[Uri.tryParse(url)?.host] ?? '$origin/',
  };
  Future<String> fetchPage(String path) async {
    final uri =
        gateway
            ?.resolve('/api/source')
            .replace(queryParameters: {'path': path}) ??
        Uri.parse('$origin$path');
    final response = await _client
        .get(
          uri,
          headers: gateway == null
              ? {
                  'User-Agent':
                      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/130.0 Mobile Safari/537.36',
                  'Referer': '$origin/',
                }
              : null,
        )
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw SourceException('动漫屋暂时无法访问（${response.statusCode}），请稍后重试。');
    }
    final text = utf8.decode(response.bodyBytes);
    if (text.contains('Just a moment...') || text.contains('cf-chl-')) {
      throw SourceException('动漫屋需要网页验证，请在浏览器打开原站。');
    }
    return text;
  }

  Future<List<Comic>> home() async => parseCatalog(await fetchPage('/'));
  Future<List<Comic>> search(String query) async => parseCatalog(
    await fetchPage('/search?title=${Uri.encodeComponent(query.trim())}'),
  );
  Future<ComicDetail> detail(Comic comic) async {
    if (comic.sourceId == 'local') {
      return (await offlineDetail?.call(comic)) ??
          (throw SourceException('本地漫画文件不存在。'));
    }
    try {
      return parseDetail(await fetchPage(comic.path), comic);
    } catch (_) {
      final stored = await offlineDetail?.call(comic);
      if (stored != null) return stored;
      rethrow;
    }
  }

  Future<List<String>> pages(String path) async =>
      await offlinePages?.call(path) ?? await networkPages(path);
  Future<List<String>> networkPages(String path) async =>
      parsePages(await fetchPage(path));
  Future<Discovery> discover() async => parseDiscovery(await fetchPage('/'));
  Future<List<Comic>> browse(String path) async =>
      parseCatalog(await fetchPage(path));
  Future<Map<String, String>> categories() async =>
      SourceCatalog.categories(await fetchPage('/search/'));
  Future<SourceCatalog> catalog(String path) async {
    final input = await fetchPage(path);
    return SourceCatalog.parse(input, parseCatalog(input));
  }

  Future<List<Comic>> catalogNext(Map<String, String> specs, int page) async {
    final fields = {
      ...specs,
      'action': 'getclasscomics',
      'pageindex': '$page',
      'pagesize': specs['pagesize'] ?? '10',
      'iscopyright': 'false',
    };
    final response = gateway == null
        ? await _client
              .post(
                Uri.parse('$origin/dm5.ashx'),
                headers: {'Referer': '$origin/', 'User-Agent': 'Mozilla/5.0'},
                body: fields,
              )
              .timeout(const Duration(seconds: 25))
        : await _client
              .post(
                gateway!.resolve('/api/list'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode(fields),
              )
              .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw SourceException('分类加载失败（${response.statusCode}）');
    }
    final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
    return (data['UpdateComicItems'] as List? ?? [])
        .map(
          (item) => Comic(
            path: '/${item['UrlKey']}/',
            title: item['Title'] ?? '',
            cover: item['ShowPicUrlB'] ?? '',
            latest:
                '${item['Status'] == 1 ? '完结' : '最新'} ${item['ShowLastPartName'] ?? ''}',
          ),
        )
        .where((c) => c.cover.startsWith('https://'))
        .toList();
  }

  static Discovery parseDiscovery(String input) {
    final doc = html.parse(input);
    final sections = <String, List<Comic>>{};
    for (final section in doc.querySelectorAll('.manga-list')) {
      final header = section.querySelector('.manga-list-title');
      if (header == null) continue;
      final title = header.nodes
          .where((n) => n.nodeType == 3)
          .map((n) => n.text)
          .join()
          .trim();
      if (title.isEmpty || title == '排行榜') continue;
      try {
        final books = parseCatalog(section.outerHtml);
        if (books.isNotEmpty) sections[title] = books;
      } catch (_) {}
    }
    final ranks = <String, List<Comic>>{};
    final labels = doc
        .querySelectorAll('.manga-list-title-right-item')
        .map((e) => e.text.trim())
        .toList();
    for (var i = 1; i <= 4; i++) {
      final section = doc.querySelector('#rank_$i');
      if (section != null) {
        try {
          ranks[i <= labels.length
              ? labels[i - 1]
              : ['人气', '新番', '收藏', '吐槽'][i - 1]] = parseCatalog(
            section.outerHtml,
          );
        } catch (_) {}
      }
    }
    return Discovery(
      books: parseCatalog(input),
      sections: sections,
      ranks: ranks,
      capturedAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  void close() => _client.close();

  static List<Comic> parseCatalog(String input) {
    final doc = html.parse(input);
    final result = <String, Comic>{};
    for (final image in doc.querySelectorAll(
      '.manga-list-2-cover img, .manga-list-1-cover img, .rank-list-cover img, .book-list-cover img',
    )) {
      final anchor = image.parent?.localName == 'a'
          ? image.parent
          : image.parent?.parent;
      final href = anchor?.attributes['href'] ?? '';
      final parsed = Uri.tryParse(href);
      final path = parsed?.hasAuthority == false ? parsed!.path : '';
      var item = image.parent;
      while (item != null && item.localName != 'li') {
        item = item.parent;
      }
      final title =
          (anchor?.attributes['title'] ??
                  item
                      ?.querySelector(
                        '.manga-list-2-title, .manga-list-1-title, .rank-list-title',
                      )
                      ?.text ??
                  '')
              .trim();
      final cover =
          image.attributes['src'] ?? image.attributes['data-src'] ?? '';
      if (!RegExp(r'^/manhua-[\w-]+/$').hasMatch(path) ||
          title.isEmpty ||
          !cover.startsWith('https://')) {
        continue;
      }
      result.putIfAbsent(
        path,
        () => Comic(
          path: path,
          title: title,
          cover: cover,
          latest: item?.querySelector('.manga-list-2-tip')?.text.trim() ?? '',
          description:
              item?.querySelector('.book-list-info-desc')?.text.trim() ?? '',
        ),
      );
    }
    if (result.isEmpty && !input.contains('搜索')) {
      throw SourceException('动漫屋页面结构有变化，暂时未读到漫画列表。');
    }
    return result.values.toList();
  }

  static ComicDetail parseDetail(String input, Comic fallback) {
    final doc = html.parse(input);
    final title = doc.querySelector('.detail-main-info-title')?.text.trim();
    if (title == null || title.isEmpty) {
      throw SourceException('未读到漫画详情，请在原站查看或稍后重试。');
    }
    final chapters = <Chapter>[];
    final seen = <String>{};
    for (final group in doc.querySelectorAll('.detail-list-select')) {
      final groupName = switch (group.id) {
        'detail-list-select-2' => '卷',
        'detail-list-select-3' => '番外',
        _ => '连载',
      };
      for (final anchor in group.querySelectorAll('a[href]')) {
        final path = anchor.attributes['href']!;
        if (RegExp(r'^/m\d+/$').hasMatch(path) && seen.add(path)) {
          chapters.add(Chapter(path, anchor.text.trim(), group: groupName));
        }
      }
    }
    return ComicDetail(
      Comic(
        path: fallback.path,
        title: title,
        cover:
            doc.querySelector('.detail-main-cover img')?.attributes['src'] ??
            fallback.cover,
        author:
            doc
                .querySelector('.detail-main-info-author')
                ?.text
                .trim()
                .replaceFirst('作者：', '') ??
            '',
        latest:
            doc.querySelector('.detail-list-title-2')?.text.trim() ??
            fallback.latest,
        description:
            doc
                .querySelector('.detail-desc, .detail-desc-content')
                ?.text
                .trim() ??
            '',
        tags: doc
            .querySelectorAll('.detail-main-info-class span')
            .map((e) => e.text.trim())
            .toList(),
      ),
      chapters,
    );
  }

  /// Decode the page's standard P.A.C.K.E.R string substitution as data, never eval.
  static String unpack(String input) {
    final pattern = RegExp(
      r"\}\('((?:\\.|[^'\\])*)',\s*(\d+),\s*(\d+),\s*'((?:\\.|[^'\\])*)'\.split\('\|'\)",
      dotAll: true,
    );
    final match = pattern.firstMatch(input);
    if (match == null) return input;
    String unescape(String s) =>
        s.replaceAll(r"\'", "'").replaceAll(r'\/', '/').replaceAll(r'\\', r'\');
    final payload = unescape(match[1]!);
    final radix = int.parse(match[2]!);
    final count = int.parse(match[3]!);
    if (radix < 2 || radix > 62 || count > 20000) {
      throw SourceException('暂不支持此章节的数据格式。');
    }
    final words = unescape(match[4]!).split('|');
    const alphabet =
        '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
    String encode(int value) {
      var v = value;
      var out = '';
      do {
        out = alphabet[v % radix] + out;
        v = v ~/ radix;
      } while (v > 0);
      return out;
    }

    final table = <String, String>{
      for (var i = 0; i < count && i < words.length; i++)
        if (words[i].isNotEmpty) encode(i): words[i],
    };
    return payload.replaceAllMapped(
      RegExp(r'\b[0-9A-Za-z]+\b'),
      (m) => table[m[0]] ?? m[0]!,
    );
  }

  static List<String> parsePages(String input) {
    final decoded = unpack(input);
    final list = RegExp(
      r'(?:newImgs|chapterImages)\s*=\s*\[(.*?)\]',
      dotAll: true,
    ).firstMatch(decoded);
    if (list == null) throw SourceException('此章节暂时无法直接读取。可能需要登录或原站阅读，请打开动漫屋。');
    final urls = RegExp(r'''["'](https://[^"']+)["']''')
        .allMatches(list[1]!)
        .map((m) => m[1]!.replaceAll(r'\/', '/'))
        .where((s) => Uri.tryParse(s)?.host.endsWith('.cdndm5.com') ?? false)
        .toList();
    if (urls.isEmpty) throw SourceException('此章节没有可读取的图片，请在原站查看。');
    return urls;
  }
}

class SourceException implements Exception {
  SourceException(this.message);
  final String message;
  @override
  String toString() => message;
}
