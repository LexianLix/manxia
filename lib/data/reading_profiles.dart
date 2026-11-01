import 'dart:convert';
import 'comic.dart';
import 'library_features.dart';
import 'reading_profile.dart';
export 'reading_profile.dart';

extension ReadingProfiles on LibraryFeatures {
  List<ReadingProfile> get readingProfiles =>
      ReadingProfile.fromOptions(options);
  Future<ReadingProfile> saveReadingProfile(
    String name,
    Map<String, dynamic> values, {
    String? id,
  }) async {
    final profiles = readingProfiles;
    final profile = ReadingProfile(
      id: id ?? 'p_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
      name: name.trim(),
      values: ReadingProfile.clean(values),
    );
    final at = profiles.indexWhere((p) => p.id == profile.id);
    if (at < 0) {
      if (profiles.length >= 20) throw const FormatException('最多保存 20 个阅读方案');
      profiles.add(profile);
    } else {
      profiles[at] = profile;
    }
    await setOption(
      'reader.profiles',
      profiles.map((p) => p.toJson()).toList(),
    );
    return profile;
  }

  Future<void> deleteReadingProfile(String id) async {
    options['reader.profiles'] = readingProfiles
        .where((p) => p.id != id)
        .map((p) => p.toJson())
        .toList();
    if (options['reader.profileDefault'] == id) {
      options.remove('reader.profileDefault');
    }
    await persistFeatures();
  }

  Map<String, dynamic> previewReadingProfile(
    Comic? comic,
    ReadingProfile profile, {
    required bool asDefault,
  }) => asDefault
      ? (comic == null
            ? defaultReaderOptions(profileDefaults: profile.values)
            : readerOptions(comic, profileDefaults: profile.values))
      : {...readerOptions(comic!), ...profile.values};
  Future<ReadingProfileApplication> applyReadingProfile(
    Comic? comic,
    ReadingProfile profile, {
    required bool asDefault,
  }) async {
    if (!readingProfiles.any((p) => p.id == profile.id)) {
      throw const FormatException('阅读方案已删除');
    }
    final oldDefault = options['reader.profileDefault'];
    final oldReader = comic == null ? null : meta(comic)['reader'];
    if (!asDefault && comic == null) throw const FormatException('请选择要应用方案的漫画');
    if (asDefault) {
      await setOption('reader.profileDefault', profile.id);
    } else {
      await setMeta(comic!, {
        'reader': {
          ...Map<String, dynamic>.from(meta(comic)['reader'] as Map? ?? {}),
          ...profile.values,
        },
      });
    }
    return ReadingProfileApplication._(
      this,
      comic,
      asDefault,
      oldDefault,
      oldReader == null ? null : Map<String, dynamic>.from(oldReader),
      asDefault ? profile.id : jsonEncode(meta(comic!)['reader']),
    );
  }
}

/// Undo only the fields changed by this application, and never overwrite a
/// newer choice made while the confirmation message is visible.
class ReadingProfileApplication {
  ReadingProfileApplication._(
    this.library,
    this.comic,
    this.asDefault,
    this.oldDefault,
    this.oldReader,
    this.expected,
  );
  final LibraryFeatures library;
  final Comic? comic;
  final bool asDefault;
  final Object? oldDefault;
  final Map<String, dynamic>? oldReader;
  final String expected;
  bool used = false;
  Future<bool> undo() async {
    if (used) return false;
    used = true;
    if (asDefault) {
      if (library.options['reader.profileDefault'] != expected) return false;
      if (oldDefault == null) {
        library.options.remove('reader.profileDefault');
      } else {
        library.options['reader.profileDefault'] = oldDefault;
      }
      await library.persistFeatures();
    } else {
      if (jsonEncode(library.meta(comic!)['reader']) != expected) return false;
      final metadata = {...library.meta(comic!)};
      if (oldReader == null) {
        metadata.remove('reader');
      } else {
        metadata['reader'] = oldReader;
      }
      library.metadata[comic!.path] = metadata;
      await library.persistFeatures();
    }
    return true;
  }
}
