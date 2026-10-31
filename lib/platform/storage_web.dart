import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;
import 'blob_store.dart';

class WebBlobStore implements BlobStore {
  WebBlobStore({this.namespace = 'offline'});
  final String namespace;
  String address(String key) =>
      '${web.window.location.origin}/$namespace-data/$key';
  Future<web.Cache> get cache =>
      web.window.caches.open('manxia-$namespace-v1').toDart;
  @override
  Future<void> write(String key, Uint8List bytes) async {
    await (await cache)
        .put(web.Request(address(key).toJS), web.Response(bytes.toJS))
        .toDart;
  }

  @override
  Future<Uint8List?> read(String key) async {
    final response = await (await cache)
        .match(web.Request(address(key).toJS))
        .toDart;
    if (response == null) return null;
    return (await response.arrayBuffer().toDart).toDart.asUint8List();
  }

  @override
  Future<void> delete(String key) async {
    await (await cache).delete(web.Request(address(key).toJS)).toDart;
  }
}

Future<BlobStore> createBlobStore() async => WebBlobStore();
Future<BlobStore> createWallpaperStore() async =>
    WebBlobStore(namespace: 'appearance');
Future<BlobStore> createBackupStore() async =>
    WebBlobStore(namespace: 'backups');
Future<List<({String name, Uint8List bytes})>> readImageFolder(String path) =>
    throw UnsupportedError('浏览器请使用多选图片导入。');
