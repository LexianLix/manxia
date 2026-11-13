import 'source_page_parser.dart';

Future<List<String>> parseBuiltinImagePaths(String body) async =>
    extractBuiltinImagePaths(body);

Future<T> runSourceParse<T, M>(T Function(M) parse, M message) async =>
    parse(message);
