import 'package:html/parser.dart' as html;
import 'comic.dart';

class SourceCatalog {
  SourceCatalog({
    required this.books,
    required this.sorts,
    required this.statuses,
    required this.parameters,
  });
  final List<Comic> books;
  final Map<String, String> sorts, statuses, parameters;
  static Map<String, String> categories(String input) {
    final result = <String, String>{};
    for (final a in html.parse(input).querySelectorAll('a[href]')) {
      final label = a.querySelector('.search-class-title')?.text.trim();
      final path = a.attributes['href'] ?? '';
      if (label != null && RegExp(r'^/manhua-[a-z0-9-]+/$').hasMatch(path)) {
        result[label] = path;
      }
    }
    return result;
  }

  static SourceCatalog parse(String input, List<Comic> books) {
    final doc = html.parse(input);
    Map<String, String> links(String selector) {
      final result = <String, String>{};
      for (final a in doc.querySelectorAll(selector)) {
        final href = a.attributes['href'] ?? '';
        final path = RegExp(
          r"pushHistory\('(/manhua-[a-z0-9-]+/)'\)",
        ).firstMatch(href)?.group(1);
        if (path != null) result[a.text.trim()] = path;
      }
      return result;
    }

    final parameters = <String, String>{};
    for (final key in [
      'pageindex',
      'pagesize',
      'usergroup',
      'categoryid',
      'tagid',
      'status',
      'sort',
      'pay',
      'areaid',
    ]) {
      parameters[key] =
          RegExp('var $key = "(-?[0-9]+)"').firstMatch(input)?.group(1) ?? '0';
    }
    return SourceCatalog(
      books: books,
      sorts: links('.manga-list-bar-item'),
      statuses: links('.manga-list-bar-right-down-item'),
      parameters: parameters,
    );
  }
}
