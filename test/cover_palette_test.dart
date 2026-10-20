import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/ui/cover_palette.dart';

void main() {
  testWidgets('tiny cached cover readback preserves the actual colour', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawRect(
        const ui.Rect.fromLTWH(0, 0, 512, 768),
        ui.Paint()..color = const ui.Color(0xff446688),
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(512, 768);
      try {
        final first = CoverPalette.average('palette-test', image);
        final second = CoverPalette.average('palette-test', image);
        expect(identical(first, second), isTrue);
        expect((await first)?.toARGB32(), 0xff446688);
      } finally {
        image.dispose();
        picture.dispose();
      }
    });
  });
}
