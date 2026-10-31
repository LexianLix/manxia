import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/ui/reader_gestures.dart';

void main() {
  test(
    'hand presets override side actions while preserving a central controls zone',
    () {
      expect(readerTap(.1, {}, false), ReaderTap.previous);
      expect(readerTap(.1, {}, true), ReaderTap.next);
      expect(readerTap(.1, {'hand': 'left'}, false), ReaderTap.next);
      expect(readerTap(.9, {'hand': 'right'}, true), ReaderTap.next);
      expect(readerTap(.3, {'leftTapWidth': .35}, false), ReaderTap.previous);
      expect(
        readerTap(.5, {'leftTapWidth': 2, 'rightTapWidth': 2}, false),
        ReaderTap.controls,
      );
    },
  );
}
