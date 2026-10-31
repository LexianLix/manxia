import 'dart:convert';
import 'dart:async';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../platform/blob_store.dart';
import '../platform/storage.dart';
import 'comic.dart';
import 'dm5_source.dart';
import 'library.dart';
import 'chapter_links.dart';
import '../platform/network_monitor.dart';

class OfflineCapacityException implements Exception {
  const OfflineCapacityException();
  @override
  String toString() => '离线空间已达到上限，任务已暂停；请清理空间或提高容量上限后继续。';
}

class OfflineLibrary extends ChangeNotifier {
  OfflineLibrary(
    this.library,
    this.source, {
    BlobStore? store,
    http.Client? client,
    NetworkMonitor? network,
  }) : _store = store {
    _client = client ?? http.Client();
    this.network = network ?? NetworkMonitor();
    instance = this;
  }
  static OfflineLibrary? instance;
  final Library library;
  final Dm5Source source;
  late final http.Client _client;
  late final NetworkMonitor network;
  final _aborts = <String, Completer<void>>{};
  bool _closed = false;
  (NetworkInfo, bool)? _lastPolicy;
  bool get networkAllowed =>
      network.value.permits(library.option<bool>('downloadWifiOnly', false));
  bool allowed(Map<String, dynamic> entry) => network.value.permits(
    entry['automatic'] == true ||
        library.option<bool>('downloadWifiOnly', false),
  );
  void pauseForNetwork(Map<String, dynamic> entry) {
    entry['status'] = 'paused';
    entry['pauseReason'] = 'network';
    entry['error'] = '当前网络不符合下载设置，已暂停并保留完成页。';
    final abort = _aborts[entry['id']];
    if (abort != null && !abort.isCompleted) abort.complete();
  }

  void networkChanged() {
    if (!ready) return;
    final policy = (
      network.value,
      library.option<bool>('downloadWifiOnly', false),
    );
    if (policy == _lastPolicy) return;
    _lastPolicy = policy;
    for (final e in entries) {
      if (!allowed(e) && ['queued', 'downloading'].contains(e['status'])) {
        pauseForNetwork(e);
      } else if (allowed(e) &&
          library.option<bool>('resumeDownloadsOnNetwork', true) &&
          e['status'] == 'paused' &&
          e['pauseReason'] == 'network') {
        e['status'] = 'queued';
        e.remove('pauseReason');
        e.remove('error');
      }
    }
    unawaited(persist());
    pump();
  }

  Future<http.Response> requestImage(
    String id,
    String image, {
    int timeout = 30,
  }) async {
    final abort = Completer<void>();
    _aborts[id] = abort;
    final url = kIsWeb
        ? Uri.base
              .resolve('/api/image')
              .replace(queryParameters: {'url': image})
        : Uri.parse(image);
    final request = http.AbortableRequest(
      'GET',
      url,
      abortTrigger: abort.future,
    );
    if (!kIsWeb) request.headers.addAll(Dm5Source.headersForImage(image));
    try {
      return await (() async => http.Response.fromStream(
        await _client.send(request),
      ))().timeout(Duration(seconds: timeout));
    } on TimeoutException {
      if (!abort.isCompleted) abort.complete();
      rethrow;
    } finally {
      if (identical(_aborts[id], abort)) _aborts.remove(id);
    }
  }

  BlobStore? _store;
  final List<Map<String, dynamic>> entries = [];
  final Set<String> _running = {};
  final Map<String, List<String>> chapterCatalogs = {};
  final Map<String, Uint8List> _memory = {};
  int _memoryBytes = 0;
  int _reservedBytes = 0;
  int get capacityBytes =>
      library.option<int>('offlineLimitMb', 0).clamp(0, 102400) * 1024 * 1024;
  bool get nearCapacity => capacityBytes > 0 && bytes >= capacityBytes * .9;
  int reclaimableBytes(Iterable<String> ids) {
    final selected = entries.where((e) => ids.contains(e['id'])).toList();
    var size = selected.fold<int>(0, (n, e) => n + (e['bytes'] as int? ?? 0));
    final covers = <String, int>{
      for (final e in selected)
        if (e['coverKey'] is String)
          e['coverKey']: e['coverBytes'] as int? ?? 0,
    };
    for (final cover in covers.entries) {
      if (!entries.any(
        (e) => !ids.contains(e['id']) && e['coverKey'] == cover.key,
      )) {
        size += cover.value;
      }
    }
    return size;
  }

  bool ready = false;
  Future<void> initialize() async {
    _store ??= await createBlobStore();
    try {
      entries.addAll(
        (jsonDecode(library.prefs.getString('offline.v1') ?? '[]') as List).map(
          (e) => Map<String, dynamic>.from(e),
        ),
      );
    } catch (_) {}
    try {
      final saved =
          jsonDecode(library.prefs.getString('offline.catalogs.v1') ?? '{}')
              as Map;
      chapterCatalogs.addAll(
        saved.map((k, v) => MapEntry(k.toString(), List<String>.from(v))),
      );
    } catch (_) {}
    for (final e in entries) {
      if (e['status'] == 'downloading') {
        e['status'] = library.option<bool>('resumeDownloadsOnLaunch', false)
            ? 'queued'
            : 'paused';
      }
      if (e['status'] == 'paused' &&
          e['pauseReason'] == 'network' &&
          !library.option<bool>('resumeDownloadsOnLaunch', false)) {
        e['pauseReason'] = 'restart';
      } else if (e['status'] == 'paused' && e['pauseReason'] == 'network') {
        e['status'] = 'queued';
      }
    }
    await network.start();
    _lastPolicy = (
      network.value,
      library.option<bool>('downloadWifiOnly', false),
    );
    network.addListener(networkChanged);
    library.addListener(networkChanged);
    Dm5Source.offlinePages = pages;
    Dm5Source.offlineDetail = detail;
    ready = true;
    notifyListeners();
    pump();
  }

  String key(String input) => sha256.convert(utf8.encode(input)).toString();

  /// Read only the existing bounded memory cache, without starting disk I/O.
  /// Flights can reuse a cover on their very first painted frame.
  Uint8List? peek(String key) {
    final hit = _memory.remove(key);
    if (hit != null) {
      _memory[key] = hit;
    }
    return hit;
  }

  Future<Uint8List?> read(String key) async {
    final hit = peek(key);
    if (hit != null) return hit;
    final data = await _store?.read(key);
    if (data != null && data.length < 32 * 1024 * 1024) {
      final previous = _memory.remove(key);
      if (previous != null) _memoryBytes -= previous.length;
      _memory[key] = data;
      _memoryBytes += data.length;
      while (_memoryBytes > 32 * 1024 * 1024 || _memory.length > 50) {
        _memoryBytes -= _memory.remove(_memory.keys.first)!.length;
      }
    }
    return data;
  }

  Future<Uint8List?> cachedCover(String url) async {
    final e = entries
        .where((e) => e['comic']['cover'] == url && e['coverKey'] != null)
        .firstOrNull;
    return e == null ? null : read(e['coverKey']);
  }

  int get bytes =>
      entries.fold<int>(0, (sum, e) => sum + (e['bytes'] as int? ?? 0)) +
      {
        for (final e in entries.where((e) => e['coverKey'] != null))
          e['coverKey']: e['coverBytes'] as int? ?? 0,
      }.values.fold<int>(0, (n, b) => n + b);
  Future<void> persist() async {
    if (_closed) return;
    notifyListeners();
    await library.prefs.setString('offline.v1', jsonEncode(entries));
  }

  List<Comic> get localBooks => {
    for (final e in entries.where((e) => e['local'] == true))
      (e['comic'] as Map)['path']: Comic.fromJson(
        Map<String, dynamic>.from(e['comic']),
      ),
  }.values.toList();
  List<Chapter> chapters(Comic c) {
    final list = entries
        .where((e) => e['comic']['path'] == c.path && e['status'] == 'complete')
        .map((e) => Chapter.fromJson(Map<String, dynamic>.from(e['chapter'])))
        .toList();
    final order =
        chapterCatalogs[c.path] ??
        Dm5Source.chapterCatalogs[c.path]?.map((c) => c.path).toList();
    if (order != null) {
      final rank = {for (final e in order.indexed) e.$2: e.$1};
      list.sort(
        (a, b) => (rank[a.path] ?? order.length).compareTo(
          rank[b.path] ?? order.length,
        ),
      );
    }
    return list;
  }

  Future<List<String>?> pages(String path) async {
    final entry = entries
        .where((e) => e['chapter']['path'] == path && e['status'] == 'complete')
        .firstOrNull;
    return entry == null
        ? null
        : List<String>.from(entry['keys']).map((k) => 'offline:$k').toList();
  }

  Future<ComicDetail?> detail(Comic c) async {
    final list = chapters(c);
    return list.isEmpty ? null : ComicDetail(c, list);
  }

  Future<void> enqueue(
    Comic comic,
    Chapter chapter, {
    bool automatic = false,
  }) async {
    if (!ready) throw StateError('离线书库正在初始化');
    if (entries.any((e) => e['chapter']['path'] == chapter.path)) return;
    final canonical = Dm5Source.chapterCatalogs[comic.path]
        ?.map((c) => c.path)
        .toList();
    if (canonical != null &&
        !listEquals(canonical, chapterCatalogs[comic.path])) {
      chapterCatalogs[comic.path] = canonical;
      await library.prefs.setString(
        'offline.catalogs.v1',
        jsonEncode(chapterCatalogs),
      );
    }
    entries.add({
      'id': key(chapter.path),
      'comic': comic.toJson(),
      'chapter': chapter.toJson(),
      'status': 'queued',
      'urls': <String>[],
      'keys': <String>[],
      'done': 0,
      'total': 0,
      'bytes': 0,
      'local': false,
      'automatic': automatic,
    });
    await persist();
    pump();
  }

  Future<void> prepareNext(Comic comic, Iterable<Chapter> wanted) async {
    final list = wanted.take(10).toList(),
        paths = wanted.take(10).map((c) => c.path).toSet();
    for (final e
        in entries
            .where(
              (e) =>
                  e['comic']['path'] == comic.path &&
                  e['automatic'] == true &&
                  !paths.contains(e['chapter']['path']) &&
                  e['done'] == 0 &&
                  !_running.contains(e['id']),
            )
            .toList()) {
      entries.remove(e);
    }
    for (final chapter in list) {
      if (entries.any((e) => e['chapter']['path'] == chapter.path)) continue;
      await enqueue(comic, chapter, automatic: true);
    }
    await persist();
  }

  void pump() {
    if (_closed) return;
    final limit = library.option<int>('downloadParallel', 2).clamp(1, 4);
    for (final e in entries.where((e) => e['status'] == 'queued').toList()) {
      if (!allowed(e)) {
        pauseForNetwork(e);
        unawaited(persist());
        continue;
      }
      if (_running.contains(e['id'])) continue;
      if (_running.length >= limit) break;
      _running.add(e['id']);
      _run(e);
    }
  }

  Future<void> _run(Map<String, dynamic> e) async {
    e['status'] = 'downloading';
    e.remove('pauseReason');
    await persist();
    try {
      if ((e['urls'] as List).isEmpty) {
        e['urls'] = await source.networkPages(e['chapter']['path']);
        e['total'] = (e['urls'] as List).length;
      }
      if ((e['urls'] as List).isEmpty) throw StateError('章节没有返回图片，请重新读取目录后重试。');
      var urls = List<String>.from(e['urls']);
      var refreshed = false;
      final keys = List<String>.from(e['keys']);
      for (var i = e['done'] as int; i < urls.length; i++) {
        if (e['status'] != 'downloading' || !allowed(e)) break;
        final imageKey = key('${e['chapter']['path']}/$i');
        if (await read(imageKey) == null) {
          final response = await requestImage(e['id'], urls[i]);
          if (!allowed(e) || e['pauseReason'] == 'network') break;
          if (response.statusCode != 200 ||
              !(response.headers['content-type'] ?? '').startsWith('image/')) {
            if (!refreshed && expiredImageStatus(response.statusCode)) {
              refreshed = true;
              urls = await refreshChapterLinks(
                source,
                e['chapter']['path'],
                urls,
                completed: i,
              );
              e['urls'] = urls;
              await persist();
              i--;
              continue;
            }
            throw StateError(
              response.statusCode == 200
                  ? '第 ${i + 1} 页没有返回图片，请核对书源后重试。'
                  : '第 ${i + 1} 页下载失败（HTTP ${response.statusCode}），可稍后重试。',
            );
          }
          if (response.bodyBytes.length > 20 * 1024 * 1024) {
            throw StateError('单张图片超过 20 MB');
          }
          final size = response.bodyBytes.length;
          if (capacityBytes > 0 &&
              bytes + _reservedBytes + size > capacityBytes) {
            throw const OfflineCapacityException();
          }
          _reservedBytes += size;
          try {
            await _store!.write(imageKey, response.bodyBytes);
            e['bytes'] = (e['bytes'] as int) + size;
          } finally {
            _reservedBytes -= size;
          }
        }
        if (i >= keys.length) keys.add(imageKey);
        e['keys'] = keys;
        e['done'] = i + 1;
        await persist();
      }
      if (e['done'] == urls.length && e['status'] == 'downloading') {
        try {
          final cover = e['comic']['cover'] as String;
          final coverKey = key('cover:$cover');
          if (await read(coverKey) == null) {
            if (!allowed(e)) throw StateError('Network changed');
            final response = await requestImage(e['id'], cover, timeout: 15);
            if (response.statusCode == 200 &&
                (response.headers['content-type'] ?? '').startsWith('image/') &&
                response.bodyBytes.length < 5 * 1024 * 1024) {
              final size = response.bodyBytes.length;
              if (capacityBytes == 0 ||
                  bytes + _reservedBytes + size <= capacityBytes) {
                _reservedBytes += size;
                try {
                  await _store!.write(coverKey, response.bodyBytes);
                  e['coverBytes'] = size;
                  e['coverKey'] = coverKey;
                } finally {
                  _reservedBytes -= size;
                }
              }
            }
          } else {
            e['coverKey'] = coverKey;
            e['coverBytes'] = (await read(coverKey))!.length;
          }
        } catch (_) {
          /* A missing thumbnail does not invalidate downloaded pages. */
        }
        if (e['status'] == 'downloading') e['status'] = 'complete';
      }
    } catch (error) {
      if (e['status'] == 'downloading') {
        e['status'] = error is OfflineCapacityException ? 'paused' : 'failed';
        e['error'] = error.toString();
      }
    } finally {
      _running.remove(e['id']);
      await persist();
      pump();
    }
  }

  Future<void> pause(String id) async {
    final e = entries.firstWhere((e) => e['id'] == id);
    e['status'] = 'paused';
    e['pauseReason'] = 'manual';
    await persist();
  }

  bool isRunning(String id) => _running.contains(id);

  /// Only queued order changes; the current image may finish normally.
  Future<void> prioritize(String id) async {
    final index = entries.indexWhere((e) => e['id'] == id);
    if (index < 0) return;
    final entry = entries[index];
    if (entry['local'] == true || entry['status'] == 'complete') return;
    entries.removeAt(index);
    entries.insert(0, entry);
    entry['status'] = _running.contains(id) ? 'downloading' : 'queued';
    entry.remove('error');
    await persist();
    pump();
  }

  Future<void> retryFailed() async {
    for (final e in entries.where((e) => e['status'] == 'failed')) {
      e['status'] = 'queued';
      e.remove('error');
    }
    await persist();
    pump();
  }

  Future<void> pauseAll() async {
    for (final e in entries.where(
      (e) => ['queued', 'downloading'].contains(e['status']),
    )) {
      e['status'] = 'paused';
      e['pauseReason'] = 'manual';
    }
    await persist();
  }

  Future<void> resume(String id) async {
    final e = entries.firstWhere((e) => e['id'] == id);
    e['status'] = 'queued';
    e.remove('error');
    e.remove('pauseReason');
    await persist();
    pump();
  }

  Future<void> remove(String id) async {
    final e = entries.firstWhere((e) => e['id'] == id);
    if (_running.contains(id)) throw StateError('请先暂停任务，等待当前图片完成后再删除。');
    for (final k in e['keys'] as List) {
      await _store!.delete(k);
      final memory = _memory.remove(k);
      if (memory != null) _memoryBytes -= memory.length;
    }
    final coverKey = e['coverKey'];
    if (coverKey != null &&
        !entries.any((v) => v != e && v['coverKey'] == coverKey)) {
      await _store!.delete(coverKey);
      final memory = _memory.remove(coverKey);
      if (memory != null) _memoryBytes -= memory.length;
    }
    entries.remove(e);
    await persist();
  }

  Future<void> removeComic(String path) async {
    final selected = entries.where((e) => e['comic']['path'] == path).toList();
    if (selected.any((e) => _running.contains(e['id']))) {
      throw StateError('请先暂停这本漫画的任务，等待当前图片完成。');
    }
    for (final e in selected) {
      await remove(e['id']);
    }
  }

  Future<void> removeMany(Iterable<String> ids) async {
    final selected = entries.where((e) => ids.contains(e['id'])).toList();
    if (selected.any((e) => _running.contains(e['id']))) {
      throw StateError('选中任务仍在运行，请暂停并等待当前图片完成。');
    }
    for (final entry in selected) {
      await remove(entry['id']);
    }
  }

  @override
  void dispose() {
    _closed = true;
    library.removeListener(networkChanged);
    network.removeListener(networkChanged);
    for (final abort in _aborts.values) {
      if (!abort.isCompleted) abort.complete();
    }
    network.dispose();
    _client.close();
    super.dispose();
  }

  Future<Comic> importImages(
    String name,
    List<({String name, Uint8List bytes})> images,
  ) async {
    if (images.isEmpty) throw const FormatException('没有找到支持的漫画图片。');
    images.sort((a, b) => natural(a.name).compareTo(natural(b.name)));
    final id = key('$name/${DateTime.now().microsecondsSinceEpoch}');
    final keys = <String>[];
    var length = 0;
    for (var i = 0; i < images.length; i++) {
      final k = key('$id/$i');
      await _store!.write(k, images[i].bytes);
      keys.add(k);
      length += images[i].bytes.length;
    }
    final comic = Comic(
      path: 'local:$id',
      title: name,
      cover: 'offline:${keys.first}',
      sourceId: 'local',
    );
    final chapter = Chapter('local:$id/1', '本地漫画', group: '本地');
    entries.add({
      'id': id,
      'comic': comic.toJson(),
      'chapter': chapter.toJson(),
      'status': 'complete',
      'keys': keys,
      'urls': <String>[],
      'done': keys.length,
      'total': keys.length,
      'bytes': length,
      'local': true,
    });
    await persist();
    if (!library.contains(comic)) await library.toggle(comic);
    return comic;
  }

  static String natural(String name) => name.toLowerCase().replaceAllMapped(
    RegExp(r'\d+'),
    (m) => m[0]!.padLeft(12, '0'),
  );
  static bool isImage(String name) => RegExp(
    r'\.(jpe?g|png|webp|gif|bmp)$',
    caseSensitive: false,
  ).hasMatch(name);
  Future<Comic> importZip(String name, Uint8List bytes) async {
    final archive = ZipDecoder().decodeBytes(bytes);
    final images = <({String name, Uint8List bytes})>[];
    var size = 0;
    for (final f in archive.files.where((f) => f.isFile && isImage(f.name))) {
      size += f.size;
      if (size > 512 * 1024 * 1024 || images.length >= 5000) {
        throw const FormatException('解压内容超过本地导入上限。');
      }
      images.add((name: f.name, bytes: Uint8List.fromList(f.content)));
    }
    return importImages(
      name.replaceFirst(RegExp(r'\.(cbz|zip)$', caseSensitive: false), ''),
      images,
    );
  }

  Future<Uint8List> exportChapter(Map<String, dynamic> e) async {
    final archive = Archive();
    final keys = List<String>.from(e['keys']);
    for (var i = 0; i < keys.length; i++) {
      final bytes = await read(keys[i]);
      if (bytes != null) {
        archive.addFile(
          ArchiveFile(
            '${(i + 1).toString().padLeft(4, '0')}.${imageExtension(bytes)}',
            bytes.length,
            bytes,
          ),
        );
      }
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  static String imageExtension(Uint8List bytes) {
    if (bytes.length > 4 && bytes[0] == 137 && bytes[1] == 80) return 'png';
    if (bytes.length > 4 && bytes[0] == 71 && bytes[1] == 73) return 'gif';
    if (bytes.length > 12 && String.fromCharCodes(bytes.take(4)) == 'RIFF') {
      return 'webp';
    }
    if (bytes.length > 2 && bytes[0] == 66 && bytes[1] == 77) return 'bmp';
    return 'jpg';
  }

  Future<Uint8List> exportBundle() async {
    final archive = Archive();
    final complete = entries.where((e) => e['status'] == 'complete').toList();
    final sums = <String, String>{};
    var size = 0;
    for (final k
        in complete
            .expand(
              (e) => [
                ...List<String>.from(e['keys']),
                if (e['coverKey'] != null) e['coverKey'] as String,
              ],
            )
            .toSet()) {
      final data = await read(k);
      if (data == null) throw StateError('离线图片缺失，请先重新下载对应章节。');
      size += data.length;
      if (size > 512 * 1024 * 1024) {
        throw StateError('完整书库导出上限为 512 MB，请分章导出 CBZ。');
      }
      sums[k] = sha256.convert(data).toString();
      archive.addFile(ArchiveFile('pages/$k', data.length, data));
    }
    final manifest = utf8.encode(
      jsonEncode({
        'format': 'manxia-offline',
        'schema': 1,
        'library': library.backup(),
        'entries': complete,
        'chapterCatalogs': chapterCatalogs,
        'sha256': sums,
      }),
    );
    archive.addFile(ArchiveFile('manifest.json', manifest.length, manifest));
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  Future<void> importBundle(Uint8List bytes) async {
    final archive = ZipDecoder().decodeBytes(bytes);
    if (archive.files.fold<int>(0, (n, f) => n + f.size) > 512 * 1024 * 1024) {
      throw const FormatException('书库备份超过 512 MB。');
    }
    final manifest = archive.findFile('manifest.json');
    if (manifest == null) throw const FormatException('找不到漫匣书库清单。');
    final json = jsonDecode(utf8.decode(manifest.content)) as Map;
    if (json['format'] != 'manxia-offline' || json['schema'] != 1) {
      throw const FormatException('不支持的书库备份版本。');
    }
    final restoredLibrary = Map<String, dynamic>.from(json['library']);
    if (restoredLibrary['format'] != 'manxia' ||
        (restoredLibrary['schema'] as num? ?? 0) > 2) {
      throw const FormatException('书库资料版本高于当前应用，请先升级应用。');
    }
    final restoredCatalogs = (json['chapterCatalogs'] as Map? ?? {}).map(
      (k, v) => MapEntry(k.toString(), List<String>.from(v)),
    );
    final sums = Map<String, String>.from(json['sha256']);
    final incoming = (json['entries'] as List)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    for (final k in sums.keys) {
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(k)) {
        throw const FormatException('非法图片索引。');
      }
      final file = archive.findFile('pages/$k');
      if (file == null || sha256.convert(file.content).toString() != sums[k]) {
        throw const FormatException('图片校验失败，备份可能损坏。');
      }
    }
    for (final e in incoming) {
      if (e['status'] != 'complete' ||
          (e['keys'] as List).any((k) => !sums.containsKey(k))) {
        throw const FormatException('章节索引不完整。');
      }
    }
    // Image integrity and format versions are checked before writing files.
    for (final k in sums.keys) {
      await _store!.write(
        k,
        Uint8List.fromList(archive.findFile('pages/$k')!.content),
      );
    }
    for (final e in incoming) {
      entries.removeWhere((v) => v['id'] == e['id']);
      entries.add(e);
    }
    await library.restore(restoredLibrary, restoreOptions: true);
    for (final e in restoredCatalogs.entries) {
      final incoming = e.value;
      final existing = chapterCatalogs[e.key] ?? [];
      if (incoming.length >= existing.length) chapterCatalogs[e.key] = incoming;
    }
    await library.prefs.setString(
      'offline.catalogs.v1',
      jsonEncode(chapterCatalogs),
    );
    await persist();
  }
}
