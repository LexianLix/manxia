import 'settings_checks.dart';

class UpdatePackage {
  const UpdatePackage({
    required this.name,
    required this.abi,
    required this.sha256,
    required this.bytes,
    required this.versionCode,
    required this.uri,
  });
  final String name, abi, sha256;
  final int bytes, versionCode;
  final Uri uri;
  static UpdatePackage select(
    Map<String, dynamic> manifest,
    UpdateRelease release,
    List<String> abis,
  ) {
    if (manifest['applicationId'] != 'io.manxia.manxia' ||
        manifest['mode'] != 'release' ||
        manifest['version'] is! String ||
        ReleaseVersion.parse(
              manifest['version'],
            )?.compareTo(ReleaseVersion.parse(release.tag)!) !=
            0) {
      throw const FormatException('发行清单与版本不一致，请到发行页下载。');
    }
    final packages = manifest['packages'];
    if (packages is! List) throw const FormatException('发行版缺少安装包清单。');
    for (final abi in abis.where(
      (a) => ['arm64-v8a', 'armeabi-v7a', 'x86_64'].contains(a),
    )) {
      for (final raw in packages.whereType<Map>()) {
        if (raw['abi'] != abi) continue;
        final version = release.tag.replaceFirst(RegExp(r'^v'), '');
        final name = 'Manxia-$version-$abi.apk';
        final sha = raw['sha256'],
            bytes = raw['bytes'],
            code = raw['versionCode'];
        if (raw['name'] != name ||
            sha is! String ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha) ||
            bytes is! int ||
            bytes < 1 ||
            bytes > 200 * 1024 * 1024 ||
            code is! int ||
            code < 1) {
          throw const FormatException('安装包清单无效，请到发行页下载。');
        }
        return UpdatePackage(
          name: name,
          abi: abi,
          sha256: sha,
          bytes: bytes,
          versionCode: code,
          uri: Uri.https(
            'github.com',
            '/LexianLix/manxia/releases/download/${release.tag}/$name',
          ),
        );
      }
    }
    throw const FormatException('该发行版没有适合此设备的安装包。');
  }
}
