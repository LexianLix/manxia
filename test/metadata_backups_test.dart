import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/data/backup_preview.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/metadata_backups.dart';
import 'package:manxia/platform/blob_store.dart';
import 'features_test.dart' as fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'a safety snapshot waits for an older write and then captures the latest state',
    () async {
      final library = await fixtures.library();
      await library.toggle(fixtures.comic);
      final store = _DelayedStore();
      final snapshots = MetadataBackups(library, store);
      library.backups = snapshots;
      addTearDown(library.dispose);
      final automatic = snapshots.capture();
      await store.started.future;
      await library.setMeta(fixtures.comic, {'group': 'Latest'});
      final safety = snapshots.capture(force: true, reason: '恢复前备份');
      store.release.complete();
      await Future.wait([automatic, safety]);
      expect(snapshots.entries, hasLength(2));
      final data = await snapshots.read(snapshots.entries.first);
      expect(data['metadata'][fixtures.comic.path]['group'], 'Latest');
      expect(snapshots.entries.first['reason'], '恢复前备份');
    },
  );
  test(
    'metadata snapshots deduplicate, rotate, exclude secrets and reject corrupt bytes',
    () async {
      final library = await fixtures.library();
      await library.toggle(fixtures.comic);
      await library.setOption('autoBackupKeep', 3);
      await library.setOption('webdav.password', 'must-not-back-up');
      final store = MemoryBlobStore();
      final service = MetadataBackups(library, store);
      library.backups = service;
      addTearDown(library.dispose);
      await service.capture(force: true);
      await service.capture(force: true);
      expect(service.entries, hasLength(1));
      for (var i = 0; i < 4; i++) {
        await library.setMeta(fixtures.comic, {'group': 'Group $i'});
        await service.capture(force: true);
      }
      expect(service.entries, hasLength(3));
      expect(store.data, hasLength(3));
      final data = await service.read(service.entries.first);
      expect(jsonEncode(data), isNot(contains('must-not-back-up')));
      expect(
        (data['metadata'] as Map)[fixtures.comic.path]['group'],
        'Group 3',
      );
      store.data[service.entries.first['key']] = Uint8List.fromList([1, 2, 3]);
      await expectLater(
        service.read(service.entries.first),
        throwsFormatException,
      );
    },
  );
  test(
    'restore preview preserves local conflicts and applies new data without incoming deletions by default',
    () async {
      final library = await fixtures.library();
      await library.toggle(fixtures.comic);
      await library.save(fixtures.record(2, 20));
      await library.setMeta(fixtures.comic, {'group': 'Local'});
      final incoming = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(library.backup())),
      );
      incoming['history'][0]['page'] = 7;
      incoming['history'][0]['updatedAt'] = 100;
      incoming['metadata'][fixtures.comic.path]['group'] = 'Remote';
      incoming['metadata'][fixtures.comic.path]['updatedAt'] = 9999999999999;
      incoming['tombstones'] = {'book:${fixtures.comic.path}': 9999999999999};
      final preview = BackupPreview(library.backup(), incoming);
      expect(preview.conflicts, 2);
      expect(preview.progressChanges, hasLength(1));
      expect(library.record(fixtures.comic)!.page, 2);
      await library.restore(preview.mergeInput(keepLocal: true));
      expect(library.record(fixtures.comic)!.page, 2);
      expect(library.meta(fixtures.comic)['group'], 'Local');
      expect(library.contains(fixtures.comic), true);
      await library.restore(preview.mergeInput());
      expect(library.record(fixtures.comic)!.page, 7);
      expect(library.meta(fixtures.comic)['group'], 'Remote');
    },
  );
  test(
    'invalid metadata is rejected before existing library changes; legacy schema remains accepted',
    () async {
      final library = await fixtures.library();
      await library.toggle(fixtures.comic);
      final backup = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(library.backup())),
      );
      backup['favorites'].add(
        const Comic(path: '/new/', title: 'New', cover: '').toJson(),
      );
      backup['metadata'] = {'/new/': 'not a map'};
      await expectLater(library.restore(backup), throwsFormatException);
      expect(library.favorites.map((b) => b.path), [fixtures.comic.path]);
      backup['metadata'] = {};
      backup.remove('schema');
      await library.restore(backup);
      expect(library.favorites, hasLength(2));
    },
  );
}

class _DelayedStore extends MemoryBlobStore {
  final started = Completer<void>(), release = Completer<void>();
  @override
  Future<void> write(String key, Uint8List bytes) async {
    if (!started.isCompleted) {
      started.complete();
      await release.future;
    }
    await super.write(key, bytes);
  }
}
