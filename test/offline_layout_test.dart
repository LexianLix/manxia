import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/data/dm5_source.dart';
import 'package:manxia/data/offline_library.dart';
import 'package:manxia/platform/blob_store.dart';
import 'package:manxia/ui/offline_page.dart';
import 'features_test.dart' as fixtures;

void main() {
  testWidgets(
    'offline empty state remains scrollable in enlarged landscape layout',
    (tester) async {
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(
        () => (FontLoader(
          'RoomSans',
        )..addFont(rootBundle.load('assets/fonts/NotoSansSC.ttf'))).load(),
      );
      final library = await fixtures.library();
      final source = Dm5Source();
      final offline = OfflineLibrary(library, source, store: MemoryBlobStore());
      await offline.initialize();
      addTearDown(() {
        source.close();
        OfflineLibrary.instance = null;
        Dm5Source.offlineDetail = null;
        Dm5Source.offlinePages = null;
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'RoomSans'),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Padding(
            padding: const EdgeInsets.only(bottom: 98),
            child: OfflinePage(library: library, source: source, web: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final importButton = find.byType(FilledButton);
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -800),
      );
      await tester.pumpAndSettle();
      final viewport = tester.getRect(find.byType(SingleChildScrollView));
      final button = tester.getRect(importButton);
      expect(button.top, greaterThanOrEqualTo(viewport.top));
      expect(button.bottom, lessThanOrEqualTo(viewport.bottom));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
