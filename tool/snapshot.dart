import 'dart:convert';
import 'dart:io';
import 'package:manxia/data/dm5_source.dart';
import 'package:manxia/data/discovery.dart';

Future<void> main() async {
  final file = File('.cache/wenku8-reference/dm5-home.html');
  final parsed = Dm5Source.parseDiscovery(await file.readAsString());
  final result = Discovery(
    books: parsed.books,
    sections: parsed.sections,
    ranks: parsed.ranks,
    capturedAt: (await file.lastModified()).toUtc().toIso8601String(),
  );
  await File(
    'assets/discovery.json',
  ).writeAsString(const JsonEncoder.withIndent('  ').convert(result.toJson()));
  stdout.writeln(
    '${result.books.length} books / ${result.sections.length} sections / ${result.ranks.length} ranks',
  );
}
