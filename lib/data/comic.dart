import 'dart:convert';

class Comic {
  const Comic({
    required this.path,
    required this.title,
    required this.cover,
    this.author = '',
    this.latest = '',
    this.description = '',
    this.tags = const [],
    this.sourceId = 'dm5',
  });
  final String path, title, cover, author, latest, description;
  final List<String> tags;
  final String sourceId;
  Map<String, dynamic> toJson() => {
    'path': path,
    'title': title,
    'cover': cover,
    'author': author,
    'latest': latest,
    'description': description,
    'tags': tags,
    'sourceId': sourceId,
  };
  factory Comic.fromJson(Map<String, dynamic> j) => Comic(
    path: j['path'],
    title: j['title'],
    cover: j['cover'],
    author: j['author'] ?? '',
    latest: j['latest'] ?? '',
    description: j['description'] ?? '',
    tags: List<String>.from(j['tags'] ?? []),
    sourceId: j['sourceId'] ?? 'dm5',
  );
  static List<Comic> decode(String json) => (jsonDecode(json) as List)
      .map((j) => Comic.fromJson(j as Map<String, dynamic>))
      .toList();
}

class Chapter {
  const Chapter(this.path, this.title, {this.group = '连载'});
  final String path, title, group;
  Map<String, dynamic> toJson() => {
    'path': path,
    'title': title,
    'group': group,
  };
  factory Chapter.fromJson(Map<String, dynamic> j) =>
      Chapter(j['path'], j['title'], group: j['group'] ?? '连载');
}

class ComicDetail {
  const ComicDetail(this.comic, this.chapters);
  final Comic comic;
  final List<Chapter> chapters;
}

class ReadingRecord {
  const ReadingRecord({
    required this.comic,
    required this.chapterPath,
    required this.chapterTitle,
    required this.page,
    required this.total,
    required this.updatedAt,
    this.position = 0,
  });
  final Comic comic;
  final String chapterPath, chapterTitle;
  final int page, total, updatedAt;
  final double position;
  Map<String, dynamic> toJson() => {
    'comic': comic.toJson(),
    'chapterPath': chapterPath,
    'chapterTitle': chapterTitle,
    'page': page,
    'total': total,
    'updatedAt': updatedAt,
    'position': position,
  };
  factory ReadingRecord.fromJson(Map<String, dynamic> j) => ReadingRecord(
    comic: Comic.fromJson(j['comic']),
    chapterPath: j['chapterPath'],
    chapterTitle: j['chapterTitle'],
    page: j['page'],
    total: j['total'],
    updatedAt: j['updatedAt'],
    position: (j['position'] as num?)?.toDouble() ?? 0,
  );
}
