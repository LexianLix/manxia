import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/ui/reader_preloader.dart';

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'chapter changes discard queued old pages and serialize decoding',
    () async {
      final calls = <(String, int)>[];
      final pending = <Completer<bool>>[];
      final loader = ReaderPreloader((url, width) {
        calls.add((url, width));
        final response = Completer<bool>();
        pending.add(response);
        return response.future;
      });
      loader.replace(['old-1', 'old-2', 'old-3'], 1500);
      expect(calls, [('old-1', 1500)]);
      loader.replace(['new-1', 'new-2'], 1000);
      expect(calls, hasLength(1));
      pending[0].complete(true);
      await flush();
      expect(calls, [('old-1', 1500), ('new-1', 1000)]);
      loader.dispose();
      pending[1].complete(true);
      await flush();
      expect(calls, hasLength(2));
    },
  );
  test(
    'failed requests retry and a changed decode width uses a new key',
    () async {
      final calls = <(String, int)>[];
      var success = false;
      final loader = ReaderPreloader((url, width) async {
        calls.add((url, width));
        return success;
      });
      addTearDown(loader.dispose);
      loader.replace(['page', 'page'], 1000);
      await flush();
      success = true;
      loader.replace(['page'], 1000);
      await flush();
      loader.replace(['page'], 1000);
      await flush();
      expect(calls, [('page', 1000), ('page', 1000)]);
      loader.replace(['page'], 2200);
      await flush();
      expect(calls.last, ('page', 2200));
    },
  );
}
