import '../data/settings_checks.dart';

class AppUpdateDownload {
  static bool get supported => false;
  static Future<List<String>> architectures() async => [];
  static Future<String> download(
    UpdateRelease release,
    CheckControl control,
    void Function(int, int) progress,
  ) async => throw UnsupportedError('请在发行页下载。');
  static Future<String> install(String path) async =>
      throw UnsupportedError('请在发行页下载。');
}
