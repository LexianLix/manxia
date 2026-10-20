import 'dart:convert';
import 'dart:io';
import 'package:manxia/data/source_catalog.dart';

void main() {
  final data = SourceCatalog.categories(
    File('.cache/wenku8-reference/dm5-categories.html').readAsStringSync(),
  );
  File(
    'assets/categories.json',
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
  stdout.writeln('${data.length} categories');
}
