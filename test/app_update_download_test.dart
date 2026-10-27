import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:crypto/crypto.dart';
import 'package:manxia/platform/app_update_native.dart';
import 'package:manxia/data/settings_checks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('manxia-update-test-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => directory.path,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          AppUpdateDownload.channel,
          (call) async => {
            'abis': ['arm64-v8a', 'armeabi-v7a'],
          },
        );
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppUpdateDownload.channel, null);
    // This directory is created uniquely by this test and contains no library data.
    await directory.delete(recursive: true);
  });
  final release = UpdateRelease(
    tag: 'v0.3.9',
    body: '',
    uri: Uri.parse('https://github.com/LexianLix/manxia/releases/tag/v0.3.9'),
    publicPage: true,
    hasApk: false,
  );
  const bytes = [1, 2, 3, 4, 5];
  Map<String, dynamic> manifest({bool valid = true}) => {
    'version': '0.3.9+18',
    'mode': 'release',
    'applicationId': 'io.manxia.manxia',
    'packages': [
      {
        'name': 'Manxia-0.3.9-arm64-v8a.apk',
        'abi': 'arm64-v8a',
        'versionCode': 2018,
        'bytes': bytes.length,
        'sha256': valid ? sha256.convert(bytes).toString() : '0' * 64,
      },
    ],
  };
  test(
    'download verifies bytes, reuses only a verified complete APK and leaves user files intact',
    () async {
      final marker = File('${directory.path}/library.json');
      await marker.writeAsString('favorites');
      var reads = 0;
      await http.runWithClient(
        () async {
          final file = await AppUpdateDownload.download(
            release,
            CheckControl(),
            (_, _) {},
          );
          expect(await File(file).readAsBytes(), bytes);
          expect(file.endsWith('.apk'), isTrue);
          expect(
            await AppUpdateDownload.download(
              release,
              CheckControl(),
              (_, _) {},
            ),
            file,
          );
          expect(reads, 1);
          expect(await marker.readAsString(), 'favorites');
        },
        () => MockClient(
          (r) async => r.url.path.endsWith('.json')
              ? http.Response(jsonEncode(manifest()), 200)
              : (() {
                  reads++;
                  return http.Response.bytes(bytes, 200);
                })(),
        ),
      );
    },
  );
  test(
    'corrupted payload removes only its partial file and cannot be installed',
    () async {
      await http.runWithClient(
        () async {
          await expectLater(
            AppUpdateDownload.download(release, CheckControl(), (_, _) {}),
            throwsFormatException,
          );
          expect(
            await Directory('${directory.path}/updates').list().toList(),
            isEmpty,
          );
        },
        () => MockClient(
          (r) async => r.url.path.endsWith('.json')
              ? http.Response(jsonEncode(manifest(valid: false)), 200)
              : http.Response.bytes(bytes, 200),
        ),
      );
    },
  );
  test(
    'cancel interrupts a stalled body instead of waiting for its network timeout',
    () async {
      final body = StreamController<List<int>>(),
          started = Completer<void>(),
          control = CheckControl();
      await http.runWithClient(
        () async {
          final result = AppUpdateDownload.download(
            release,
            control,
            (_, _) {},
          );
          final assertion = expectLater(result, throwsA(isA<CheckCancelled>()));
          await started.future;
          control.cancel();
          await assertion.timeout(const Duration(seconds: 2));
          expect(
            await Directory('${directory.path}/updates').list().toList(),
            isEmpty,
          );
        },
        () => MockClient.streaming((r, _) async {
          if (r.url.path.endsWith('.json')) {
            return http.StreamedResponse(
              Stream.value(utf8.encode(jsonEncode(manifest()))),
              200,
            );
          }
          started.complete();
          return http.StreamedResponse(
            body.stream,
            200,
            contentLength: bytes.length,
          );
        }),
      );
      await body.close();
    },
  );
}
