import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'data/library.dart';
import 'data/plugin.dart';
import 'data/appearance.dart';
import 'ui/app_shell.dart';
import 'ui/room_motion.dart';
import 'ui/room_scroll.dart';
import 'ui/startup.dart';
import 'ui/room_backdrop.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSizeBytes = 96 * 1024 * 1024;
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Source Han Serif CN',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
    yield LicenseEntryWithLineBreaks([
      'Noto Sans SC',
    ], await rootBundle.loadString('assets/fonts/NotoSansSC-OFL.txt'));
  });
  runApp(ManxiaStartup(builder: (library) => ManxiaApp(library: library)));
}

class ManxiaApp extends StatelessWidget {
  const ManxiaApp({super.key, required this.library});
  final Library library;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: library,
    builder: (context, _) => MaterialApp(
      title: '漫匣 · 把故事留在手边',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const RoomScrollBehavior(),
      locale: switch (library.option<String>('language', 'zh_CN')) {
        'en' => const Locale('en'),
        'zh_TW' => const Locale('zh', 'TW'),
        _ => const Locale('zh', 'CN'),
      },
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('zh', 'TW'),
        Locale('en'),
      ],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(library.option<double>('textScale', 1)),
          highContrast: library.option<bool>('highContrast', false),
          disableAnimations:
              MediaQuery.disableAnimationsOf(context) || !library.motion,
        ),
        child: RoomBackdrop(library: library, child: child!),
      ),
      themeMode: library.dark ? ThemeMode.dark : ThemeMode.light,
      theme: _theme(false),
      darkTheme: _theme(true),
      home: AppShell(library: library, web: kIsWeb),
    ),
  );
  ThemeData _theme(bool dark) {
    final theme = PluginSnapshot(library.options).theme;
    final appearance = RoomAppearance(library.options);
    Color color(String key, Color fallback) => theme[key] is String
        ? Color(
            0xff000000 |
                int.parse((theme[key] as String).substring(1), radix: 16),
          )
        : fallback;
    final seed = appearance.wallpaper != null && appearance.follow
        ? appearance.seed
        : color('seed', RoomAppearance.defaultSeed);
    final scheme = ColorScheme.fromSeed(
      contrastLevel: library.option<bool>('highContrast', false) ? 1 : 0,
      seedColor: seed,
      brightness: dark ? Brightness.dark : Brightness.light,
      surface: appearance.wallpaper != null && appearance.follow
          ? RoomAppearance.surface(seed, dark)
          : color(
              dark ? 'darkSurface' : 'lightSurface',
              RoomAppearance.surface(seed, dark),
            ),
    );
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'RoomSans',
      fontFamilyFallback: const ['ArchiveSerif'],
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: RoomPageTransitions(),
          TargetPlatform.windows: RoomPageTransitions(),
          TargetPlatform.linux: RoomPageTransitions(),
          TargetPlatform.macOS: RoomPageTransitions(),
          TargetPlatform.iOS: RoomPageTransitions(),
        },
      ),
      colorScheme: scheme,
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface.withValues(alpha: .78),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 54,
        titleTextStyle: TextStyle(
          fontFamily: 'RoomSans',
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      listTileTheme: ListTileThemeData(
        minVerticalPadding: 8,
        titleTextStyle: TextStyle(
          fontFamily: 'RoomSans',
          fontSize: 14,
          color: scheme.onSurface,
        ),
        subtitleTextStyle: TextStyle(
          fontFamily: 'RoomSans',
          fontSize: 12,
          color: scheme.onSurfaceVariant,
        ),
        textColor: scheme.onSurface,
      ),
      iconTheme: IconThemeData(size: 21, color: scheme.onSurface),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: scheme.onSurface,
          disabledForegroundColor: scheme.onSurface.withValues(alpha: .35),
        ),
      ),
      scaffoldBackgroundColor: Colors.transparent,
      dividerColor: scheme.onSurface.withValues(alpha: .09),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 3,
        activeTrackColor: scheme.primary,
      ),
      cardTheme: CardThemeData(
        color: scheme.surface.withValues(alpha: .68),
        elevation: 0,
      ),
      splashFactory: InkSparkle.splashFactory,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.onSurface.withValues(alpha: .035),
        border: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(14),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 12,
        ),
      ),
    );
  }
}
