import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'library.dart';
import 'offline_library.dart';

class SyncService {
  SyncService(
    this.library, {
    http.Client? client,
    this.gateway,
    this.readPassword,
  }) : client = client ?? http.Client();
  final Library library;
  final http.Client client;
  final Uri? gateway;
  final Future<String> Function()? readPassword;
  static const vault = FlutterSecureStorage();
  static String sessionPassword = '';
  Future<String> password() async =>
      kIsWeb ? sessionPassword : await vault.read(key: 'webdav.password') ?? '';
  Future<void> savePassword(String password) async {
    if (kIsWeb) {
      sessionPassword = password;
    } else {
      await vault.write(key: 'webdav.password', value: password);
    }
  }

  Future<http.Response> send(
    String method,
    Uri target,
    String user,
    String password, {
    String? body,
    String? etag,
  }) async {
    if (target.scheme != 'https' ||
        target.userInfo.isNotEmpty ||
        target.host.isEmpty) {
      throw const FormatException('WebDAV 请填写不含账号密码的 HTTPS 文件地址。');
    }
    final headers = <String, String>{
      'Authorization': 'Basic ${base64Encode(utf8.encode('$user:$password'))}',
      if (body != null) 'Content-Type': 'application/json',
      (etag == '*' ? 'If-None-Match' : 'If-Match'): ?etag,
    };
    if (gateway != null) {
      final result = await client
          .post(
            gateway!.resolve('/api/webdav'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'url': target.toString(),
              'method': method,
              'headers': headers,
              'body': body,
            }),
          )
          .timeout(const Duration(seconds: 40));
      if (result.statusCode != 200) {
        throw StateError('同步代理返回 ${result.statusCode}');
      }
      final json = jsonDecode(result.body) as Map;
      return http.Response(
        json['body'] as String,
        json['status'] as int,
        headers: Map<String, String>.from(json['headers']),
      );
    }
    final request = http.Request(method, target)
      ..headers.addAll(headers)
      ..followRedirects = false;
    if (body != null) request.body = body;
    return http.Response.fromStream(
      await client.send(request).timeout(const Duration(seconds: 35)),
    );
  }

  /// Conditional writes prevent a device overwriting another device's newer snapshot.
  Future<String> synchronize() async {
    final target = Uri.parse(library.option<String>('webdav.url', ''));
    final user = library.option<String>('webdav.user', '');
    final pass = await (readPassword?.call() ?? password());
    final read = await send('GET', target, user, pass);
    String? tag;
    if (read.statusCode == 200) {
      tag = read.headers['etag'];
      if (tag == null || tag.startsWith('W/')) {
        throw StateError('服务器未提供强 ETag，不能安全合并上传；请改用支持 ETag 的 WebDAV 服务。');
      }
      await library.restore(Map<String, dynamic>.from(jsonDecode(read.body)));
    } else if (read.statusCode == 404) {
      tag = '*';
    } else {
      throw StateError('读取同步文件失败：HTTP ${read.statusCode}');
    }
    final write = await send(
      'PUT',
      target,
      user,
      pass,
      etag: tag,
      body: jsonEncode(library.backup()),
    );
    if (write.statusCode == 412) throw StateError('另一台设备刚更新了数据，请再次同步以合并。');
    if (![200, 201, 204].contains(write.statusCode)) {
      throw StateError('上传同步文件失败：HTTP ${write.statusCode}');
    }
    await library.setOption(
      'webdav.lastSync',
      DateTime.now().toIso8601String(),
    );
    return '收藏、阅读位置、分组和书签已合并同步。';
  }

  void close() => client.close();
  Uri get archiveTarget {
    final target = Uri.parse(library.option<String>('webdav.url', ''));
    final path = target.path.endsWith('.json')
        ? target.path.substring(0, target.path.length - 5)
        : target.path;
    return target.replace(path: '$path.offline.zip');
  }

  Future<http.Response> binary(
    String method, {
    Uint8List? body,
    String? etag,
  }) async {
    final target = archiveTarget;
    if (target.scheme != 'https' ||
        target.host.isEmpty ||
        target.userInfo.isNotEmpty) {
      throw const FormatException('请先配置 WebDAV HTTPS 文件地址。');
    }
    final pass = await (readPassword?.call() ?? password());
    final headers = {
      'Authorization':
          'Basic ${base64Encode(utf8.encode('${library.option<String>('webdav.user', '')}:$pass'))}',
      'Content-Type': 'application/zip',
      (etag == '*' ? 'If-None-Match' : 'If-Match'): ?etag,
    };
    final uri =
        gateway
            ?.resolve('/api/webdav-binary')
            .replace(
              queryParameters: {'url': target.toString(), 'method': method},
            ) ??
        target;
    final request = http.Request(gateway == null ? method : 'POST', uri)
      ..headers.addAll(headers)
      ..followRedirects = false;
    if (body != null) request.bodyBytes = body;
    return http.Response.fromStream(
      await client.send(request).timeout(const Duration(minutes: 5)),
    );
  }

  Future<String> uploadLibrary(OfflineLibrary offline) async {
    final state = await binary('HEAD');
    String? tag;
    if (state.statusCode == 404) {
      tag = '*';
    } else if (state.statusCode == 200) {
      tag = state.headers['etag'];
      if (tag == null || tag.startsWith('W/')) {
        throw StateError('离线备份服务器需支持强 ETag，避免覆盖其他设备上传。');
      }
    } else {
      throw StateError('检查离线备份失败：HTTP ${state.statusCode}');
    }
    final result = await binary(
      'PUT',
      body: await offline.exportBundle(),
      etag: tag,
    );
    if (result.statusCode == 412) throw StateError('备份已被其他设备更新，请先恢复/合并，再重新上传。');
    if (![200, 201, 204].contains(result.statusCode)) {
      throw StateError('上传离线书库失败：HTTP ${result.statusCode}');
    }
    return '已上传完成章节、图片与资料的 ZIP 书库。';
  }

  Future<String> downloadLibrary(OfflineLibrary offline) async {
    final result = await binary('GET');
    if (result.statusCode != 200) {
      throw StateError('下载离线书库失败：HTTP ${result.statusCode}');
    }
    if (result.bodyBytes.length > 512 * 1024 * 1024) {
      throw StateError('书库备份超过 512 MB。');
    }
    await offline.importBundle(result.bodyBytes);
    return '云端离线书库已校验并合并到本机。';
  }
}
