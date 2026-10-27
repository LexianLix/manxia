import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html;
import 'comic.dart';
import 'dm5_source.dart';

class CheckCancelled implements Exception {}

class CheckControl {
  final _cancelled = Completer<void>();
  final _cleanup = <void Function()>[];
  bool get cancelled => _cancelled.isCompleted;
  void ensureActive() {
    if (cancelled) throw CheckCancelled();
  }

  void onCancel(void Function() callback) => _cleanup.add(callback);
  void removeCancel(void Function() callback) => _cleanup.remove(callback);
  void cancel() {
    if (cancelled) return;
    _cancelled.complete();
    for (final close in _cleanup.toList()) {
      close();
    }
    _cleanup.clear();
  }

  Future<T> wait<T>(Future<T> work) {
    ensureActive();
    return Future.any([
      work,
      _cancelled.future.then<T>((_) => throw CheckCancelled()),
    ]);
  }
}

enum SourceCheckStage { catalog, detail, pages }

class SourceSample {
  SourceSample(
    this.comic, {
    this.chapters = 0,
    this.pages = 0,
    this.reason,
    this.copyright = false,
  });
  final Comic comic;
  final int chapters, pages;
  final String? reason;
  final bool copyright;
}

class SourceCheckReport {
  SourceCheckReport(this.books, this.samples, this.milliseconds);
  final int books, milliseconds;
  final List<SourceSample> samples;
  bool get readable => samples.any((s) => s.pages > 0);
  bool get allCopyright =>
      samples.isNotEmpty && samples.every((s) => s.copyright);
}

Future<SourceCheckReport> inspectSource(
  Dm5Source original,
  CheckControl control, {
  void Function(SourceCheckStage stage, Comic? comic)? progress,
  Duration stepTimeout = const Duration(seconds: 12),
  Duration totalTimeout = const Duration(seconds: 35),
}) async {
  final probe = original.forkForCheck();
  final close = probe.close;
  control.onCancel(close);
  final watch = Stopwatch()..start();
  Future<T> step<T>(Future<T> Function() task) async {
    control.ensureActive();
    final remaining = totalTimeout - watch.elapsed;
    if (remaining <= Duration.zero) throw TimeoutException('source check');
    final timeout = remaining < stepTimeout ? remaining : stepTimeout;
    final result = await control.wait(task().timeout(timeout));
    control.ensureActive();
    return result;
  }

  try {
    progress?.call(SourceCheckStage.catalog, null);
    final books = await step(probe.home);
    final candidates = {
      for (final b in books) '${b.sourceId}/${b.path}': b,
    }.values.take(3);
    final samples = <SourceSample>[];
    for (final comic in candidates) {
      try {
        progress?.call(SourceCheckStage.detail, comic);
        final detail = await step(() => probe.detail(comic));
        if (detail.chapters.isEmpty) {
          samples.add(SourceSample(comic, reason: '未读取到网页章节'));
          continue;
        }
        progress?.call(SourceCheckStage.pages, comic);
        final pages = await step(
          () => probe.networkPages(detail.chapters.first.path),
        );
        final count = pages
            .where((p) => ['http', 'https'].contains(Uri.tryParse(p)?.scheme))
            .length;
        samples.add(
          SourceSample(
            comic,
            chapters: detail.chapters.length,
            pages: count,
            reason: count == 0 ? '未读取到章节图片地址' : null,
          ),
        );
        if (count > 0) break;
      } on CheckCancelled {
        rethrow;
      } on SourceCopyrightException catch (e) {
        samples.add(SourceSample(comic, reason: e.message, copyright: true));
      } on TimeoutException {
        samples.add(SourceSample(comic, reason: '请求超时'));
        if (watch.elapsed >= totalTimeout) break;
      } catch (e) {
        samples.add(
          SourceSample(
            comic,
            reason: e is SourceException ? e.message : '暂时无法读取此作品',
          ),
        );
      }
    }
    return SourceCheckReport(books.length, samples, watch.elapsedMilliseconds);
  } finally {
    control.removeCancel(close);
    probe.close();
  }
}

final githubLatestPage = Uri.parse(
  'https://github.com/LexianLix/manxia/releases/latest',
);
final githubLatestApi = Uri.parse(
  'https://api.github.com/repos/LexianLix/manxia/releases/latest',
);

class ReleaseVersion implements Comparable<ReleaseVersion> {
  ReleaseVersion(this.parts, this.prerelease);
  final List<int> parts;
  final String? prerelease;
  static ReleaseVersion? parse(String value) {
    final m = RegExp(
      r'^v?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+\d+)?$',
    ).firstMatch(value.trim());
    if (m == null) return null;
    return ReleaseVersion([
      int.parse(m[1]!),
      int.parse(m[2]!),
      int.parse(m[3]!),
    ], m[4]);
  }

  @override
  int compareTo(ReleaseVersion other) {
    for (var i = 0; i < 3; i++) {
      final n = parts[i].compareTo(other.parts[i]);
      if (n != 0) return n;
    }
    if (prerelease == other.prerelease) return 0;
    if (prerelease == null) return 1;
    if (other.prerelease == null) return -1;
    return prerelease!.compareTo(other.prerelease!);
  }
}

String? releaseTag(Uri? uri) {
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host != 'github.com' ||
      uri.userInfo.isNotEmpty ||
      uri.port != 443) {
    return null;
  }
  final parts = uri.pathSegments;
  if (parts.length != 5 ||
      parts.take(4).join('/') != 'LexianLix/manxia/releases/tag') {
    return null;
  }
  return ReleaseVersion.parse(parts.last) == null ? null : parts.last;
}

class UpdateRelease {
  UpdateRelease({
    required this.tag,
    required this.body,
    required this.uri,
    required this.publicPage,
    required this.hasApk,
  });
  final String tag, body;
  final Uri uri;
  final bool publicPage, hasApk;
  int? compareInstalled(String installed) {
    final current = ReleaseVersion.parse(installed),
        latest = ReleaseVersion.parse(tag);
    return current == null || latest == null ? null : latest.compareTo(current);
  }

  factory UpdateRelease.fromJson(Map<String, dynamic> json) {
    final tag = json['tag_name'];
    if (tag is! String ||
        ReleaseVersion.parse(tag) == null ||
        json['draft'] == true ||
        json['prerelease'] == true) {
      throw const FormatException('Invalid stable release');
    }
    final uri = Uri.https('github.com', '/LexianLix/manxia/releases/tag/$tag');
    final assets = json['assets'];
    return UpdateRelease(
      tag: tag,
      body: json['body'] is String ? json['body'] : '',
      uri: uri,
      publicPage: json['source'] == 'public-page',
      hasApk:
          assets is List &&
          assets.any(
            (a) =>
                a is Map &&
                a['name'] is String &&
                (a['name'] as String).startsWith('Manxia-') &&
                (a['name'] as String).endsWith('.apk'),
          ),
    );
  }
}

class UpdateCheckException implements Exception {
  UpdateCheckException(this.message);
  final String message;
  @override
  String toString() => message;
}

Future<UpdateRelease> inspectUpdate(
  CheckControl control, {
  Uri? gateway,
  http.Client? transport,
  Duration timeout = const Duration(seconds: 25),
  void Function()? onPublicFallback,
}) async {
  final client = transport ?? http.Client();
  final close = client.close;
  control.onCancel(close);
  final watch = Stopwatch()..start();
  Future<T> step<T>(Future<T> Function() task, {Duration? limit}) {
    control.ensureActive();
    final remaining = timeout - watch.elapsed;
    if (remaining <= Duration.zero) throw TimeoutException('update check');
    final budget = limit != null && limit < remaining ? limit : remaining;
    return control.wait(task().timeout(budget));
  }

  try {
    try {
      final r = await step(
        () => client.get(
          gateway?.resolve('/api/update') ?? githubLatestApi,
          headers: {'Accept': 'application/vnd.github+json'},
        ),
        limit: const Duration(seconds: 6),
      );
      if (r.statusCode == 200) {
        return UpdateRelease.fromJson(
          jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>,
        );
      }
    } on CheckCancelled {
      rethrow;
    } catch (_) {
      /* Try the same repository's public release redirect. */
    }
    control.ensureActive();
    if (gateway != null) {
      throw UpdateCheckException('无法读取版本信息，请重试或打开 GitHub 发行页。');
    }
    onPublicFallback?.call();
    final request = http.Request('HEAD', githubLatestPage)
      ..followRedirects = false;
    final response = await step(() => client.send(request));
    Uri? uri;
    if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
      uri = githubLatestPage.resolve(response.headers['location'] ?? '');
      await step(() => response.stream.listen(null).cancel());
    } else if (response.statusCode == 200) {
      final r = await step(() => http.Response.fromStream(response));
      final document = html.parse(utf8.decode(r.bodyBytes));
      final value =
          document
              .querySelector('meta[property="og:url"]')
              ?.attributes['content'] ??
          document.querySelector('link[rel="canonical"]')?.attributes['href'];
      uri = value == null ? null : Uri.tryParse(value);
    }
    final tag = releaseTag(uri);
    if (tag == null) throw UpdateCheckException('无法读取版本信息，请重试或打开 GitHub 发行页。');
    return UpdateRelease(
      tag: tag,
      body: '',
      uri: uri!,
      publicPage: true,
      hasApk: false,
    );
  } on CheckCancelled {
    rethrow;
  } on UpdateCheckException {
    rethrow;
  } on TimeoutException {
    throw UpdateCheckException('连接 GitHub 超时，请重试或在浏览器打开发行页。');
  } catch (_) {
    throw UpdateCheckException('无法连接 GitHub，请检查网络或在浏览器打开发行页。');
  } finally {
    control.removeCancel(close);
    client.close();
  }
}
