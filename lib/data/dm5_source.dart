import 'dart:async';
import 'dart:convert';
import 'package:html/parser.dart' as html;
import 'package:html/dom.dart' show Element;
import 'package:http/http.dart' as http;
import 'comic.dart';
import 'discovery.dart';
import 'source_catalog.dart';

/// Public DM5 pages only. No embedded cookies, account credentials, or remote JS execution.
class Dm5Source {
  static Future<List<String>?> Function(String path)? offlinePages;
  static Future<ComicDetail?> Function(Comic comic)? offlineDetail;
  static final Map<String, List<Chapter>> chapterCatalogs = {};
  Dm5Source({this.gateway, http.Client? client, this.allowOffline = true})
    : _client = client ?? http.Client();
  final Uri? gateway;
  final http.Client _client;
  final bool allowOffline;
  Future<void> Function(Comic comic, SourceException? error)? onDetailStatus;
  Future<void> reportDetailStatus(Comic comic, SourceException? error) async {
    try {
      await onDetailStatus?.call(comic, error);
    } catch (_) {
      // A failed local status write must not make a readable chapter fail.
    }
  }

  /// A diagnostic owns its transport and reads the network rather than saved chapters.
  Dm5Source forkForCheck() => Dm5Source(gateway: gateway, allowOffline: false);
  final detailDiagnostics = <String, Map<String, Object?>>{};
  static const origin = 'https://m.dm5.com';
  static final Map<String, String> imageOrigins = {};
  static Map<String, String> headersForImage(String url) => {
    'Referer': imageOrigins[Uri.tryParse(url)?.host] ?? '$origin/',
  };
  Future<String> fetchPage(String path, {bool desktop = false}) async {
    final base = desktop ? 'https://www.dm5.com' : origin;
    final uri =
        gateway
            ?.resolve('/api/source')
            .replace(
              queryParameters: {
                'path': path,
                if (desktop) 'edition': 'desktop',
              },
            ) ??
        Uri.parse('$base$path');
    return requestText(
      () => _client.get(
        uri,
        headers: gateway == null
            ? {
                'User-Agent': desktop
                    ? 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/130.0 Safari/537.36'
                    : 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/130.0 Mobile Safari/537.36',
                'Referer': '$base/',
              }
            : null,
      ),
      sourceName: '动漫屋',
    );
  }

  /// Interpret access failures before any source-specific HTML selectors run.
  static Future<String> requestText(
    Future<http.Response> Function() request, {
    required String sourceName,
  }) async {
    late http.Response response;
    try {
      response = await request().timeout(const Duration(seconds: 25));
    } on TimeoutException {
      throw SourceException('$sourceName 连接超时，请检查网络后重试。');
    } on http.ClientException {
      throw SourceException('$sourceName 连接失败，请检查网络后重试。');
    }
    if (response.statusCode == 404 || response.statusCode == 410) {
      throw SourceEntryException(sourceName, response.statusCode);
    }
    if (response.statusCode == 401) {
      throw SourceException('$sourceName 需要登录，请在原站打开。');
    }
    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (text.contains('Just a moment...') ||
        text.contains('cf-chl-') ||
        text.contains('/cdn-cgi/challenge-platform/')) {
      throw SourceException('$sourceName 需要网页验证，请在浏览器打开原站。');
    }
    if (response.statusCode == 403) {
      throw SourceException('$sourceName 拒绝了本次访问（403），请在原站核对访问限制。');
    }
    if (response.statusCode == 429) {
      throw SourceException('$sourceName 请求过于频繁（429），请稍等后重试。');
    }
    if (response.statusCode != 200) {
      throw SourceException(
        '$sourceName 暂时无法访问（${response.statusCode}），请稍后重试。',
      );
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
    final attempts = <Map<String, Object?>>[];
    detailDiagnostics.remove(comic.path);
    detailDiagnostics[comic.path] = {'path': comic.path, 'attempts': attempts};
    while (detailDiagnostics.length > 12) {
      detailDiagnostics.remove(detailDiagnostics.keys.first);
    }
    Future<ComicDetail> readEdition(bool desktop) async {
      final attempt = <String, Object?>{
        'edition': desktop ? 'desktop' : 'mobile',
      };
      attempts.add(attempt);
      try {
        final input = await fetchPage(comic.path, desktop: desktop);
        attempt['characters'] = input.length;
        return parseDetail(
          input,
          comic,
          inspect: (value) => attempt.addAll(value),
        );
      } catch (error) {
        attempt['error'] = error.toString();
        rethrow;
      }
    }

    try {
      ComicDetail result;
      try {
        result = await readEdition(false);
      } on _DetailEditionException {
        // A mobile search-only landing is not a statement about the public
        // desktop edition. Check the same work there, never follow the
        // external search link or substitute another comic's chapters.
        // Explicit removal/migration notices and HTTP challenges still stop.
        result = await readEdition(true);
      }
      chapterCatalogs[comic.path] = result.chapters;
      await reportDetailStatus(comic, null);
      return result;
    } catch (error) {
      if (error is SourceCopyrightException || error is SourceEntryException) {
        await reportDetailStatus(comic, error as SourceException);
      }
      final stored = allowOffline ? await offlineDetail?.call(comic) : null;
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
    final sectionPaths = <String, String>{}, rankPaths = <String, String>{};
    String? morePath(Element element) {
      for (final a in element.querySelectorAll('a[href]')) {
        if (!a.text.contains('更多') || a.querySelector('img') != null) continue;
        final uri = Uri.tryParse(a.attributes['href'] ?? '');
        if (uri != null &&
            (!uri.hasAuthority || uri.host == 'm.dm5.com') &&
            RegExp(r'^/manhua-[\w-]+/$').hasMatch(uri.path)) {
          return uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
        }
      }
      return null;
    }

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
        if (books.isNotEmpty) {
          sections[title] = books;
          final path = morePath(header);
          if (path != null) sectionPaths[title] = path;
        }
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
          final label = i <= labels.length
              ? labels[i - 1]
              : ['人气', '新番', '收藏', '吐槽'][i - 1];
          final path = morePath(section);
          if (path != null) rankPaths[label] = path;
        } catch (_) {}
      }
    }
    return Discovery(
      books: parseCatalog(input),
      sections: sections,
      ranks: ranks,
      capturedAt: DateTime.now().toUtc().toIso8601String(),
      sectionPaths: sectionPaths,
      rankPaths: rankPaths,
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
      final path =
          parsed != null &&
              (!parsed.hasAuthority ||
                  parsed.host == 'm.dm5.com' ||
                  parsed.host == 'www.dm5.com')
          ? parsed.path
          : '';
      var item = image.parent;
      while (item != null && item.localName != 'li') {
        item = item.parent;
      }
      final anchorTitle = anchor?.attributes['title']?.trim() ?? '';
      final title =
          (anchorTitle.isNotEmpty
                  ? anchorTitle
                  : item
                            ?.querySelector(
                              '.manga-list-2-title, .manga-list-1-title, .rank-list-title, .book-list-info-title',
                            )
                            ?.text ??
                        '')
              .trim();
      final cover = ['data-src', 'data-original', 'data-lazy-src', 'src']
          .map((key) => image.attributes[key] ?? '')
          .map((url) => url.startsWith('//') ? 'https:$url' : url)
          .firstWhere((url) => url.startsWith('https://'), orElse: () => '');
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
          author:
              item
                  ?.querySelector(
                    '.manga-list-2-author, .book-list-info-author, .rank-list-author',
                  )
                  ?.text
                  .trim() ??
              '',
          tags: [
            if ((item
                        ?.querySelector('.book-list-info-bottom-right-font')
                        ?.text
                        .trim() ??
                    '')
                .isNotEmpty)
              item!
                  .querySelector('.book-list-info-bottom-right-font')!
                  .text
                  .trim(),
          ],
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

  static ComicDetail parseDetail(
    String input,
    Comic fallback, {
    void Function(Map<String, Object?> value)? inspect,
  }) {
    final doc = html.parse(input);
    final desktopInfo = doc.querySelector('.banner_detail_form .info');
    final desktopTitle = desktopInfo
        ?.querySelector('.title')
        ?.nodes
        .where((n) => n.nodeType == 3)
        .map((n) => n.text)
        .join()
        .trim();
    final title =
        doc.querySelector('.detail-main-info-title')?.text.trim() ??
        desktopTitle;
    final containers = doc.querySelectorAll(
      '.detail-list-select, #detail-list-select-1, #detail-list-select-2, #detail-list-select-3',
    );
    inspect?.call({'title': title, 'groups': containers.length});
    if (title == null || title.isEmpty) {
      final notice =
          doc
              .querySelector('.warning-bar')
              ?.text
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim() ??
          '';
      if (_isCopyrightRemoval(notice)) {
        inspect?.call({'availability': 'copyright', 'notice': notice});
        throw SourceCopyrightException(notice, comic: fallback);
      }
      throw _DetailLayoutException('未读到漫画详情，请在原站查看或稍后重试。');
    }
    final resolved = Comic(
      path: fallback.path,
      title: title,
      cover:
          doc.querySelector('.detail-main-cover img')?.attributes['src'] ??
          doc
              .querySelector('.banner_detail_form .cover img')
              ?.attributes['src'] ??
          fallback.cover,
      author:
          doc
              .querySelector('.detail-main-info-author')
              ?.text
              .trim()
              .replaceFirst('作者：', '') ??
          desktopInfo
              ?.querySelector('.subtitle')
              ?.text
              .trim()
              .replaceFirst('作者：', '') ??
          fallback.author,
      latest:
          doc.querySelector('.detail-list-title-2')?.text.trim() ??
          fallback.latest,
      description:
          doc
              .querySelector('.detail-desc, .detail-desc-content')
              ?.text
              .trim() ??
          desktopInfo?.querySelector('.content')?.text.trim() ??
          fallback.description,
      tags: doc
          .querySelectorAll('.detail-main-info-class span')
          .map((e) => e.text.trim())
          .toList(),
    );
    final chapters = <Chapter>[];
    final seen = <String>{};
    final oldestFirst = RegExp(r'\bDM5_COMIC_SORT\s*=\s*1\s*;').hasMatch(input);
    for (final group in containers) {
      final groupName = switch (group.id) {
        'detail-list-select-2' => '卷',
        'detail-list-select-3' => '番外',
        _ => '连载',
      };
      final members = <Chapter>[];
      for (final anchor in group.querySelectorAll('a[href]')) {
        final uri = Uri.tryParse(anchor.attributes['href']!);
        if (uri == null ||
            (uri.hasAuthority &&
                (uri.userInfo.isNotEmpty ||
                    uri.hasPort ||
                    !{
                      'm.dm5.com',
                      'www.dm5.com',
                      'dm5.com',
                    }.contains(uri.host))) ||
            (uri.hasScheme && !{'https', 'http'}.contains(uri.scheme))) {
          continue;
        }
        final path = uri.path;
        if (RegExp(r'^/m\d+/$').hasMatch(path) && seen.add(path)) {
          final label =
              (anchor.querySelector('.detail-list-2-info-title')?.text ??
                      anchor.text)
                  .replaceAll(RegExp(r'\s+'), ' ')
                  .trim();
          members.add(Chapter(path, label, group: groupName));
        }
      }
      // Consumers expect newest first and reverse for their reading sequence.
      // The source explicitly marks thumbnail layouts as oldest first.
      chapters.addAll(oldestFirst ? members.reversed : members);
    }
    inspect?.call({'chapters': chapters.length});
    if (chapters.isEmpty) {
      final notice =
          doc
              .querySelector('.warning-bar')
              ?.text
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim() ??
          '';
      if (notice.contains('全篇转移') && notice.contains('漫画人')) {
        inspect?.call({'availability': 'migration', 'notice': notice});
        throw SourceException('原站已将这部漫画的网页章节迁移到漫画人 App，当前网页无法读取目录。');
      }
      final copyrightRemoval = _isCopyrightRemoval(notice);
      if (copyrightRemoval) {
        inspect?.call({'availability': 'copyright', 'notice': notice});
        throw SourceCopyrightException(notice, comic: resolved);
      }
      if (notice.isNotEmpty) {
        inspect?.call({'availability': 'notice', 'notice': notice});
        throw SourceException('原站提示：$notice');
      }
      if (doc
              .querySelector('.detail-fix-bottom .detail-bottom-btn')
              ?.text
              .contains('全网搜索') ==
          true) {
        inspect?.call({'availability': 'externalSearch'});
        throw _DetailEditionException('此入口只提供外部搜索，没有返回本作品的网页章节。');
      }
      inspect?.call({'availability': 'unrecognized'});
      throw _DetailLayoutException('未能识别章节目录，可能是页面结构变化或访问验证。请重新加载，或打开原站核对。');
    }
    inspect?.call({'availability': 'available'});
    return ComicDetail(resolved, chapters);
  }

  static bool _isCopyrightRemoval(String notice) =>
      RegExp(
        r'版权|版權|著作权|著作權|copyright',
        caseSensitive: false,
      ).hasMatch(notice) &&
      RegExp(
        r'删除|刪除|清理|移除|下架|屏蔽|未授权|未授權|未经授权|未經授權|没有版权|沒有版權|无版权|無版權|removed|unavailable',
        caseSensitive: false,
      ).hasMatch(notice);

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
    if (list == null) {
      _unreadableChapter(input, '此章节暂时无法直接读取。可能需要登录或原站阅读，请打开动漫屋。');
    }
    final urls = RegExp(r'''["'](https://[^"']+)["']''')
        .allMatches(list[1]!)
        .map((m) => m[1]!.replaceAll(r'\/', '/'))
        .where((s) => Uri.tryParse(s)?.host.endsWith('.cdndm5.com') ?? false)
        .toList();
    if (urls.isEmpty) _unreadableChapter(input, '此章节没有可读取的图片，请在原站查看。');
    return urls;
  }

  static Never _unreadableChapter(String input, String reason) {
    if (input.contains('warning-bar')) {
      final notice =
          html
              .parse(input)
              .querySelector('.warning-bar')
              ?.text
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim() ??
          '';
      if (_isCopyrightRemoval(notice)) throw SourceCopyrightException(notice);
    }
    throw SourceException(reason);
  }
}

class SourceException implements Exception {
  SourceException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SourceEntryException extends SourceException {
  SourceEntryException(String name, this.statusCode)
    : super('$name 的这个入口已失效（$statusCode），请重新搜索或换源查找。');
  final int statusCode;
}

/// An explicit rights/removal notice from this source, never inferred from a
/// timeout, empty layout, search landing or a different source's response.
class SourceCopyrightException extends SourceException {
  SourceCopyrightException(this.notice, {this.comic})
    : super('当前书源没有版权，无法提供在线章节。');
  final String notice;
  final Comic? comic;
}

class _DetailEditionException extends SourceException {
  _DetailEditionException(super.message);
}

class _DetailLayoutException extends _DetailEditionException {
  _DetailLayoutException(super.message);
}
