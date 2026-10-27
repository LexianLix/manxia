import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:manxia/data/appearance.dart';
import 'package:manxia/data/library.dart';
import 'package:manxia/platform/blob_store.dart';
import 'package:manxia/ui/glass_navigation.dart';
import 'package:manxia/ui/materials.dart';
import 'package:manxia/ui/room_backdrop.dart';

void main() {
  test(
    'wallpaper palette keeps a chromatic family and handles neutral pixels',
    () {
      final pixels = Uint8List.fromList([
        for (var i = 0; i < 40; i++) ...[30, 150, 210, 255],
        for (var i = 0; i < 400; i++) ...[255, 255, 255, 255],
        for (var i = 0; i < 10; i++) ...[240, 120, 40, 255],
      ]);
      final hue = HSLColor.fromColor(wallpaperSeed(pixels)).hue;
      expect(hue, inInclusiveRange(190, 210));
      expect(wallpaperSeed(Uint8List(32)), RoomAppearance.defaultSeed);
      final primary = ColorScheme.fromSeed(
        seedColor: wallpaperSeed(pixels),
      ).primary;
      final onPrimary = ColorScheme.fromSeed(
        seedColor: wallpaperSeed(pixels),
      ).onPrimary;
      final luminances = [
        primary.computeLuminance(),
        onPrimary.computeLuminance(),
      ]..sort();
      expect(
        (luminances.last + .05) / (luminances.first + .05),
        greaterThan(4.5),
      );
    },
  );

  test(
    'invalid imported appearance metadata falls back without a startup error',
    () {
      for (final raw in [
        null,
        'not a map',
        12,
        {
          'wallpaper': '../secret',
          'veil': 'bad',
          'blur': double.nan,
          'name': 42,
        },
      ]) {
        final value = RoomAppearance({'appearance': raw});
        expect(value.wallpaper, isNull);
        expect(value.seed, RoomAppearance.defaultSeed);
        expect(value.veil, .58);
        expect(value.blur, 0);
        expect(value.name, '');
      }
    },
  );

  testWidgets(
    'wallpaper survives storage reopen, is bounded, and a failed import preserves it',
    (tester) async {
      await tester.runAsync(() async {
        final blobs = MemoryBlobStore();
        final store = WallpaperStore(store: blobs);
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(const Color(0xff3296bc), BlendMode.src);
        final picture = recorder.endRecording();
        final original = await picture.toImage(2400, 1200);
        final encoded = await original.toByteData(
          format: ui.ImageByteFormat.png,
        );
        original.dispose();
        picture.dispose();
        final saved = await store.save(encoded!.buffer.asUint8List());
        expect(saved.key, matches(RegExp(r'^[a-f0-9]{64}$')));
        final reopened = WallpaperStore(store: blobs);
        final bytes = await reopened.read(saved.key);
        final codec = await ui.instantiateImageCodec(bytes!);
        final image = (await codec.getNextFrame()).image;
        expect(image.width, 1920);
        expect(image.height, 960);
        image.dispose();
        codec.dispose();
        await expectLater(store.save(Uint8List(0)), throwsFormatException);
        await expectLater(
          store.save(Uint8List.fromList([1, 2, 3])),
          throwsA(anything),
        );
        expect(await reopened.read(saved.key), bytes);
        SharedPreferences.setMockInitialValues({});
        final library = Library(await SharedPreferences.getInstance());
        await library.load();
        await library.setOption('appearance', {
          'wallpaper': saved.key,
          'seed': saved.seed.toARGB32(),
          'name': 'test.png',
          'veil': .5,
        });
        final restored = Library(library.prefs);
        await restored.load();
        expect(RoomAppearance(restored.options).wallpaper, saved.key);
        expect(RoomAppearance(restored.options).seed, saved.seed);
        expect(restored.favorites, isEmpty);
        expect(
          restored.readerOptions(restored.samples.first)['background'],
          'theme',
        );
        await library.setReaderOption(
          library.samples.first,
          'background',
          'ink',
        );
        expect(
          library.readerOptions(library.samples.first)['background'],
          'ink',
        );
        await store.remove(saved.key);
        expect(await WallpaperStore(store: blobs).read(saved.key), isNull);
      });
    },
  );

  testWidgets(
    'missing local wallpaper shows the themed room and leaves navigation usable',
    (tester) async {
      late Library library;
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        library = Library(await SharedPreferences.getInstance());
        await library.load();
        await library.setOption('appearance', {
          'wallpaper': 'a' * 64,
          'seed': 0xff3296bc,
        });
      });
      await tester.pumpWidget(
        MaterialApp(
          home: RoomBackdrop(
            library: library,
            store: WallpaperStore(store: MemoryBlobStore()),
            child: const Scaffold(body: Center(child: Text('Library'))),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Library').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final scale in [1.0, 1.5]) {
    testWidgets(
      'compact glass lens and animated icon share a center at text scale $scale',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var index = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, set) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  bottomNavigationBar: FrostedNavigation(
                    destinations: [
                      for (final id in [0, 1, 4, 5, 3]) roomDestinations[id],
                    ],
                    selectedIndex: index,
                    haptics: false,
                    onSelected: (value) => set(() => index = value),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final bar = tester.getRect(find.byType(MilkGlass));
        expect(bar.width, 314);
        expect(bar.height, lessThanOrEqualTo(scale == 1 ? 54 : 61));
        expect(bar.center.dx, 195);
        final lens = find.byKey(const ValueKey('navigation-lens'));
        for (final (position, id) in [(4, 3), (0, 0)]) {
          await tester.tap(find.byTooltip(id == 0 ? 'Library' : 'Settings'));
          await tester.pumpAndSettle();
          expect(index, position);
          expect(
            (tester.getCenter(lens) -
                    tester.getCenter(
                      find.byKey(ValueKey('navigation-icon-$id')),
                    ))
                .distance,
            lessThan(.5),
          );
          expect(tester.getRect(lens).height, 34);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
