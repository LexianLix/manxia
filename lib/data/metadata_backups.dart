import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import '../platform/blob_store.dart';
import '../platform/storage.dart';
import 'backup_preview.dart';
import 'library.dart';

class MetadataBackups extends ChangeNotifier {
  MetadataBackups(this.library, this.store) {
    try {
      entries.addAll(
        (jsonDecode(library.prefs.getString('metadata.backups.v1') ?? '[]')
                as List)
            .map((e) => Map<String, dynamic>.from(e))
            .where(
              (e) =>
                  e['key'] is String &&
                  RegExp(r'^[a-f0-9]{64}$').hasMatch(e['key']) &&
                  e['at'] is int,
            ),
      );
    } catch (_) {
      entries.clear();
    }
    library.addListener(changed);
    changed();
  }
  static Future<MetadataBackups> open(Library library) async {
    if (library.backups != null) return library.backups!;
    final store = await createBackupStore().timeout(const Duration(seconds: 5));
    return library.backups ??= MetadataBackups(library, store);
  }

  final Library library;
  final BlobStore store;
  final entries = <Map<String, dynamic>>[];
  Timer? timer;
  Future<void>? running;
  String? error;
  bool disposed = false;
  bool get enabled => library.option<bool>('autoBackupEnabled', true);
  int get interval => library.option<int>('autoBackupHours', 24).clamp(1, 168);
  bool get due =>
      entries.isEmpty ||
      DateTime.now().millisecondsSinceEpoch - (entries.first['at'] as int) >=
          Duration(hours: interval).inMilliseconds;
  void changed() {
    if (!enabled || !due || timer != null || running != null || disposed) {
      return;
    }
    timer = Timer(const Duration(seconds: 2), () {
      timer = null;
      capture().catchError((Object _) {});
    });
  }

  Future<void> capture({bool force = false, String reason = '自动备份'}) async {
    final previous = running;
    if (previous != null) {
      await previous;
      if (force) await capture(force: true, reason: reason);
      return;
    }
    final task = _capture(force, reason);
    running = task;
    try {
      await task;
    } finally {
      if (identical(running, task)) running = null;
    }
  }

  Future<void> _capture(bool force, String reason) async {
    if (disposed || (!force && (!enabled || !due))) return;
    if (library.favorites.isEmpty &&
        library.history.isEmpty &&
        library.metadata.isEmpty &&
        library.bookmarks.isEmpty) {
      return;
    }
    try {
      final data = library.backup();
      final content = Map<String, dynamic>.from(data)..remove('exportedAt');
      final contentHash = sha256
          .convert(utf8.encode(jsonEncode(content)))
          .toString();
      if (entries.firstOrNull?['contentHash'] == contentHash) return;
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(data)));
      if (bytes.length > 5 * 1024 * 1024) {
        throw const FormatException('资料超过自动备份的 5 MB 上限，请手动导出。');
      }
      final at = DateTime.now().millisecondsSinceEpoch;
      final key = sha256
          .convert(utf8.encode('metadata:$at:$contentHash'))
          .toString();
      await store.write(key, bytes);
      final keep = library.option<int>('autoBackupKeep', 5).clamp(3, 10);
      final next = [
        {
          'key': key,
          'at': at,
          'bytes': bytes.length,
          'sha256': sha256.convert(bytes).toString(),
          'contentHash': contentHash,
          'reason': reason,
        },
        ...entries,
      ];
      final retained = next.take(keep).toList();
      await library.prefs.setString(
        'metadata.backups.v1',
        jsonEncode(retained),
      );
      entries
        ..clear()
        ..addAll(retained);
      for (final old in next.skip(keep)) {
        await store.delete(old['key'] as String);
      }
      error = null;
    } catch (e) {
      error = e.toString();
      rethrow;
    } finally {
      if (!disposed) notifyListeners();
    }
  }

  Future<Map<String, dynamic>> read(Map<String, dynamic> entry) async {
    final bytes = await store.read(entry['key']);
    if (bytes == null || sha256.convert(bytes).toString() != entry['sha256']) {
      throw const FormatException('备份缺失或校验失败，不会恢复。');
    }
    final result = Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)));
    validateBackup(result);
    return result;
  }

  @override
  void dispose() {
    disposed = true;
    timer?.cancel();
    library.removeListener(changed);
    super.dispose();
  }
}
