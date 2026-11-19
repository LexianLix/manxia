import 'comic.dart';

class ReadingQueue {
  List<Comic> _books = const [];
  List<Comic> get books => _books;
  int _updatedAt = 0;

  static (String, String) identity(Comic book) => (book.sourceId, book.path);
  int indexOf(Comic book) =>
      _books.indexWhere((candidate) => identity(candidate) == identity(book));
  bool contains(Comic book) => indexOf(book) >= 0;

  Comic? nextAfter(Comic book) {
    if (_books.isEmpty) return null;
    final index = indexOf(book);
    if (index < 0) return _books.first;
    if (_books.length == 1) return null;
    return _books[(index + 1) % _books.length];
  }

  bool setQueued(Comic book, bool queued) {
    if (queued == contains(book)) return false;
    return _replace([
      ..._books.where((candidate) => identity(candidate) != identity(book)),
      if (queued) book,
    ]);
  }

  bool move(Comic book, int to) {
    final from = indexOf(book);
    if (from < 0 || to < 0 || to >= _books.length || from == to) return false;
    final reordered = _books.toList();
    reordered.insert(to, reordered.removeAt(from));
    return _replace(reordered);
  }

  bool _replace(List<Comic> books) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _updatedAt = now > _updatedAt ? now : _updatedAt + 1;
    _books = List.unmodifiable(books);
    return true;
  }

  Map<String, dynamic> toJson() => {
    'updatedAt': _updatedAt,
    'books': _books.map((book) => book.toJson()).toList(),
  };

  void merge(Object? value) {
    if (value == null) return;
    if (value is! Map ||
        value['updatedAt'] is! int ||
        value['books'] is! List) {
      throw const FormatException('待读队列格式错误');
    }
    final updatedAt = value['updatedAt'] as int;
    if (updatedAt <= _updatedAt) return;
    final entries = <(String, String), Comic>{};
    for (final item in value['books'] as List) {
      final book = Comic.fromJson(Map<String, dynamic>.from(item));
      if (book.path.trim().isEmpty || book.title.trim().isEmpty) {
        throw const FormatException('待读漫画格式错误');
      }
      entries.putIfAbsent(identity(book), () => book);
    }
    _books = List.unmodifiable(entries.values);
    _updatedAt = updatedAt;
  }
}
