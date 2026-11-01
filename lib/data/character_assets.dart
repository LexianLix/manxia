import 'dart:convert';
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import '../platform/blob_store.dart';
import '../platform/storage.dart';
import 'character_definition.dart';

class CharacterAssets {
  CharacterAssets({BlobStore? store, Map<String, String>? bundled})
    : _provided = store,
      _providedIndex = bundled;
  static final shared = CharacterAssets();
  final BlobStore? _provided;
  final Map<String, String>? _providedIndex;
  Future<BlobStore>? _pending;
  Future<BlobStore> get store => _pending ??= _provided == null
      ? createCharacterStore()
      : Future.value(_provided);
  Future<Map<String, String>>? _index;
  Future<Map<String, String>> get index => _index ??= _readIndex();
  final _cache = <String, Uint8List>{};

  Future<Map<String, String>> _readIndex() async {
    if (_providedIndex != null) return _providedIndex;
    final data =
        jsonDecode(await rootBundle.loadString('assets/characters/index.json'))
            as Map;
    return Map<String, String>.from(data['images']);
  }

  static void checkPng(Uint8List bytes, String expected) {
    if (bytes.length < 33 ||
        bytes.length > 256 * 1024 ||
        sha256.convert(bytes).toString() != expected ||
        !List.generate(8, (i) => bytes[i]).asMap().entries.every(
          (e) => e.value == [137, 80, 78, 71, 13, 10, 26, 10][e.key],
        )) {
      throw const FormatException('角色图片损坏或校验不一致');
    }
    final header = ByteData.sublistView(bytes);
    final width = header.getUint32(16), height = header.getUint32(20);
    if (ascii.decode(bytes.sublist(12, 16)) != 'IHDR' ||
        width == 0 ||
        height == 0 ||
        width > 512 ||
        height > 512) {
      throw const FormatException('角色图片应为不超过 512px 的 PNG');
    }
    var at = 8;
    var ended = false;
    while (at + 12 <= bytes.length) {
      final size = header.getUint32(at), end = at + 12 + size;
      if (end > bytes.length) throw const FormatException('角色 PNG 数据不完整');
      final type = ascii.decode(bytes.sublist(at + 4, at + 8));
      if (type == 'acTL') throw const FormatException('角色包使用静态表情，由宿主控制动效');
      at = end;
      if (type == 'IEND') {
        ended = true;
        break;
      }
    }
    if (!ended || at != bytes.length) {
      throw const FormatException('角色 PNG 数据无效');
    }
  }

  void _remember(String key, Uint8List bytes) {
    _cache.remove(key);
    _cache[key] = bytes.asUnmodifiableView();
    while (_cache.length > 16) {
      _cache.remove(_cache.keys.first);
    }
  }

  Future<Uint8List?> read(String key) async {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(key)) return null;
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return cached;
    }
    try {
      final asset = (await index)[key];
      final bytes =
          asset != null &&
              asset.startsWith('assets/characters/') &&
              !asset.contains('..')
          ? (await rootBundle.load(asset)).asUint8List()
          : await (await store).read(key);
      if (bytes == null) return null;
      checkPng(bytes, key);
      _remember(key, bytes);
      return _cache[key];
    } catch (_) {
      return null;
    }
  }

  Future<void> prepare(
    CharacterDefinition definition,
    Map<String, Uint8List> resources,
  ) async {
    final checked = <String, Uint8List>{};
    for (final frame in definition.frames.values) {
      if (checked.containsKey(frame.sha256)) continue;
      final bytes = resources[frame.file] ?? await read(frame.sha256);
      if (bytes == null) throw const FormatException('角色素材缺失，请导入完整角色 ZIP 包');
      checkPng(bytes, frame.sha256);
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        if (codec.frameCount != 1) throw const FormatException('角色表情必须为静态图片');
        final decoded = await codec.getNextFrame();
        decoded.image.dispose();
      } finally {
        codec.dispose();
      }
      checked[frame.sha256] = bytes;
    }
    // Validate the complete package before writing any image or preference.
    final bundled = await index;
    for (final e in checked.entries) {
      if (!bundled.containsKey(e.key)) {
        await (await store).write(e.key, e.value);
      }
      _remember(e.key, e.value);
    }
  }

  Future<void> remove(String hash) async {
    _cache.remove(hash);
    if (!(await index).containsKey(hash)) await (await store).delete(hash);
  }
}

extension on ByteData {
  Uint8List asUint8List() => buffer.asUint8List(offsetInBytes, lengthInBytes);
}
