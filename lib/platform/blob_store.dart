import 'dart:typed_data';

abstract class BlobStore {
  Future<void> write(String key, Uint8List bytes);
  Future<Uint8List?> read(String key);
  Future<void> delete(String key);
}

class MemoryBlobStore implements BlobStore {
  final data = <String, Uint8List>{};
  @override
  Future<void> write(String key, Uint8List bytes) async {
    data[key] = bytes;
  }

  @override
  Future<Uint8List?> read(String key) async => data[key];
  @override
  Future<void> delete(String key) async {
    data.remove(key);
  }
}
