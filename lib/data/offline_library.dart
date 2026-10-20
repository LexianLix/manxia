import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../platform/blob_store.dart';
import '../platform/storage.dart';
import 'comic.dart';
import 'dm5_source.dart';
import 'library.dart';

class OfflineLibrary extends ChangeNotifier {
  OfflineLibrary(
    this.library,
    this.source, {
    BlobStore? store,
    http.Client? client,
  }) : _store = store {
    _client = client ?? http.Client();
    instance = this;
  }
  static OfflineLibrary? instance;
  final Library library;
  final Dm5Source source;
  late final http.Client _client;
  BlobStore? _store;
  final List<Map<String, dynamic>> entries = [];
  final Set<String> _running = {};
  final Map<String, Uint8List> _memory = {};
  int _memoryBytes = 0;
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
    for (final e in entries) {
      if (e['status'] == 'downloading') e['status'] = 'paused';
    }
    Dm5Source.offlinePages = pages;
    Dm5Source.offlineDetail = detail;
    ready = true;
    notifyListeners();
    pump();
  }

  String key(String input) => sha256.convert(utf8.encode(input)).toString();
  Future<Uint8List?> read(String key) async {
    final hit = _memory.remove(key);
    if (hit != null) {
      _memory[key] = hit;
      return hit;
    }
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
    notifyListeners();
    await library.prefs.setString('offline.v1', jsonEncode(entries));
  }

  List<Comic> get localBooks => {
    for (final e in entries.where((e) => e['local'] == true))
      (e['comic'] as Map)['path']: Comic.fromJson(
        Map<String, dynamic>.from(e['comic']),
      ),
  }.values.toList();
  List<Chapter> chapters(Comic c) => entries
      .where((e) => e['comic']['path'] == c.path && e['status'] == 'complete')
      .map((e) => Chapter.fromJson(Map<String, dynamic>.from(e['chapter'])))
      .toList();
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

  Future<void> enqueue(Comic comic, Chapter chapter) async {
    if (!ready) throw StateError('离线书库正在初始化');
    if (entries.any((e) => e['chapter']['path'] == chapter.path)) return;
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
    });
    await persist();
    pump();
  }

  void pump() {
    final limit = library.option<int>('downloadParallel', 2).clamp(1, 4);
    for (final e in entries.where((e) => e['status'] == 'queued').toList()) {
      if (_running.contains(e['id'])) continue;
      if (_running.length >= limit) break;
      _running.add(e['id']);
      _run(e);
    }
  }

  Future<void> _run(Map<String, dynamic> e) async {
    e['status'] = 'downloading';
    await persist();
    try {
      if ((e['urls'] as List).isEmpty) {
        e['urls'] = await source.networkPages(e['chapter']['path']);
        e['total'] = (e['urls'] as List).length;
      }
      final urls = List<String>.from(e['urls']);
      final keys = List<String>.from(e['keys']);
      for (var i = e['done'] as int; i < urls.length; i++) {
        if (e['status'] != 'downloading') break;
        final imageKey = key('${e['chapter']['path']}/$i');
        if (await read(imageKey) == null) {
          final url = kIsWeb
              ? Uri.base
                    .resolve('/api/image')
                    .replace(queryParameters: {'url': urls[i]})
              : Uri.parse(urls[i]);
          final response = await _client
              .get(
                url,
                headers: kIsWeb ? null : Dm5Source.headersForImage(urls[i]),
              )
              .timeout(const Duration(seconds: 30));
          if (response.statusCode != 200 ||
              !(response.headers['content-type'] ?? '').startsWith('image/')) {
            throw StateError('第 ${i + 1} 页下载失败');
          }
          if (response.bodyBytes.length > 20 * 1024 * 1024) {
            throw StateError('单张图片超过 20 MB');
          }
          await _store!.write(imageKey, response.bodyBytes);
          e['bytes'] = (e['bytes'] as int) + response.bodyBytes.length;
        }
        if (i >= keys.length) keys.add(imageKey);
        e['keys'] = keys;
        e['done'] = i + 1;
        await persist();
      }
      if (e['done'] == urls.length) {
        try {
          final cover = e['comic']['cover'] as String;
          final coverKey = key('cover:$cover');
          if (await read(coverKey) == null) {
            final target = kIsWeb
                ? Uri.base
                      .resolve('/api/image')
                      .replace(queryParameters: {'url': cover})
                : Uri.parse(cover);
            final response = await _client
                .get(
                  target,
                  headers: kIsWeb ? null : Dm5Source.headersForImage(cover),
                )
                .timeout(const Duration(seconds: 15));
            if (response.statusCode == 200 &&
                (response.headers['content-type'] ?? '').startsWith('image/') &&
                response.bodyBytes.length < 5 * 1024 * 1024) {
              await _store!.write(coverKey, response.bodyBytes);
              e['coverBytes'] = response.bodyBytes.length;
              e['coverKey'] = coverKey;
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
        e['status'] = 'failed';
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
    await persist();
  }

  Future<void> resume(String id) async {
    final e = entries.firstWhere((e) => e['id'] == id);
    e['status'] = 'queued';
    e.remove('error');
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
    // Validation finishes before any persistent state changes.
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
    await library.restore(
      Map<String, dynamic>.from(json['library']),
      restoreOptions: true,
    );
    await persist();
  }
}
