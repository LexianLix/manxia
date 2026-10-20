import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;
import 'comic.dart';
import 'dm5_source.dart';

/// A deliberately declarative adapter: selectors and URLs, never downloaded code.
class SourceProfile {
  SourceProfile(this.json) {
    validate();
  }
  final Map<String, dynamic> json;
  String get id => json['id'] as String;
  String get name => json['name'] as String;
  Uri get base => Uri.parse(json['baseUrl'] as String);
  String value(String key, [String fallback = '']) =>
      json[key] as String? ?? fallback;
  List<String> get imageHosts =>
      List<String>.from(json['imageHosts'] ?? [base.host]);
  void validate() {
    if (!RegExp(r'^[a-z0-9_-]{1,40}$').hasMatch(json['id'] as String? ?? '') ||
        json['id'] == 'dm5' ||
        json['id'] == 'local') {
      throw const FormatException('源 id 需为 1–40 位小写字母、数字、下划线或短横线。');
    }
    if (base.scheme != 'https' ||
        base.userInfo.isNotEmpty ||
        base.host.isEmpty) {
      throw const FormatException('漫画源需填写不带账号密码的 HTTPS 地址。');
    }
    for (final key in [
      'name',
      'cards',
      'title',
      'link',
      'cover',
      'chapters',
      'pages',
    ]) {
      if (value(key).trim().isEmpty) throw FormatException('源配置缺少 $key');
    }
    if (imageHosts.any((h) => !RegExp(r'^[a-zA-Z0-9.-]+$').hasMatch(h))) {
      throw const FormatException('imageHosts 只能填写域名。');
    }
    // Parse selectors now so malformed profiles fail before they are saved.
    for (final key in [
      'cards',
      'title',
      'link',
      'cover',
      'chapters',
      'pages',
    ]) {
      html.parse('').querySelectorAll(value(key));
    }
  }

  Uri url(String path) {
    final result = base.resolve(path);
    if (result.origin != base.origin || result.userInfo.isNotEmpty) {
      throw const FormatException('页面链接超出了漫画源地址。');
    }
    return result;
  }

  String encode(Uri uri) => 'custom:$id:${Uri.encodeComponent(uri.toString())}';
  Uri decode(String path) =>
      url(Uri.decodeComponent(path.substring('custom:$id:'.length)));
  String text(Element card, String selector) =>
      card.querySelector(selector)?.text.trim() ?? '';
  List<Comic> catalog(String input) {
    final result = <String, Comic>{};
    for (final card in html.parse(input).querySelectorAll(value('cards'))) {
      final link = card.querySelector(value('link'))?.attributes['href'];
      final image = card.querySelector(value('cover'));
      final cover = image?.attributes[value('coverAttribute', 'src')] ?? '';
      if (link == null || cover.isEmpty) continue;
      final uri = url(link);
      final imageUri = base.resolve(cover);
      if (imageUri.scheme != 'https' || !imageHosts.contains(imageUri.host)) {
        continue;
      }
      final title = text(card, value('title'));
      if (title.isEmpty) continue;
      result[uri.toString()] = Comic(
        path: encode(uri),
        title: title,
        cover: imageUri.toString(),
        sourceId: id,
        author: value('author').isEmpty ? '' : text(card, value('author')),
        latest: value('latest').isEmpty ? '' : text(card, value('latest')),
      );
    }
    return result.values.toList();
  }

  ComicDetail detail(String input, Comic comic) {
    final doc = html.parse(input);
    final chapters = <String, Chapter>{};
    for (final item in doc.querySelectorAll(value('chapters'))) {
      final href = item.attributes['href'];
      if (href == null) continue;
      final path = encode(url(href));
      chapters[path] = Chapter(path, item.text.trim());
    }
    if (chapters.isEmpty) throw SourceException('$name 未解析到章节，请检查选择器。');
    final list = chapters.values.toList();
    final description = value('description').isEmpty
        ? comic.description
        : doc.querySelector(value('description'))?.text.trim() ?? '';
    return ComicDetail(
      Comic(
        path: comic.path,
        title: comic.title,
        cover: comic.cover,
        author: comic.author,
        latest: comic.latest,
        tags: comic.tags,
        sourceId: id,
        description: description,
      ),
      json['reverseChapters'] == true ? list.reversed.toList() : list,
    );
  }

  List<String> pages(String input) {
    final pages = html
        .parse(input)
        .querySelectorAll(value('pages'))
        .map(
          (e) => base
              .resolve(e.attributes[value('pageAttribute', 'src')] ?? '')
              .toString(),
        )
        .where((s) {
          final u = Uri.parse(s);
          return u.scheme == 'https' && imageHosts.contains(u.host);
        })
        .toList();
    if (pages.isEmpty) throw SourceException('$name 未解析到图片。此适配器支持静态 HTML 页面。');
    return pages;
  }
}
