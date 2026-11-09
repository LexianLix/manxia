import 'dart:convert';
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
import 'ui/companion.dart';
import 'ui/adaptive_glass.dart';

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

class ManxiaApp extends StatefulWidget {
  const ManxiaApp({super.key, required this.library});
  final Library library;
  @override
  State<ManxiaApp> createState() => _ManxiaAppState();
}

class _ManxiaAppState extends State<ManxiaApp> {
  Library get library => widget.library;
  String get signature =>
      jsonEncode([library.dark, library.motion, library.options]);
  late String configuration;
  @override
  void initState() {
    super.initState();
    configuration = signature;
    library.addListener(preferencesChanged);
  }

  void preferencesChanged() {
    final next = signature;
    if (configuration != next) setState(() => configuration = next);
  }

  @override
  void didUpdateWidget(ManxiaApp old) {
    super.didUpdateWidget(old);
    if (old.library != library) {
      old.library.removeListener(preferencesChanged);
      library.addListener(preferencesChanged);
      configuration = signature;
    }
  }

  @override
  void dispose() {
    library.removeListener(preferencesChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
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
        highContrast:
            MediaQuery.highContrastOf(context) ||
            library.option<bool>('highContrast', false),
        disableAnimations:
            MediaQuery.disableAnimationsOf(context) || !library.motion,
      ),
      child: AdaptiveGlass(
        high: library.option<String>('quality', 'high') == 'high',
        child: CompanionScope(
          library: library,
          child: RoomBackdrop(library: library, child: child!),
        ),
      ),
    ),
    themeMode: library.dark ? ThemeMode.dark : ThemeMode.light,
    theme: _theme(false),
    darkTheme: _theme(true),
    home: AppShell(library: library, web: kIsWeb),
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
      dynamicSchemeVariant:
          (appearance.wallpaper == null || !appearance.follow) &&
              theme['seed'] == null
          ? DynamicSchemeVariant.monochrome
          : DynamicSchemeVariant.tonalSpot,
      contrastLevel: library.option<bool>('highContrast', false) ? 1 : 0,
      seedColor: seed,
      primary:
          (appearance.wallpaper == null || !appearance.follow) &&
              theme['seed'] == null &&
              !library.option<bool>('highContrast', false)
          ? (dark ? const Color(0xffd3d5dd) : const Color(0xff303238))
          : null,
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
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w600,
          height: 1.2,
          letterSpacing: -.8,
        ),
        headlineMedium: TextStyle(
          fontSize: 25,
          fontWeight: FontWeight.w600,
          height: 1.25,
          letterSpacing: -.6,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          height: 1.3,
          letterSpacing: -.3,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          height: 1.4,
        ),
        bodyLarge: TextStyle(fontSize: 16, height: 1.45),
        bodyMedium: TextStyle(fontSize: 14, height: 1.45),
        bodySmall: TextStyle(fontSize: 12, height: 1.4),
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 54,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: 'RoomSans',
          fontSize: 17,
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
        inactiveTrackColor: scheme.onSurface.withValues(alpha: .10),
        thumbColor: Colors.white,
        thumbShape: const RoundSliderThumbShape(
          enabledThumbRadius: 8,
          elevation: 1,
          pressedElevation: 2,
        ),
        activeTickMarkColor: Colors.transparent,
        inactiveTickMarkColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: scheme.surface.withValues(alpha: .68),
        elevation: 0,
      ),
      splashFactory: NoSplash.splashFactory,
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.onSurface.withValues(alpha: .14),
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      chipTheme: ChipThemeData(
        showCheckmark: false,
        side: BorderSide.none,
        shape: const StadiumBorder(),
        backgroundColor: scheme.onSurface.withValues(alpha: .045),
        selectedColor: scheme.primary.withValues(alpha: .12),
        labelStyle: TextStyle(
          fontFamily: 'RoomSans',
          fontSize: 13,
          color: scheme.onSurface,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          side: const WidgetStatePropertyAll(BorderSide.none),
          shape: const WidgetStatePropertyAll(StadiumBorder()),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.surfaceContainerLowest
                : scheme.onSurface.withValues(alpha: .045),
          ),
          foregroundColor: WidgetStatePropertyAll(scheme.onSurface),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(
              fontFamily: 'RoomSans',
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerLowest.withValues(alpha: .97),
        surfaceTintColor: Colors.transparent,
        elevation: 5,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(40, 42),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: BorderSide(
            color: scheme.onSurface.withValues(alpha: .13),
            width: .7,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLowest.withValues(alpha: .75),
        border: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(24),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 12,
        ),
      ),
    );
  }
}
