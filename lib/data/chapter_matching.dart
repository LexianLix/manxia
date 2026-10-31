import 'comic.dart';

String chapterName(String title) => title
    .toLowerCase()
    .replaceAllMapped(
      RegExp('[０-９]'),
      (m) => String.fromCharCode(m[0]!.codeUnitAt(0) - 0xff10 + 48),
    )
    .replaceAll(RegExp(r'[^\p{L}\p{N}.]', unicode: true), '');

num? chapterNumber(String title) {
  final match =
      RegExp(
        r'第?\s*([0-9]+(?:\.[0-9]+)?|[零〇一二两兩三四五六七八九十百千壹贰貳叁參肆伍陆陸柒捌玖拾佰仟]+)\s*[话話回章集卷]',
      ).firstMatch(
        title.replaceAllMapped(
          RegExp('[０-９]'),
          (m) => String.fromCharCode(m[0]!.codeUnitAt(0) - 0xff10 + 48),
        ),
      );
  if (match == null) return null;
  final token = match[1]!;
  final number = num.tryParse(token);
  if (number != null) return number;
  const digits = {
    '零': 0,
    '〇': 0,
    '一': 1,
    '壹': 1,
    '二': 2,
    '两': 2,
    '兩': 2,
    '贰': 2,
    '貳': 2,
    '三': 3,
    '叁': 3,
    '參': 3,
    '四': 4,
    '肆': 4,
    '五': 5,
    '伍': 5,
    '六': 6,
    '陆': 6,
    '陸': 6,
    '七': 7,
    '柒': 7,
    '八': 8,
    '捌': 8,
    '九': 9,
    '玖': 9,
  };
  const units = {'十': 10, '拾': 10, '百': 100, '佰': 100, '千': 1000, '仟': 1000};
  var result = 0, digit = 0;
  if (!token.split('').any(units.containsKey)) {
    return num.tryParse(token.split('').map((c) => digits[c]).join());
  }
  for (final char in token.split('')) {
    if (digits.containsKey(char)) {
      digit = digits[char]!;
    } else {
      result += (digit == 0 ? 1 : digit) * units[char]!;
      digit = 0;
    }
  }
  return result + digit;
}

String chapterKind(Chapter c) =>
    RegExp(
      r'番外|外传|外傳|特別|特别|special|extra',
      caseSensitive: false,
    ).hasMatch('${c.group} ${c.title}')
    ? 'extra'
    : c.title.contains('卷')
    ? 'volume'
    : 'chapter';

class ChapterCandidate {
  const ChapterCandidate(this.chapter, this.score);
  final Chapter chapter;
  final int score;
}

List<ChapterCandidate> matchChapters(Chapter old, Iterable<Chapter> chapters) {
  final name = chapterName(old.title), number = chapterNumber(old.title);
  String part(String text) =>
      RegExp(r'[（(]?([上中下])(?:篇|部|半)?[）)]?\s*$').firstMatch(text)?[1] ?? '';
  final list = chapters.map((chapter) {
    var score = 0;
    if (chapterKind(old) == chapterKind(chapter)) {
      if (name == chapterName(chapter.title)) {
        score = 100;
      } else if (number != null && number == chapterNumber(chapter.title)) {
        final a = part(old.title), b = part(chapter.title);
        score = a.isNotEmpty && b.isNotEmpty && a != b
            ? 0
            : a == b
            ? 80
            : 60;
      }
    }
    return ChapterCandidate(chapter, score);
  }).toList();
  list.sort((a, b) => b.score.compareTo(a.score));
  return list;
}
