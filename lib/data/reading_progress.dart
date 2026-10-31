import 'comic.dart';
import 'library_features.dart';

extension ReadingProgress on LibraryFeatures {
  bool chapterRead(Comic comic, String path) =>
      (meta(comic)['readChapters'] as Map?)?[path] == true;

  int readChapterCount(Comic comic) {
    final marks = meta(comic)['readChapters'] as Map? ?? {};
    final paths = meta(comic)['chapterPaths'] as List?;
    return paths == null
        ? marks.values.where((v) => v == true).length
        : paths.where((p) => marks[p] == true).length;
  }

  int? chapterCount(Comic comic) {
    final value = meta(comic)['chapterCount'];
    return value is num && value.isFinite && value >= 0 ? value.toInt() : null;
  }

  bool archived(Comic comic) => meta(comic)['archived'] == true;

  Future<void> rememberChapters(Comic comic, Iterable<Chapter> chapters) async {
    final paths = chapters.map((c) => c.path).toSet().toList();
    if (paths.isEmpty) return;
    final previous = List<String>.from(
      meta(comic)['chapterPaths'] as List? ?? [],
    );
    if (previous.length == paths.length && previous.every(paths.contains)) {
      return;
    }
    final revived =
        meta(comic)['autoArchived'] == true &&
        paths.any((p) => !chapterRead(comic, p));
    await setMeta(comic, {
      'chapterCount': paths.length,
      'chapterPaths': paths,
      if (revived) 'archived': false,
      if (revived) 'autoArchived': false,
      if (revived) 'status': '在读',
    });
  }

  Future<void> setChapterRead(Comic comic, String path, bool read) async {
    final marks = Map<String, dynamic>.from(
      meta(comic)['readChapters'] as Map? ?? {},
    );
    marks[path] = read;
    final paths = List<String>.from(meta(comic)['chapterPaths'] as List? ?? []);
    final complete = paths.isNotEmpty && paths.every((p) => marks[p] == true);
    await setMeta(comic, {
      'readChapters': marks,
      if (complete) 'status': '已读',
      if (!read && meta(comic)['status'] == '已读') 'status': '在读',
      if (complete && option<bool>('autoArchiveRead', false)) 'archived': true,
      if (complete && option<bool>('autoArchiveRead', false))
        'autoArchived': true,
      if (!read) 'archived': false,
      if (!read) 'autoArchived': false,
    });
  }

  Future<void> setArchived(Comic comic, bool value) =>
      setMeta(comic, {'archived': value, 'autoArchived': false});
}
