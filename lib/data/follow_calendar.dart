import 'comic.dart';
import 'dm5_source.dart';
import 'library.dart';
import 'library_features.dart';
import 'reading_progress.dart';

class FollowEvent {
  const FollowEvent(this.comic, this.value);
  final Comic comic;
  final Map<String, dynamic> value;
  String get id => value['id'] as String;
  DateTime get observedAt =>
      DateTime.fromMillisecondsSinceEpoch((value['observedAt'] as num).toInt());
  List<Chapter> get chapters => (value['chapters'] as List)
      .map((e) => Chapter.fromJson(Map<String, dynamic>.from(e)))
      .toList();
}

extension FollowCalendar on LibraryFeatures {
  List<Map<String, dynamic>> followJournal(Comic book) {
    final raw = meta(book)['followEvents'];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .where((e) {
          final time = e['observedAt'], chapters = e['chapters'];
          return e['id'] is String &&
              time is num &&
              time.isFinite &&
              time >= 0 &&
              time <= 8640000000000000 &&
              chapters is List &&
              chapters.isNotEmpty &&
              chapters.every(
                (c) => c is Map && c['path'] is String && c['title'] is String,
              );
        })
        .take(120)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  List<FollowEvent> get followEvents {
    final result = <FollowEvent>[];
    for (final book in favorites) {
      for (final value in followJournal(book)) {
        result.add(FollowEvent(book, value));
      }
    }
    return result..sort((a, b) => b.observedAt.compareTo(a.observedAt));
  }

  bool eventUnread(FollowEvent event) =>
      event.chapters.any((c) => !chapterRead(event.comic, c.path));

  /// First success establishes a baseline. Only subsequent new chapter paths
  /// become dated observations; checking time is never a publication date.
  Future<void> recordFollow(ComicDetail detail, {DateTime? at}) async {
    final book = detail.comic;
    if (!favorites.any((b) => b.path == book.path)) return;
    if (detail.chapters.isEmpty) throw SourceException('原站未返回可读取的章节目录');
    final now = (at ?? DateTime.now()).millisecondsSinceEpoch;
    final prior = updates[book.path];
    final paths = detail.chapters.map((c) => c.path).toSet();
    final previous = Set<String>.from(prior?['chapterPaths'] as List? ?? []);
    final fingerprint = detail.chapters.first.path;
    final changed =
        prior != null &&
        (prior['fingerprint'] ?? prior['latest']) != fingerprint;
    var additions = previous.isNotEmpty
        ? detail.chapters.where((c) => !previous.contains(c.path)).toList()
        : changed
        ? [detail.chapters.first]
        : <Chapter>[];
    if (previous.length > 1 &&
        paths.length > 1 &&
        previous.intersection(paths).isEmpty) {
      additions = [];
    }
    final events = followJournal(book);
    final known = <String>{
      for (final e in events)
        for (final c in e['chapters'] as List? ?? []) c['path'] as String,
    };
    additions = additions.where((c) => !known.contains(c.path)).toList();
    if (additions.isNotEmpty) {
      events.insert(0, {
        'id': '$now:$fingerprint',
        'observedAt': now,
        'chapters': additions.map((c) => c.toJson()).toList(),
      });
      metadata[book.path] = {
        ...meta(book),
        'followEvents': events.take(120).toList(),
        'updatedAt': now,
      };
    }
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
      'updatedAt': additions.isNotEmpty ? now : prior?['updatedAt'] ?? 0,
    };
    await rememberChapters(book, detail.chapters);
    await persistFeatures();
  }

  Future<void> markEventRead(FollowEvent event, bool read) async {
    for (final chapter in event.chapters) {
      await setChapterRead(event.comic, chapter.path, read);
    }
    if (read &&
        !followEvents.any(
          (e) => e.comic.path == event.comic.path && eventUnread(e),
        )) {
      await markUpdatesRead([event.comic.path]);
    }
  }
}

class FollowChecker {
  static final _running = Expando<Future<int>>();
  static Future<int> check(
    Library library,
    Dm5Source source, {
    bool failedOnly = false,
    bool Function()? active,
  }) {
    final current = _running[library];
    if (current != null) return current;
    final future = _check(library, source, failedOnly, active);
    _running[library] = future;
    return future.whenComplete(() => _running[library] = null);
  }

  static Future<int> _check(
    Library library,
    Dm5Source source,
    bool failedOnly,
    bool Function()? active,
  ) async {
    var failures = 0;
    final books = library.favorites
        .where(
          (c) =>
              c.sourceId != 'local' &&
              (!failedOnly || library.updates[c.path]?['checkError'] != null),
        )
        .toList();
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
    await library.persistFeatures();
    return failures;
  }
}
