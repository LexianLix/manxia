import 'dart:typed_data';

Future<Uint8List> fetchScriptResource(
  Uri url, {
  required int maxBytes,
  Future<void>? abort,
  bool image = false,
}) async => throw UnsupportedError('脚本漫画源需要 Android');
