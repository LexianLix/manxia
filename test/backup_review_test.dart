import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/data/metadata_backups.dart';
import 'package:manxia/platform/blob_store.dart';
import 'package:manxia/ui/metadata_backups_page.dart';
import 'package:manxia/ui/localized_text.dart';
import 'features_test.dart' as fixtures;

void main() {
  testWidgets(
    'review is inert until confirmation and writes a safety snapshot before merge',
    (tester) async {
      final library = await fixtures.library();
      await library.toggle(fixtures.comic);
      await library.save(fixtures.record(1, 1));
      final store = MemoryBlobStore();
      final snapshots = MetadataBackups(library, store);
      library.backups = snapshots;
      final incoming = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(library.backup())),
      );
      incoming['history'][0]['page'] = 9;
      incoming['history'][0]['updatedAt'] = 200;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => reviewBackup(context, library, incoming),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(library.record(fixtures.comic)!.page, 1);
      await tester.tap(find.text(translate('确认合并资料', const Locale('en'))));
      await tester.pumpAndSettle();
      expect(library.record(fixtures.comic)!.page, 9);
      expect(
        (await snapshots.read(snapshots.entries.first))['history'][0]['page'],
        1,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      library.dispose();
    },
  );
}
