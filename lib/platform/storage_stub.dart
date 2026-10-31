import 'blob_store.dart';
import 'dart:typed_data';

Future<List<({String name, Uint8List bytes})>> readImageFolder(String path) =>
    throw UnsupportedError('请使用多选图片导入。');

Future<BlobStore> createBlobStore() async => MemoryBlobStore();
Future<BlobStore> createWallpaperStore() async => MemoryBlobStore();
Future<BlobStore> createBackupStore() async => MemoryBlobStore();
