import 'dart:convert';

const maxSourceScriptBytes = 24 * 1024;
const scriptImagePrefix = 'script-image:';

class ScriptHttpError extends FormatException {
  ScriptHttpError(this.status) : super('书源请求失败（HTTP $status）');
  final int status;
}

bool isScriptDomain(String host) =>
    host.length <= 253 &&
    RegExp(
      r'^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z][a-z0-9-]{1,62}$',
    ).hasMatch(host);

Uri checkedScriptUrl(Uri uri) {
  if (uri.scheme != 'https' ||
      uri.port != 443 ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment ||
      !isScriptDomain(uri.host) ||
      uri.toString().length > 2048) {
    throw const FormatException('脚本漫画源只接受公开域名的 HTTPS 地址');
  }
  return uri;
}

List<String> scriptDomains(Object? raw, String fallback) {
  if (raw == null) return [fallback];
  if (raw is! List ||
      raw.isEmpty ||
      raw.length > 8 ||
      raw.any((host) => host is! String || !isScriptDomain(host))) {
    throw const FormatException('脚本源权限需填写 1–8 个小写域名');
  }
  return List<String>.from(raw);
}

bool validSourceScript(Object? source) =>
    source is String &&
    source.trim().isNotEmpty &&
    utf8.encode(source).length <= maxSourceScriptBytes;

Uri decodeScriptImage(String address) => checkedScriptUrl(
  Uri.parse(Uri.decodeComponent(address.substring(scriptImagePrefix.length))),
);
