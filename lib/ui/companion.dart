import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../data/library.dart';
import '../data/plugin.dart';
import '../data/character_definition.dart';
import '../data/character_assets.dart';
import '../data/library_notice.dart';
import 'localized_text.dart';
import 'materials.dart';
import 'room_motion.dart';

class CompanionPreferences {
  CompanionPreferences(Map<String, dynamic> options)
    : values = Map<String, dynamic>.from(
        options['companion'] is Map ? options['companion'] as Map : const {},
      );
  final Map<String, dynamic> values;
  bool get visible => values['visible'] != false;
  bool get animate => values['animate'] != false;
  String get frequency =>
      ['quiet', 'normal', 'off'].contains(values['frequency'])
      ? values['frequency']
      : 'quiet';
  String get size => ['small', 'normal', 'large'].contains(values['size'])
      ? values['size']
      : 'small';
  double get portraitSize => switch (size) {
    'normal' => 112,
    'large' => 144,
    _ => 88,
  };
  String get signature => '$visible:$animate:$frequency:$size';
}

class CompanionScope extends InheritedWidget {
  CompanionScope({super.key, required this.library, required super.child})
    : snapshot = PluginSnapshot(library.options),
      preferences = CompanionPreferences(library.options);
  final Library library;
  final PluginSnapshot snapshot;
  final CompanionPreferences preferences;
  bool get active => preferences.visible && snapshot.character != null;
  static CompanionScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CompanionScope>();
  @override
  bool updateShouldNotify(CompanionScope old) =>
      old.library != library ||
      old.snapshot.character != snapshot.character ||
      old.preferences.signature != preferences.signature;
}

class CompanionPortrait extends StatefulWidget {
  const CompanionPortrait({
    super.key,
    this.expression = 'idle',
    this.size = 64,
    this.definition,
    this.resources = const {},
    this.assets,
  });
  final String expression;
  final double size;
  final CharacterDefinition? definition;
  final Map<String, Uint8List> resources;
  final CharacterAssets? assets;
  @override
  State<CompanionPortrait> createState() => _CompanionPortraitState();
}

class _CompanionPortraitState extends State<CompanionPortrait> {
  String? hash;
  Object? source;
  Future<Uint8List?>? bytes;
  @override
  Widget build(BuildContext context) {
    final scope = CompanionScope.maybeOf(context);
    final definition =
        widget.definition ??
        (scope?.active == true ? scope!.snapshot.character : null);
    if (definition == null) return const SizedBox.shrink();
    final frame = definition.frame(widget.expression),
        assets = widget.assets ?? CharacterAssets.shared;
    final resource = widget.resources[frame.file];
    if (hash != frame.sha256 || !identical(source, resource ?? assets)) {
      hash = frame.sha256;
      source = resource ?? assets;
      bytes = resource == null
          ? assets.read(frame.sha256)
          : Future.value(resource);
    }
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: FutureBuilder<Uint8List?>(
            future: bytes,
            builder: (context, state) {
              if (state.data == null) {
                return Icon(
                  Icons.auto_stories_outlined,
                  size: widget.size * .42,
                  color: Theme.of(context).colorScheme.primary,
                );
              }
              return Image.memory(
                state.data!,
                width: widget.size,
                height: widget.size,
                cacheWidth: 256,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, _, _) =>
                    Icon(Icons.auto_stories_outlined, size: widget.size * .42),
              );
            },
          ),
        ),
      ),
    );
  }
}

class CompanionAvatar extends StatefulWidget {
  const CompanionAvatar({super.key, required this.onPressed});
  final VoidCallback onPressed;
  @override
  State<CompanionAvatar> createState() => _CompanionAvatarState();
}

class _CompanionAvatarState extends State<CompanionAvatar>
    with WidgetsBindingObserver {
  Timer? timer;
  bool blink = false, blinked = false, foreground = true, active = false;
  String? role;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = CompanionScope.maybeOf(context),
        current = scope?.snapshot.origins['character']?.id;
    if (role != current) {
      role = current;
      blinked = false;
    }
    active =
        scope?.active == true &&
        scope!.preferences.animate &&
        scope.library.motion &&
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    sync();
  }

  void sync() {
    timer?.cancel();
    if (!active || !foreground) {
      blink = false;
      return;
    }
    if (!blinked) timer = Timer(const Duration(milliseconds: 4200), showBlink);
  }

  Future<void> showBlink() async {
    if (!mounted) return;
    final scope = CompanionScope.maybeOf(context);
    if (!mounted ||
        !active ||
        !foreground ||
        scope?.snapshot.character == null) {
      return;
    }
    final bytes = await CharacterAssets.shared.read(
      scope!.snapshot.character!.frame('blink').sha256,
    );
    if (!mounted || !active || !foreground || bytes == null) return;
    await precacheImage(MemoryImage(bytes), context);
    if (!mounted || !active || !foreground) return;
    setState(() {
      blinked = true;
      blink = true;
    });
    timer = Timer(const Duration(milliseconds: 130), () {
      if (mounted) setState(() => blink = false);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    sync();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (CompanionScope.maybeOf(context)?.active != true) {
      return const SizedBox.shrink();
    }
    return IconButton(
      tooltip: translate('小夏与阅读伙伴', Localizations.localeOf(context)),
      onPressed: widget.onPressed,
      padding: const EdgeInsets.all(4),
      icon: CompanionPortrait(expression: blink ? 'blink' : 'idle', size: 40),
    );
  }
}

/// Transient, event-driven feedback. Reading progress never rebuilds this host.
class CompanionFeedback extends StatefulWidget {
  const CompanionFeedback({
    super.key,
    required this.library,
    required this.onShelf,
    required this.onUpdates,
    this.now,
  });
  final Library library;
  final VoidCallback onShelf, onUpdates;
  final DateTime Function()? now;
  @override
  State<CompanionFeedback> createState() => _CompanionFeedbackState();
}

class _CompanionFeedbackState extends State<CompanionFeedback>
    with WidgetsBindingObserver {
  LibraryNotice? seen, shown;
  DateTime? last;
  Timer? pending, dismiss;
  bool active = false, foreground = true, enabled = false;
  String frequency = 'quiet';
  @override
  void initState() {
    super.initState();
    seen = widget.library.notices.value;
    widget.library.notices.addListener(receive);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = CompanionScope.maybeOf(context);
    final next = scope?.active == true && scope!.preferences.frequency != 'off';
    if (!enabled && next) seen = widget.library.notices.value;
    enabled = next;
    frequency = scope?.preferences.frequency ?? 'quiet';
    active =
        enabled &&
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    if (!active) clear(rebuild: false);
    if (active) schedule();
  }

  void receive() {
    if (active && foreground) schedule();
  }

  void schedule() {
    final notice = widget.library.notices.value;
    if (notice == null || identical(notice, seen)) return;
    seen = notice;
    if ((widget.now?.call() ?? DateTime.now()).difference(notice.at).inSeconds >
        10) {
      return;
    }
    if (last != null &&
        (widget.now?.call() ?? DateTime.now()).difference(last!).inSeconds <
            (frequency == 'quiet' ? 30 : 8)) {
      return;
    }
    pending?.cancel();
    pending = Timer(const Duration(milliseconds: 220), () {
      if (!mounted || !active || !foreground) return;
      last = widget.now?.call() ?? DateTime.now();
      setState(() => shown = notice);
      dismiss?.cancel();
      dismiss = Timer(const Duration(seconds: 4), clear);
    });
  }

  void clear({bool rebuild = true}) {
    pending?.cancel();
    dismiss?.cancel();
    if (shown == null) return;
    if (rebuild && mounted) {
      setState(() => shown = null);
    } else {
      shown = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (!foreground) clear();
  }

  @override
  void dispose() {
    pending?.cancel();
    dismiss?.cancel();
    widget.library.notices.removeListener(receive);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notice = shown;
    return IgnorePointer(
      ignoring: notice == null,
      child: AnimatedSwitcher(
        duration: RoomMotion.duration(context, RoomMotion.feedback),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: animation.drive(
              Tween(
                begin: const Offset(0, .08),
                end: Offset.zero,
              ).chain(CurveTween(curve: RoomMotion.ease)),
            ),
            child: child,
          ),
        ),
        child: notice == null
            ? const SizedBox.shrink()
            : MilkGlass(
                key: ValueKey(notice),
                radius: 20,
                child: Row(
                  children: [
                    const CompanionPortrait(expression: 'happy', size: 48),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LocalizedText(
                            notice.kind == LibraryNoticeKind.favoriteAdded
                                ? '已放进你的书架'
                                : '书架有新章节',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (notice.kind == LibraryNoticeKind.favoriteAdded)
                            Text(
                              notice.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11),
                            ),
                          TextButton(
                            onPressed: () {
                              final action =
                                  notice.kind == LibraryNoticeKind.favoriteAdded
                                  ? widget.onShelf
                                  : widget.onUpdates;
                              clear();
                              action();
                            },
                            child: LocalizedText(
                              notice.kind == LibraryNoticeKind.favoriteAdded
                                  ? '查看书架'
                                  : '查看更新',
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: translate('关闭', Localizations.localeOf(context)),
                      onPressed: clear,
                      icon: const Icon(Icons.close, size: 17),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
