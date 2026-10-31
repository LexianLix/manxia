import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/dm5_source.dart';
import 'package:manxia/data/offline_library.dart';
import 'package:manxia/platform/blob_store.dart';
import 'package:manxia/platform/network_monitor.dart';
import 'features_test.dart' as fixtures;
import 'offline_queue_test.dart' show until;

class _Source extends Dm5Source {
  @override
  Future<List<String>> networkPages(String path) async => [
    'https://images.cdndm5.com/1.png',
    'https://images.cdndm5.com/2.png',
  ];
}

class _Probe extends http.BaseClient {
  final calls = <String>[];
  bool aborted = false, blocked = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls.add(request.url.path);
    if (request.url.path == '/2.png' && !blocked) {
      blocked = true;
      await (request as http.Abortable).abortTrigger;
      aborted = true;
      throw http.RequestAbortedException(request.url);
    }
    return http.StreamedResponse(
      Stream.value(Uint8List.fromList([1, 2, 3])),
      200,
      headers: {'content-type': 'image/png'},
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    OfflineLibrary.instance = null;
    Dm5Source.offlinePages = null;
    Dm5Source.offlineDetail = null;
  });
  test(
    'automatic downloads require unmetered Wi-Fi even when manual cellular downloads are allowed',
    () async {
      final library = await fixtures.library();
      final network = NetworkMonitor(
        native: false,
        initial: const NetworkInfo('mobile', metered: true),
      );
      final source = _Source();
      var calls = 0;
      final offline = OfflineLibrary(
        library,
        source,
        store: MemoryBlobStore(),
        network: network,
        client: MockClient((_) async {
          calls++;
          return http.Response.bytes(
            [1],
            200,
            headers: {'content-type': 'image/png'},
          );
        }),
      );
      addTearDown(() {
        offline.dispose();
        source.close();
      });
      await offline.initialize();
      await offline.prepareNext(fixtures.comic, [
        const Chapter('/auto/', 'Automatic'),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(calls, 0);
      expect(offline.entries.single['pauseReason'], 'network');
      await offline.enqueue(
        fixtures.comic,
        const Chapter('/manual/', 'Manual'),
      );
      await until(() => offline.entries.last['status'] == 'complete');
      expect(offline.entries.first['status'], 'paused');
      network.value = const NetworkInfo('wifi', metered: true);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(offline.entries.first['status'], 'paused');
      network.value = const NetworkInfo('wifi');
      await until(() => offline.entries.first['status'] == 'complete');
    },
  );
  test(
    'network change cancels the in-flight page and resumes without fetching completed pages again',
    () async {
      final library = await fixtures.library();
      await library.setOption('downloadWifiOnly', true);
      final network = NetworkMonitor(
        native: false,
        initial: const NetworkInfo('wifi'),
      );
      final client = _Probe(), source = _Source();
      final offline = OfflineLibrary(
        library,
        source,
        store: MemoryBlobStore(),
        client: client,
        network: network,
      );
      addTearDown(() {
        offline.dispose();
        source.close();
      });
      await offline.initialize();
      await offline.enqueue(fixtures.comic, const Chapter('/net/', 'Network'));
      await until(() => client.blocked);
      network.value = const NetworkInfo('mobile', metered: true);
      await until(
        () =>
            client.aborted && !offline.isRunning(offline.entries.single['id']),
      );
      expect(offline.entries.single['status'], 'paused');
      expect(offline.entries.single['done'], 1);
      network.value = const NetworkInfo('wifi');
      await until(() => offline.entries.single['status'] == 'complete');
      expect(client.calls.where((p) => p == '/1.png'), hasLength(1));
      expect(client.calls.where((p) => p == '/2.png'), hasLength(2));
    },
  );
  test(
    'Wi-Fi rule sends no cellular requests and network recovery never overrides manual pause',
    () async {
      final library = await fixtures.library();
      await library.setOption('downloadWifiOnly', true);
      final network = NetworkMonitor(
        native: false,
        initial: const NetworkInfo('mobile', metered: true),
      );
      var calls = 0;
      final source = _Source();
      final offline = OfflineLibrary(
        library,
        source,
        store: MemoryBlobStore(),
        network: network,
        client: MockClient((_) async {
          calls++;
          return http.Response.bytes(
            [1],
            200,
            headers: {'content-type': 'image/png'},
          );
        }),
      );
      addTearDown(() {
        offline.dispose();
        source.close();
      });
      await offline.initialize();
      await offline.enqueue(
        fixtures.comic,
        const Chapter('/manual/', 'Manual'),
      );
      expect(calls, 0);
      expect(offline.entries.single['pauseReason'], 'network');
      await offline.pause(offline.entries.single['id']);
      network.value = const NetworkInfo('wifi');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(calls, 0);
      await offline.resume(offline.entries.single['id']);
      await until(() => offline.entries.single['status'] == 'complete');
      expect(calls, greaterThan(0));
    },
  );
  test(
    'smart window is bounded, deduplicated and retains manual downloads',
    () async {
      final library = await fixtures.library();
      await library.setOption('downloadWifiOnly', true);
      final source = _Source();
      final offline = OfflineLibrary(
        library,
        source,
        store: MemoryBlobStore(),
        network: NetworkMonitor(
          native: false,
          initial: const NetworkInfo('mobile'),
        ),
      );
      addTearDown(() {
        offline.dispose();
        source.close();
      });
      await offline.initialize();
      await offline.enqueue(
        fixtures.comic,
        const Chapter('/manual/', 'Manual'),
      );
      final chapters = List.generate(
        100,
        (i) => Chapter('/auto-$i/', 'Auto $i'),
      );
      await offline.prepareNext(fixtures.comic, chapters);
      await offline.prepareNext(fixtures.comic, chapters);
      expect(offline.entries, hasLength(11));
      await offline.prepareNext(fixtures.comic, chapters.skip(30).take(3));
      expect(offline.entries, hasLength(4));
      expect(
        offline.entries.where((e) => e['automatic'] == true),
        hasLength(3),
      );
      await offline.prepareNext(fixtures.comic, []);
      expect(offline.entries.single['chapter']['path'], '/manual/');
    },
  );
  for (final resume in [false, true]) {
    test(
      'restart policy keeps partial files and respects resume setting: $resume',
      () async {
        final library = await fixtures.library();
        await library.setOption('resumeDownloadsOnLaunch', resume);
        final source = _Source(), store = MemoryBlobStore();
        final calls = <String>[];
        final offline = OfflineLibrary(
          library,
          source,
          store: store,
          network: NetworkMonitor(
            native: false,
            initial: const NetworkInfo('wifi'),
          ),
          client: MockClient((r) async {
            calls.add(r.url.path);
            return http.Response.bytes(
              [2],
              200,
              headers: {'content-type': 'image/png'},
            );
          }),
        );
        addTearDown(() {
          offline.dispose();
          source.close();
        });
        final key = offline.key('/resume//0');
        await store.write(key, Uint8List.fromList([1]));
        await library.prefs.setString(
          'offline.v1',
          jsonEncode([
            {
              'id': 'resume',
              'comic': fixtures.comic.toJson(),
              'chapter': const Chapter('/resume/', 'Resume').toJson(),
              'status': 'downloading',
              'urls': [
                'https://images.cdndm5.com/1.png',
                'https://images.cdndm5.com/2.png',
              ],
              'keys': [key],
              'done': 1,
              'total': 2,
              'bytes': 1,
              'local': false,
            },
          ]),
        );
        await offline.initialize();
        if (resume) {
          await until(() => offline.entries.single['status'] == 'complete');
        } else {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          expect(offline.entries.single['status'], 'paused');
        }
        expect(calls, isNot(contains('/1.png')));
        expect(await store.read(key), [1]);
      },
    );
  }
}
