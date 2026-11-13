import 'dart:isolate';
import 'source_page_parser.dart';

/// A long strip's HTML can contain hundreds of image nodes and tracking markup.
/// Parse in a short-lived isolate so scrolling/input can continue on the UI one.
Future<List<String>> parseBuiltinImagePaths(String body) =>
    Isolate.run(() => extractBuiltinImagePaths(body));

Future<T> runSourceParse<T, M>(T Function(M) parse, M message) =>
    Isolate.run(() => parse(message));
