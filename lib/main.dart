import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'data/library.dart';
import 'data/plugin.dart';
import 'ui/app_shell.dart';
import 'ui/room_motion.dart';
import 'ui/room_scroll.dart';
import 'ui/startup.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSizeBytes = 96 * 1024 * 1024;
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Source Han Serif CN',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
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
        child: child!,
      ),
      themeMode: library.dark ? ThemeMode.dark : ThemeMode.light,
      theme: _theme(false),
      darkTheme: _theme(true),
      home: AppShell(library: library, web: kIsWeb),
    ),
  );
  ThemeData _theme(bool dark) {
    final theme = PluginSnapshot(library.options).theme;
    Color color(String key, Color fallback) => theme[key] is String
        ? Color(
            0xff000000 |
                int.parse((theme[key] as String).substring(1), radix: 16),
          )
        : fallback;
    final seed = color('seed', const Color(0xff47775e));
    final primary = dark ? Color.lerp(seed, Colors.white, .50)! : seed;
    final scheme = ColorScheme.fromSeed(
      contrastLevel: library.option<bool>('highContrast', false) ? 1 : 0,
      seedColor: seed,
      brightness: dark ? Brightness.dark : Brightness.light,
      surface: dark
          ? color('darkSurface', const Color(0xff171d1a))
          : color('lightSurface', const Color(0xfff7f7f2)),
      primary: primary,
      onPrimary:
          ThemeData.estimateBrightnessForColor(primary) == Brightness.dark
          ? Colors.white
          : const Color(0xff18211d),
    );
    return ThemeData(
      useMaterial3: true,
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
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontFamily: 'ArchiveSerif',
          fontSize: 18,
          color: scheme.onSurface,
        ),
      ),
      listTileTheme: ListTileThemeData(
        minVerticalPadding: 8,
        titleTextStyle: TextStyle(
          fontSize: 14,
          fontFamily: 'ArchiveSerif',
          color: scheme.onSurface,
        ),
        subtitleTextStyle: TextStyle(
          fontSize: 12,
          fontFamily: 'ArchiveSerif',
          color: scheme.onSurfaceVariant,
        ),
        textColor: scheme.onSurface,
      ),
      iconTheme: const IconThemeData(size: 21),
      scaffoldBackgroundColor: scheme.surface,
      fontFamily: 'ArchiveSerif',
      dividerColor: dark ? const Color(0xff354038) : const Color(0xffdfe3d9),
      splashFactory: InkSparkle.splashFactory,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.onSurface.withValues(alpha: .035),
        border: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(8),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 12,
        ),
      ),
    );
  }
}
