import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:manxia/data/settings_checks.dart';
import 'package:manxia/data/dm5_source.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/app_update.dart';

void main() {
  test(
    'rate-limited API recovers through the exact public repository redirect',
    () async {
      final calls = <Uri>[];
      final result = await inspectUpdate(
        CheckControl(),
        transport: MockClient((r) async {
          calls.add(r.url);
          return r.url == githubLatestApi
              ? http.Response('{}', 403)
              : http.Response(
                  '',
                  302,
                  headers: {
                    'location': '/LexianLix/manxia/releases/tag/v0.3.10',
                  },
                );
        }),
      );
      expect(result.tag, 'v0.3.10');
      expect(result.publicPage, isTrue);
      expect(result.compareInstalled('0.3.9'), greaterThan(0));
      expect(calls, [githubLatestApi, githubLatestPage]);
      expect(result.compareInstalled('0.3.11'), lessThan(0));
      expect(result.compareInstalled('0.3.10'), 0);
    },
  );
  test(
    'untrusted redirect and malformed release never become a latest version',
    () async {
      for (final location in [
        'https://evil.com/releases/tag/v0.3.10',
        'https://github.com/other/repo/releases/tag/v0.3.10',
      ]) {
        await expectLater(
          inspectUpdate(
            CheckControl(),
            transport: MockClient(
              (r) async => r.url == githubLatestApi
                  ? http.Response('not-json', 200)
                  : http.Response('', 302, headers: {'location': location}),
            ),
          ),
          throwsA(isA<UpdateCheckException>()),
        );
      }
    },
  );
  test(
    'cancel finishes a pending update promptly and prevents late success',
    () async {
      final pending = Completer<http.Response>(), control = CheckControl();
      final result = inspectUpdate(
        control,
        transport: MockClient((_) => pending.future),
      );
      final assertion = expectLater(result, throwsA(isA<CheckCancelled>()));
      control.cancel();
      await assertion;
      pending.complete(http.Response(jsonEncode({'tag_name': 'v99.0.0'}), 200));
    },
  );
  test(
    'source diagnostics skip copyright-only works and verify another network chapter',
    () async {
      final probe = _Source(), control = CheckControl();
      final stages = <SourceCheckStage>[];
      final report = await inspectSource(
        probe,
        control,
        progress: (stage, _) => stages.add(stage),
      );
      expect(report.readable, isTrue);
      expect(report.books, 2);
      expect(report.samples.first.copyright, isTrue);
      expect(report.samples.last.pages, 1);
      expect(stages.last, SourceCheckStage.pages);
      expect(probe.closed, isTrue);
    },
  );
  test(
    'source cancellation closes its owned transport without changing the original source',
    () async {
      final probe = _Source()..pending = Completer<List<Comic>>();
      final control = CheckControl();
      final result = inspectSource(probe, control);
      final assertion = expectLater(result, throwsA(isA<CheckCancelled>()));
      control.cancel();
      await assertion;
      expect(probe.closed, isTrue);
      probe.pending!.complete([]);
    },
  );
  test(
    'diagnostic forks cannot turn offline cached chapters into a healthy network result',
    () async {
      var offlineCalls = 0;
      final old = Dm5Source.offlineDetail;
      Dm5Source.offlineDetail = (c) async {
        offlineCalls++;
        return ComicDetail(c, [const Chapter('/m1/', 'one')]);
      };
      addTearDown(() => Dm5Source.offlineDetail = old);
      await http.runWithClient(() async {
        final original = Dm5Source(), probe = original.forkForCheck();
        try {
          await expectLater(
            probe.detail(_books.first),
            throwsA(isA<SourceException>()),
          );
          expect(offlineCalls, 0);
          expect(probe.allowOffline, isFalse);
          expect(original.allowOffline, isTrue);
        } finally {
          probe.close();
          original.close();
        }
      }, () => MockClient((_) async => http.Response('', 503)));
    },
  );
  test(
    'update manifest selects a supported ABI and rejects path/version/hash substitutions',
    () {
      final release = UpdateRelease(
        tag: 'v0.3.9',
        body: '',
        uri: Uri.parse(
          'https://github.com/LexianLix/manxia/releases/tag/v0.3.9',
        ),
        publicPage: true,
        hasApk: false,
      );
      final manifest = <String, dynamic>{
        'applicationId': 'io.manxia.manxia',
        'mode': 'release',
        'version': '0.3.9+18',
        'packages': [
          {
            'name': 'Manxia-0.3.9-arm64-v8a.apk',
            'abi': 'arm64-v8a',
            'versionCode': 2018,
            'bytes': 100,
            'sha256': 'a' * 64,
          },
        ],
      };
      final package = UpdatePackage.select(manifest, release, [
        'arm64-v8a',
        'armeabi-v7a',
      ]);
      expect(package.versionCode, 2018);
      expect(package.uri.host, 'github.com');
      for (final changed in [
        {...manifest, 'version': '0.3.8+17'},
        {...manifest, 'applicationId': 'other.app'},
        {
          ...manifest,
          'packages': [
            {'abi': 'arm64-v8a', 'name': '../other.apk'},
          ],
        },
      ]) {
        expect(
          () => UpdatePackage.select(changed, release, ['arm64-v8a']),
          throwsFormatException,
        );
      }
      expect(
        () => UpdatePackage.select(manifest, release, ['x86_64']),
        throwsFormatException,
      );
    },
  );
}

const _books = [
  Comic(path: '/removed/', title: '无版权', cover: ''),
  Comic(path: '/available/', title: '可读漫画', cover: ''),
];

class _Source extends Dm5Source {
  bool closed = false;
  Completer<List<Comic>>? pending;
  @override
  Dm5Source forkForCheck() => this;
  @override
  void close() {
    closed = true;
    super.close();
  }

  @override
  Future<List<Comic>> home() async =>
      pending == null ? _books : await pending!.future;
  @override
  Future<ComicDetail> detail(Comic comic) async {
    if (comic.path == '/removed/') throw SourceCopyrightException('没有版权');
    return ComicDetail(comic, [const Chapter('/m1/', '第一话')]);
  }

  @override
  Future<List<String>> networkPages(String path) async => [
    'https://images.cdndm5.com/one.jpg',
    'javascript:bad',
  ];
}
