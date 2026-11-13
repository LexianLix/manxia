import 'package:html/parser.dart' as html;

List<String> extractBuiltinImagePaths(String body) => html
    .parse(body)
    .querySelectorAll('#_imageList img[data-url]')
    .map((e) => e.attributes['data-url']!)
    .toList();
