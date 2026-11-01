import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'plugin.dart';
import 'character_definition.dart';
import 'character_assets.dart';

class PluginPackage {
  static ManxiaPlugin decode(Uint8List bytes) {
    if (bytes.length > 2 * 1024 * 1024) {
      throw const FormatException('插件包超过 2 MB');
    }
    if (bytes.length < 4 || bytes[0] != 80 || bytes[1] != 75) {
      return ManxiaPlugin(
        Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes))),
      );
    }
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    if (archive.length > 5) throw const FormatException('角色 ZIP 只接受清单和四种表情');
    var total = 0;
    final files = <String, Uint8List>{};
    for (final file in archive) {
      if (!file.isFile ||
          file.isSymbolicLink ||
          files.containsKey(file.name) ||
          !RegExp(
            r'^(manifest\.json|[a-z][a-z0-9_-]{0,30}\.png)$',
          ).hasMatch(file.name) ||
          file.size > 256 * 1024) {
        throw const FormatException('角色 ZIP 文件或路径无效');
      }
      total += file.size;
      if (total > 1152 * 1024) throw const FormatException('角色 ZIP 展开内容过大');
      final content = Uint8List.fromList(file.content);
      if (content.length != file.size) {
        throw const FormatException('角色 ZIP 数据大小不一致');
      }
      files[file.name] = content;
    }
    final manifest = files.remove('manifest.json');
    if (manifest == null) {
      throw const FormatException('角色 ZIP 缺少 manifest.json');
    }
    final plugin = ManxiaPlugin(
      Map<String, dynamic>.from(jsonDecode(utf8.decode(manifest))),
      resources: files,
    );
    if (plugin.contributions['character'] is! Map) {
      throw const FormatException('角色 ZIP 缺少角色定义');
    }
    final definition = CharacterDefinition(
      Map<String, dynamic>.from(plugin.contributions['character']),
    );
    final expected = definition.frames.values.map((f) => f.file).toSet();
    if (files.length != expected.length || !expected.every(files.containsKey)) {
      throw const FormatException('角色 ZIP 素材不完整');
    }
    for (final frame in definition.frames.values) {
      CharacterAssets.checkPng(files[frame.file]!, frame.sha256);
    }
    return plugin;
  }

  static Future<Uint8List> encode(
    ManxiaPlugin plugin,
    CharacterAssets assets,
  ) async {
    final definition = CharacterDefinition(
      Map<String, dynamic>.from(plugin.contributions['character']),
    );
    final archive = Archive();
    final manifest = utf8.encode(jsonEncode(plugin.json));
    archive.addFile(ArchiveFile('manifest.json', manifest.length, manifest));
    final added = <String>{};
    for (final f in definition.frames.values) {
      if (!added.add(f.file)) continue;
      final bytes = await assets.read(f.sha256);
      if (bytes == null) throw const FormatException('角色素材缺失，请重新导入原角色包');
      archive.addFile(ArchiveFile(f.file, bytes.length, bytes));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }
}
