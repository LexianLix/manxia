import 'comic.dart';
import 'dm5_source.dart';
import 'library.dart';
import 'library_features.dart';
import 'reading_progress.dart';

extension FollowUpdates on LibraryFeatures {
  Future<void> recordFollow(ComicDetail detail, {DateTime? at}) async {
    final book = detail.comic;
    if (!favorites.any((b) => b.path == book.path)) return;
    if (detail.chapters.isEmpty) throw SourceException('原站未返回可读取的章节目录');
    final now = (at ?? DateTime.now()).millisecondsSinceEpoch;
    final prior = updates[book.path];
    final paths = detail.chapters.map((c) => c.path).toSet();
    final previous = Set<String>.from(prior?['chapterPaths'] as List? ?? []);
    final fingerprint = detail.chapters.first.path;
    final compatible =
        previous.length <= 1 ||
        paths.length <= 1 ||
        previous.intersection(paths).isNotEmpty;
    final changed =
        prior != null &&
        compatible &&
        (prior['fingerprint'] ?? prior['latest']) != fingerprint;
    final additions = compatible && previous.isNotEmpty
        ? paths.difference(previous)
        : <String>{};
    updates[book.path] = {
      'latest': detail.comic.latest.isNotEmpty
          ? detail.comic.latest
          : detail.chapters.first.title,
      'fingerprint': fingerprint,
      'chapterPaths': paths.toList(),
      'changed': prior?['changed'] == true || changed || additions.isNotEmpty,
      if (prior?['seenFingerprint'] != null)
        'seenFingerprint': prior!['seenFingerprint'],
      if (prior?['readAt'] != null) 'readAt': prior!['readAt'],
      'checkedAt': now,
      'updatedAt': changed || additions.isNotEmpty
          ? now
          : prior?['updatedAt'] ?? 0,
    };
    await rememberChapters(book, detail.chapters);
    await persistFeatures();
  }
}

class FollowChecker {
  static final _running = Expando<Future<int>>();
  static Future<int> check(
    Library library,
    Dm5Source source, {
    bool failedOnly = false,
    bool onlyDue = false,
    bool Function()? active,
  }) {
    final current = _running[library];
    if (current != null) return current;
    final future = _check(library, source, failedOnly, onlyDue, active);
    _running[library] = future;
    return future.whenComplete(() => _running[library] = null);
  }

  static Future<int> _check(
    Library library,
    Dm5Source source,
    bool failedOnly,
    bool onlyDue,
    bool Function()? active,
  ) async {
    var failures = 0;
    final books = library.favorites
        .where(
          (c) =>
              c.sourceId != 'local' &&
              (!failedOnly || library.updates[c.path]?['checkError'] != null) &&
              (!onlyDue ||
                  DateTime.now().millisecondsSinceEpoch -
                          ((library.updates[c.path]?['checkedAt'] as num?)
                                  ?.toInt() ??
                              0) >=
                      const Duration(minutes: 30).inMilliseconds),
        )
        .toList();
    if (books.isEmpty || active?.call() == false) return 0;
    books.sort(
      (a, b) => (library.meta(b)['followPinned'] == true ? 1 : 0).compareTo(
        library.meta(a)['followPinned'] == true ? 1 : 0,
      ),
    );
    for (var i = 0; i < books.length; i += 3) {
      if (active?.call() == false) break;
      await Future.wait(
        books.skip(i).take(3).map((book) async {
          try {
            final detail = await source.detail(book);
            if (active?.call() != false && library.contains(book)) {
              await library.recordFollow(detail);
            }
          } catch (error) {
            failures++;
            if (active?.call() != false && library.contains(book)) {
              library.updates[book.path] = {
                ...?library.updates[book.path],
                'checkError': error.toString(),
                'checkedAt': DateTime.now().millisecondsSinceEpoch,
              };
            }
          }
        }),
      );
    }
    if (active?.call() != false) await library.persistFeatures();
    return failures;
  }
}
