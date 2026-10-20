import 'dart:convert';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'comic.dart';

/// Public DM5 pages only. No embedded cookies, account credentials, or remote JS execution.
class Dm5Source {
  Dm5Source({this.gateway, http.Client? client})
    : _client = client ?? http.Client();
  final Uri? gateway;
  final http.Client _client;
  static const origin = 'https://m.dm5.com';
  Future<String> _get(String path) async {
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

  Future<List<Comic>> home() async => parseCatalog(await _get('/'));
  Future<List<Comic>> search(String query) async => parseCatalog(
    await _get('/search?title=${Uri.encodeComponent(query.trim())}'),
  );
  Future<ComicDetail> detail(Comic comic) async =>
      parseDetail(await _get(comic.path), comic);
  Future<List<String>> pages(String path) async => parsePages(await _get(path));
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
      final path = anchor?.attributes['href'] ?? '';
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
