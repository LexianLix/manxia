import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/data/library.dart';
import 'package:manxia/data/reading_profiles.dart';
import 'features_test.dart' as fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'preview is side-effect free and respects book/default/plugin priority',
    () async {
      final library = await fixtures.library();
      await library.setOption('readerDefaults', {
        'background': 'sepia',
        'rtl': false,
      });
      await library.setOption('plugins.installed', [
        {
          'enabled': true,
          'config': {},
          'manifest': {
            'apiVersion': 1,
            'id': 'test.reader',
            'name': 'Reader',
            'author': 'Test',
            'version': '1.0.0',
            'license': 'MIT',
            'contributes': {
              'reader': {'background': 'paper', 'rtl': false},
            },
          },
        },
      ]);
      await library.setMeta(fixtures.comic, {
        'reader': {'rtl': true},
        'note': 'keep',
      });

      final profile = await library.saveReadingProfile('夜读', {
        'background': 'ink',
        'rtl': false,
        'smartOfflineChapters': 10,
        'volumeKeys': true,
      });
      final before = library.prefs.getString('features.v2');
      expect(profile.values.containsKey('smartOfflineChapters'), false);
      expect(profile.values.containsKey('volumeKeys'), false);
      final preview = library.previewReadingProfile(
        fixtures.comic,
        profile,
        asDefault: true,
      );
      expect(preview['background'], 'ink');
      expect(preview['rtl'], true);
      expect(library.prefs.getString('features.v2'), before);
      expect(library.readerOptions(fixtures.comic)['background'], 'paper');
      await library.applyReadingProfile(
        fixtures.comic,
        profile,
        asDefault: true,
      );
      expect(library.readerOptions(fixtures.comic)['background'], 'ink');
      expect(library.readerOptions(fixtures.comic)['rtl'], true);
      await library.applyReadingProfile(
        fixtures.comic,
        profile,
        asDefault: false,
      );
      expect(library.readerOptions(fixtures.comic)['rtl'], false);
      expect(library.meta(fixtures.comic)['note'], 'keep');
      library.dispose();
    },
  );
  test(
    'profiles survive reopen and deleting the default restores base preferences',
    () async {
      final library = await fixtures.library();
      await library.toggle(fixtures.comic);
      await library.save(fixtures.record(7, 10));
      await library.setOption('readerDefaults', {'background': 'sepia'});
      final profile = await library.saveReadingProfile('我的方案', {
        'mode': 'vertical',
        'background': 'ink',
      });
      await library.applyReadingProfile(
        fixtures.comic,
        profile,
        asDefault: true,
      );
      final reopened = Library(library.prefs);
      await reopened.load();
      expect(reopened.readingProfiles.last.name, '我的方案');
      expect(reopened.readerOptions(fixtures.comic)['mode'], 'vertical');
      await reopened.deleteReadingProfile(profile.id);
      expect(reopened.readerOptions(fixtures.comic)['background'], 'sepia');
      expect(reopened.contains(fixtures.comic), true);
      expect(reopened.record(fixtures.comic)!.page, 7);
      library.dispose();
      reopened.dispose();
    },
  );
  test(
    'invalid restored profiles cannot execute, override reading or block startup',
    () async {
      final library = await fixtures.library();
      await library.prefs.setString(
        'features.v2',
        jsonEncode({
          'options': {
            'reader.profiles': [
              {
                'id': 'broken',
                'name': '坏方案',
                'options': {'mode': 'script'},
              },
              {
                'id': 'unknown',
                'name': '坏参数',
                'options': {'network': 'https://example.com'},
              },
            ],
            'reader.profileDefault': 'broken',
          },
        }),
      );
      final reopened = Library(library.prefs);
      await reopened.load();
      expect(reopened.readingProfiles, isEmpty);
      expect(reopened.readerOptions(fixtures.comic)['mode'], 'page');
      final before = reopened.prefs.getString('features.v2');
      await expectLater(
        reopened.saveReadingProfile('错误', {'brightness': double.nan}),
        throwsFormatException,
      );
      expect(reopened.prefs.getString('features.v2'), before);
      library.dispose();
      reopened.dispose();
    },
  );
  test(
    'undo preserves later book edits and restores only the last applied fields',
    () async {
      final library = await fixtures.library();
      final night = library.readingProfiles.first;
      final applied = await library.applyReadingProfile(
        fixtures.comic,
        night,
        asDefault: false,
      );
      await library.setMeta(fixtures.comic, {'note': 'added after apply'});
      expect(await applied.undo(), true);
      expect(library.meta(fixtures.comic)['note'], 'added after apply');
      expect(library.meta(fixtures.comic).containsKey('reader'), false);
      final earlier = await library.applyReadingProfile(
        fixtures.comic,
        night,
        asDefault: false,
      );
      await library.setReaderOption(fixtures.comic, 'background', 'sepia');
      expect(await earlier.undo(), false);
      expect(library.readerOptions(fixtures.comic)['background'], 'sepia');
      library.dispose();
    },
  );
}
