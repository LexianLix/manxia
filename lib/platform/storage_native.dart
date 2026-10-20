import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'blob_store.dart';

class NativeBlobStore implements BlobStore {
  NativeBlobStore(this.directory);
  final Directory directory;
  File file(String key) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(key)) {
      throw ArgumentError('Invalid blob key');
    }
    return File('${directory.path}/$key');
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    await file(key).writeAsBytes(bytes, flush: true);
  }

  @override
  Future<Uint8List?> read(String key) async {
    final f = file(key);
    return await f.exists() ? f.readAsBytes() : null;
  }

  @override
  Future<void> delete(String key) async {
    final f = file(key);
    if (await f.exists()) await f.delete();
  }
}

Future<BlobStore> createBlobStore() async {
  final root = await getApplicationDocumentsDirectory();
  return NativeBlobStore(
    await Directory('${root.path}/manxia/pages').create(recursive: true),
  );
}

Future<List<({String name, Uint8List bytes})>> readImageFolder(
  String path,
) async {
  final result = <({String name, Uint8List bytes})>[];
  await for (final entity in Directory(
    path,
  ).list(recursive: true, followLinks: false)) {
    if (entity is File &&
        RegExp(
          r'\.(png|jpe?g|webp|gif|bmp)$',
          caseSensitive: false,
        ).hasMatch(entity.path)) {
      if (result.length >= 5000) {
        throw const FormatException('文件夹超过 5000 张图片，请按分卷导入。');
      }
      result.add((name: entity.path, bytes: await entity.readAsBytes()));
    }
  }
  return result;
}
