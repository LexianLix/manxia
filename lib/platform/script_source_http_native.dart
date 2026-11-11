import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import '../data/script_source_policy.dart';
import '../data/dm5_source.dart';

bool _publicAddress(InternetAddress address) {
  final b = address.rawAddress;
  if (b.length == 16) {
    // Global unicast only. Exclude 6to4 and Teredo tunnels.
    return (b[0] & 0xe0) == 0x20 &&
        !(b[0] == 0x20 && b[1] == 0x02) &&
        !(b[0] == 0x20 && b[1] == 0x01 && b[2] == 0 && b[3] == 0);
  }
  final a = b[0], c = b[1];
  return a > 0 &&
      a < 224 &&
      a != 10 &&
      a != 127 &&
      !(a == 100 && c >= 64 && c <= 127) &&
      !(a == 169 && c == 254) &&
      !(a == 172 && c >= 16 && c <= 31) &&
      !(a == 192 && (c == 168 || c == 0)) &&
      !(a == 198 && (c == 18 || c == 19));
}

Future<Uint8List> fetchScriptResource(
  Uri url, {
  required int maxBytes,
  Future<void>? abort,
  bool image = false,
}) async {
  checkedScriptUrl(url);
  final client = HttpClient()
    ..userAgent =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/140.0.0.0 Safari/537.36'
    ..connectionTimeout = const Duration(seconds: 6)
    ..findProxy = (_) => 'DIRECT';
  var closed = false;
  client.connectionFactory = (uri, proxy, port) async {
    final addresses = await InternetAddress.lookup(uri.host);
    if (closed ||
        addresses.isEmpty ||
        addresses.any((a) => !_publicAddress(a))) {
      throw const FormatException('脚本漫画源无法连接此网络地址');
    }
    final address =
        addresses
            .where((a) => a.type == InternetAddressType.IPv4)
            .firstOrNull ??
        addresses.first;
    final tcp = await Socket.startConnect(address, uri.port);
    Socket? socket;
    final tls = tcp.socket.then((connected) async {
      socket = connected;
      if (closed) {
        connected.destroy();
        throw const FormatException('书源请求已取消');
      }
      return SecureSocket.secure(connected, host: uri.host);
    });
    return ConnectionTask.fromSocket(tls, () {
      tcp.cancel();
      socket?.destroy();
    });
  };

  Future<Uint8List> read() async {
    final request = await client.getUrl(url);
    request.headers.set(
      HttpHeaders.refererHeader,
      image
          ? Dm5Source.headersForImage(url.toString())['Referer'] ??
                '${url.origin}/'
          : '${url.origin}/',
    );
    request.followRedirects = false;
    final response = await request.close();
    if (response.statusCode != 200) {
      throw ScriptHttpError(response.statusCode);
    }
    if (image && response.headers.contentType?.primaryType != 'image') {
      throw const FormatException('书源没有返回图片');
    }
    if (response.contentLength > maxBytes) {
      throw const FormatException('书源响应超过大小限制');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response) {
      if (bytes.length + chunk.length > maxBytes) {
        throw const FormatException('书源响应超过大小限制');
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  try {
    return await Future.any<Uint8List>([
      read(),
      if (abort != null)
        abort.then((_) => throw const FormatException('书源请求已取消')),
    ]).timeout(Duration(seconds: maxBytes > 128 * 1024 ? 20 : 7));
  } finally {
    closed = true;
    client.close(force: true);
  }
}
