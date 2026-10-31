import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/data/comic.dart';
import 'package:manxia/data/dm5_source.dart';
import 'package:manxia/data/library.dart';
import 'package:manxia/data/offline_library.dart';
import 'package:manxia/ui/reader_page.dart';
import 'package:manxia/ui/reader_surfaces.dart';
import 'features_test.dart' as fixtures;
import 'reader_test.dart' show cacheReaderImages, settleFirstFrame;

class _Source extends Dm5Source {
  @override
  Future<List<String>> pages(String path) async => [
    'https://images.cdndm5.com/1.jpg',
    'https://images.cdndm5.com/2.jpg',
  ];
}

void main() {
  for (final reduced in [false, true]) {
    testWidgets(
      'double tap zoom retains page and reverses from current transform: $reduced',
      (tester) async {
        late Library library;
        await tester.runAsync(() async {
          library = await fixtures.library();
          await cacheReaderImages(library);
          await library.setReaderOption(
            library.samples.first,
            'doubleTapZoom',
            true,
          );
        });
        final source = _Source();
        addTearDown(() {
          source.close();
          OfflineLibrary.instance?.source.close();
          OfflineLibrary.instance = null;
        });
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
              child: child!,
            ),
            home: ReaderPage(
              comic: library.samples.first,
              chapter: const Chapter('/one/', 'One'),
              chapters: const [Chapter('/one/', 'One')],
              initialPage: 1,
              library: library,
              source: source,
              web: false,
            ),
          ),
        );
        await settleFirstFrame(tester);
        final surface = tester.widget<PagedSurface>(
          find.byType(PagedSurface).last,
        );
        final position = tester.getCenter(find.byType(PagedSurface));
        await tester.tapAt(position);
        await tester.pump(const Duration(milliseconds: 70));
        await tester.tapAt(position);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        final viewer = tester.widget<InteractiveViewer>(
          find.byType(InteractiveViewer),
        );
        final middle = Matrix4.copy(viewer.transformationController!.value);
        expect(middle.getMaxScaleOnAxis(), greaterThan(1));
        surface.control.onZoom!(position);
        expect(
          viewer.transformationController!.value.getMaxScaleOnAxis(),
          closeTo(reduced ? 1 : middle.getMaxScaleOnAxis(), .001),
        );
        await tester.pumpAndSettle();
        expect(
          viewer.transformationController!.value.getMaxScaleOnAxis(),
          closeTo(1, .001),
        );
        expect(library.record(library.samples.first)!.page, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
