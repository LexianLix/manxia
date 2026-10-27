import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import '../data/app_update.dart';
import '../data/settings_checks.dart';

class AppUpdateDownload {
  static const channel = MethodChannel('io.manxia/update');
  static bool get supported => Platform.isAndroid;
  static Future<List<String>> architectures() async => List<String>.from(
    (await channel.invokeMapMethod<String, dynamic>('info'))?['abis'] ?? [],
  );
  static Future<String> download(
    UpdateRelease release,
    CheckControl control,
    void Function(int, int) progress,
  ) async {
    final client = http.Client();
    final close = client.close;
    control.onCancel(close);
    File? partial;
    IOSink? sink;
    StreamIterator<List<int>>? chunks;
    bool complete = false;
    try {
      final abis = await control.wait(architectures());
      final manifestUri = Uri.https(
        'github.com',
        '/LexianLix/manxia/releases/download/${release.tag}/release-manifest.json',
      );
      final response = await control.wait(
        client.get(manifestUri).timeout(const Duration(seconds: 20)),
      );
      if (response.statusCode != 200 ||
          response.bodyBytes.length > 128 * 1024) {
        throw const FormatException('无法读取发行清单，请重试或到发行页下载。');
      }
      final package = UpdatePackage.select(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
        release,
        abis,
      );
      final root = Directory('${(await getTemporaryDirectory()).path}/updates');
      await root.create(recursive: true);
      // Only our own update files live in this directory. Never touch user books.
      final target = File('${root.path}/${package.name}');
      if (await target.exists()) {
        final digest = await control.wait(sha256.bind(target.openRead()).first);
        if (await target.length() == package.bytes &&
            digest.toString() == package.sha256) {
          control.ensureActive();
          return target.path;
        }
        await target.delete();
      }
      partial = File('${target.path}.part');
      final stream = await control.wait(
        client
            .send(http.Request('GET', package.uri))
            .timeout(const Duration(seconds: 25)),
      );
      if (stream.statusCode != 200) {
        throw const FormatException('安装包下载失败，请重试或到发行页下载。');
      }
      if (stream.contentLength != null &&
          stream.contentLength != package.bytes) {
        throw const FormatException('安装包大小与发行清单不一致。');
      }
      sink = partial.openWrite();
      var bytes = 0;
      final watch = Stopwatch()..start();
      chunks = StreamIterator(stream.stream);
      while (await control.wait(
        chunks.moveNext().timeout(const Duration(seconds: 25)),
      )) {
        final chunk = chunks.current;
        control.ensureActive();
        if (watch.elapsed > const Duration(minutes: 5)) {
          throw const FormatException('下载超时，请重试。');
        }
        bytes += chunk.length;
        if (bytes > package.bytes) throw const FormatException('安装包超出清单大小。');
        sink.add(chunk);
        progress(bytes, package.bytes);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      control.ensureActive();
      if (bytes != package.bytes) throw const FormatException('安装包下载不完整，请重试。');
      final digest = await control.wait(sha256.bind(partial.openRead()).first);
      if (digest.toString() != package.sha256) {
        throw const FormatException('安装包校验失败，请重新下载。');
      }
      control.ensureActive();
      await partial.rename(target.path);
      complete = true;
      return target.path;
    } finally {
      control.removeCancel(close);
      client.close();
      await chunks?.cancel();
      await sink?.close();
      if (!complete && partial != null && await partial.exists()) {
        await partial.delete();
      }
    }
  }

  static Future<String> install(String path) async =>
      await channel.invokeMethod<String>('install', {'path': path}) ??
      'unavailable';
}
