import 'localized_text.dart';
import 'room_motion.dart';
import 'reader_gestures.dart';
import '../data/reading_progress.dart';
import '../data/chapter_links.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../data/comic.dart';
import '../data/dm5_source.dart';
import '../data/library.dart';
import '../data/source_hub.dart';
import '../data/offline_library.dart';
import 'app_shell.dart' show EmptyState, friendlyError;
import 'reader_surfaces.dart';
import 'reader_layout.dart';
import 'reader_preloader.dart';
import 'chapter_catalog.dart';
import 'content_handoff.dart';
import 'materials.dart';

class ReaderPage extends StatefulWidget {
  const ReaderPage({
    super.key,
    required this.comic,
    required this.chapter,
    required this.library,
    required this.source,
    required this.web,
    this.chapters = const [],
    this.initialPage,
    this.initialPosition = 0,
  });
  final Comic comic;
  final Chapter chapter;
  final Library library;
  final Dm5Source source;
  final bool web;
  final List<Chapter> chapters;
  final int? initialPage;
  final double initialPosition;
  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const device = MethodChannel('io.manxia/device');
  late Chapter chapter = widget.chapter;
  late List<Chapter> chapters = widget.chapters;
  late Map<String, dynamic> options = widget.library.readerOptions(
    widget.comic,
  );
  final idleCommand = ReaderControl();
  ReaderControl get command => scene?.control ?? idleCommand;
  _ChapterScene? scene, incoming, outgoing;
  final ownedScenes = <_ChapterScene>{};
  Chapter? pendingChapter;
  String? chapterError;
  bool chapterImagesChanged = false;
  int? pendingPage;
  double pendingFraction = 0;
  late final transition =
      AnimationController(vsync: this, duration: RoomMotion.feedback, value: 1)
        ..addListener(markPainted)
        ..addStatusListener(finishTransition);
  _ChapterScene? paintScheduled;
  int page = 0, total = 0, request = 0;
  int? scrubPage;
  bool scrubbing = false;
  double fraction = 0;
  bool controls = true, first = true;
  bool foreground = true;
  String? warmPath;
  List<String>? warmUrls;
  Future<List<String>>? warmPages;
  int warmGeneration = 0;
  bool get bottomTools => options['toolbarDock'] == 'bottom';
  Timer? saveTimer;
  Timer? chromeTimer;
  void armChromeTimer() {
    chromeTimer?.cancel();
    final seconds = widget.library.option<int>('chromeTimeout', 0);
    if (seconds <= 0 || !controls) return;
    chromeTimer = Timer(Duration(seconds: seconds), () {
      if (!mounted) return;
      if (total == 0) {
        armChromeTimer();
        return;
      }
      if (ModalRoute.of(context)?.isCurrent == true) {
        setState(() => controls = false);
      }
    });
  }

  void toggleChrome() {
    setState(() => controls = !controls);
    armChromeTimer();
  }

  List<String> urls = [];
  String get mode => options['mode'] as String;
  bool get rtl => options['rtl'] == true;
  bool get paired =>
      options['doublePage'] == true &&
      MediaQuery.sizeOf(context).width >= 900 &&
      mode == 'page';
  int get firstVisiblePage =>
      paired && page > 0 ? 1 + ((page - 1) ~/ 2) * 2 : page;
  int get lastVisiblePage => total <= 0
      ? 0
      : paired && page > 0
      ? (firstVisiblePage + 1).clamp(0, total - 1)
      : page;
  String get pageLabel => total <= 0
      ? '加载中'
      : lastVisiblePage > firstVisiblePage
      ? '${firstVisiblePage + 1}–${lastVisiblePage + 1} / $total'
      : '${page + 1} / $total';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!['auto', 'left', 'right'].contains(options['hand'])) {
      options['hand'] = 'auto';
    }
    for (final key in ['leftTapWidth', 'rightTapWidth']) {
      options[key] = tapAreaWidth(options, key);
    }
    if (chapters.isNotEmpty &&
        widget.library.chapterCount(widget.comic) == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.library.rememberChapters(widget.comic, chapters);
      });
    }
    load();
    if (chapters.isEmpty) {
      widget.source
          .detail(widget.comic)
          .then((detail) {
            if (!mounted) return;
            widget.library.rememberChapters(widget.comic, detail.chapters);
            final group = detail.chapters
                .where((c) => c.path == chapter.path)
                .firstOrNull
                ?.group;
            setState(
              () => chapters = detail.chapters
                  .where((c) => group == null || c.group == group)
                  .toList()
                  .reversed
                  .toList(),
            );
          })
          .catchError((Object _) {});
    }
    if (options['keepAwake'] == true) {
      WakelockPlus.enable().catchError((Object _) {});
    }
    native('volumeKeys', options['volumeKeys'] == true);
    armChromeTimer();
    device.setMethodCallHandler((call) async {
      if (call.method == 'volume') turn((call.arguments as int?) ?? 1);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) && transition.isAnimating) {
      transition.value = 1;
    }
  }

  Future<void> load([
    Chapter? selected,
    int? at,
    double? offset,
    bool fresh = false,
  ]) async {
    scrubPage = null;
    scrubbing = false;
    final target = selected ?? pendingChapter ?? chapter;
    if (selected != null &&
        pendingChapter?.path == target.path &&
        chapterError == null) {
      return;
    }
    final generation = ++request;
    final restart = chapterImagesChanged && !fresh;
    if (fresh || restart) {
      warmGeneration++;
      warmPath = null;
      warmPages = null;
      warmUrls = null;
    }
    preloader.clear();
    final record = widget.library.record(widget.comic);
    final initial =
        first &&
        target.path == widget.chapter.path &&
        widget.initialPage != null;
    final wantedPage =
        (restart ? 0 : at) ??
        (selected == null && pendingChapter != null ? pendingPage : null) ??
        (initial
            ? widget.initialPage!
            : record?.chapterPath == target.path
            ? record!.page
            : 0);
    final wantedFraction =
        (restart ? 0.0 : offset) ??
        (selected == null && pendingChapter != null
            ? pendingFraction
            : initial
            ? widget.initialPosition
            : record?.chapterPath == target.path
            ? record!.position
            : 0);
    final obsolete = incoming;
    final previousUrls = scene?.chapter.path == target.path
        ? scene!.urls
        : incoming?.urls;
    setState(() {
      incoming = null;
      pendingChapter = target;
      pendingPage = wantedPage;
      pendingFraction = wantedFraction;
      chapterError = null;
      chapterImagesChanged = false;
    });
    retire(obsolete);
    try {
      final list = fresh
          ? await refreshChapterLinks(
              widget.source,
              target.path,
              previousUrls ?? [],
              completed: previousUrls?.length ?? 0,
            )
          : restart
          ? await widget.source.networkPages(target.path)
          : await (warmPath == target.path && warmPages != null
                ? warmPages!
                : widget.source.pages(target.path));
      if (!mounted || generation != request) return;
      if (list.isEmpty) throw SourceException('这一章没有返回可读取的图片，请重新加载。');
      final prepared = _ChapterScene(
        target,
        List.unmodifiable(list),
        generation,
        wantedPage.clamp(0, list.length - 1),
        wantedFraction.clamp(0, 1),
      );
      prepared.refreshed = fresh || restart;
      ownedScenes.add(prepared);
      setState(() => incoming = prepared);
    } catch (e) {
      if (mounted && generation == request) {
        setState(() {
          chapterError = friendlyError(e);
          chapterImagesChanged = e is ChapterImagesChanged;
        });
      }
    }
  }

  void retire(_ChapterScene? value) {
    if (value == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ownedScenes.remove(value)) value.control.dispose();
    });
  }

  void cancelLoad() {
    final obsolete = incoming;
    request++;
    setState(() {
      incoming = null;
      pendingChapter = null;
      pendingPage = null;
      chapterError = null;
      chapterImagesChanged = false;
    });
    retire(obsolete);
    preload();
  }

  void ready(_ChapterScene value) {
    if (!mounted ||
        !identical(incoming, value) ||
        value.request != request ||
        value.failed) {
      return;
    }
    value.ready = true;
    // Finish the currently visible blend before handing off another frame.
    // A ready third request waits here; rapid retargeting cannot snap layers.
    if (outgoing == null || !transition.isAnimating) commit(value);
  }

  void failed(_ChapterScene value) {
    if (!mounted || !identical(incoming, value) || value.request != request) {
      return;
    }
    value.failed = true;
    setState(() => chapterError = '这一章的首屏图片加载失败，可以重试。');
  }

  void commit(_ChapterScene value) {
    if (!mounted || !identical(incoming, value) || value.request != request) {
      return;
    }
    save();
    saveTimer?.cancel();
    final previous = scene;
    if (previous?.presented == true &&
        previous!.chapter.path != value.chapter.path) {
      value.previous = (
        chapter: previous.chapter,
        page: previous.page,
        position: previous.position,
      );
    }
    warmGeneration++;
    warmPath = null;
    warmPages = null;
    warmUrls = null;
    setState(() {
      outgoing = previous;
      scene = value;
      incoming = null;
      chapter = value.chapter;
      urls = value.urls;
      page = value.page;
      fraction = value.position;
      total = value.urls.length;
      first = false;
      pendingChapter = null;
      pendingPage = null;
      chapterError = null;
    });
    if (MediaQuery.disableAnimationsOf(context) || !widget.library.motion) {
      transition.value = 1;
      finishTransition(AnimationStatus.completed);
      markPainted();
    } else {
      transition.forward(from: 0);
    }
  }

  void finishTransition(AnimationStatus status) {
    if (!mounted || status != AnimationStatus.completed) return;
    final obsolete = outgoing;
    if (obsolete != null) {
      setState(() => outgoing = null);
      retire(obsolete);
    }
    if (incoming?.ready == true && incoming?.failed == false) commit(incoming!);
  }

  void markPainted() {
    final value = scene;
    if (value == null ||
        value.presented ||
        identical(paintScheduled, value) ||
        transition.value <= 0) {
      return;
    }
    paintScheduled = value;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(scene, value) || transition.value <= 0) return;
      setState(() {
        value.presented = true;
      });
      save();
      preload();
      final prior = value.previous;
      if (prior != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
            content: LocalizedText(
              '已进入 {chapter}',
              arguments: {'chapter': value.chapter.title},
            ),
            action: SnackBarAction(
              label: translate('返回上一章', Localizations.localeOf(context)),
              onPressed: () => changeChapter(
                prior.chapter,
                at: prior.page,
                offset: prior.position,
              ),
            ),
          ),
        );
      }
    });
  }

  ReadingRecord record() => ReadingRecord(
    comic: widget.comic,
    chapterPath: chapter.path,
    chapterTitle: chapter.title,
    page: page,
    total: total,
    position: fraction,
    updatedAt: DateTime.now().millisecondsSinceEpoch,
  );
  void save() {
    if (total > 0 && scene?.presented == true) widget.library.save(record());
  }

  void position(int value, double offset) {
    if (!mounted) return;
    if (value != page) forward = value > page;
    scene?.page = value;
    scene?.position = offset;
    fraction = offset;
    if (value != page) setState(() => page = value);
    saveTimer?.cancel();
    saveTimer = Timer(const Duration(milliseconds: 350), save);
    preload();
  }

  bool forward = true;
  late final preloader = ReaderPreloader((url, width) async {
    final provider = await pageProvider(url, widget.web, width);
    if (!mounted) return false;
    var success = true;
    await precacheImage(provider, context, onError: (_, _) => success = false);
    return success;
  });
  void preload() {
    if (!foreground || total == 0 || pendingChapter != null) {
      preloader.clear();
      return;
    }
    final count = widget.library.option<int>('preload', 2).clamp(0, 5);
    final window = <String>[];
    for (var step = 1; mode != 'strip' && step <= count; step++) {
      final i = forward ? lastVisiblePage + step : firstVisiblePage - step;
      if (i >= 0 && i < urls.length) window.add(urls[i]);
    }
    if (count > 0 && warmUrls?.isNotEmpty == true) window.add(warmUrls!.first);
    preloader.replace(window, decodeWidth);
    if (count > 0 &&
        lastVisiblePage >= total - 3 &&
        widget.library.option<bool>('warmNextChapter', true)) {
      warmNext();
    }
  }

  Chapter? get nextChapter {
    final index = chapters.indexWhere((c) => c.path == chapter.path);
    return index >= 0 && index + 1 < chapters.length
        ? chapters[index + 1]
        : null;
  }

  Future<void> warmNext() async {
    final next = nextChapter;
    if (next == null || warmPath == next.path || !foreground) return;
    warmPath = next.path;
    final origin = chapter.path, token = ++warmGeneration;
    final future = widget.source.pages(next.path);
    warmPages = future;
    try {
      final list = await future;
      if (!mounted ||
          !foreground ||
          token != warmGeneration ||
          chapter.path != origin) {
        return;
      }
      warmUrls = list;
      preload();
    } catch (_) {
      if (mounted && token == warmGeneration) {
        warmPages = null;
        warmUrls = null;
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (!foreground) {
      preloader.clear();
      warmGeneration++;
      warmPath = null;
      warmPages = null;
      warmUrls = null;
    } else {
      preload();
    }
  }

  int get decodeWidth =>
      switch (widget.library.option<String>('quality', 'high')) {
        'low' => 1000,
        'standard' => 1500,
        _ => 2200,
      };
  void go(int value, {double offset = 0}) {
    if (total == 0 || scene?.presented != true) return;
    command.go(value.clamp(0, total - 1), position: offset.clamp(0, 1));
  }

  void turn(int direction) {
    if (direction > 0 &&
        total > 0 &&
        lastVisiblePage >= total - 1 &&
        scene?.presented == true) {
      chapterEnd();
      return;
    }
    final target = command.target ?? firstVisiblePage;
    final anchor = paired && target > 0 ? 1 + ((target - 1) ~/ 2) * 2 : target;
    final step = paired && anchor > 0 ? 2 : 1;
    go(anchor + direction * step);
  }

  Future<void> changeChapter(
    Chapter value, {
    int? at,
    double offset = 0,
  }) async {
    save();
    if (scene != null && value.path == chapter.path) {
      if (pendingChapter != null) cancelLoad();
      if (at != null) go(at, offset: offset);
      return;
    }
    await load(value, at, offset);
  }

  bool endSheetOpen = false;
  Future<void> chapterEnd() async {
    if (endSheetOpen || scene?.presented != true) return;
    endSheetOpen = true;
    chromeTimer?.cancel();
    final finished = chapter, next = nextChapter;
    try {
      await showReaderSheet(
        (c) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const LocalizedText(
                  '本章告一段落',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                Text(finished.title),
                const SizedBox(height: 20),
                FilledButton.icon(
                  icon: Icon(
                    next == null ? Icons.done_all : Icons.arrow_forward,
                  ),
                  label: LocalizedText(next == null ? '标记本章已读' : '读完并继续下一章'),
                  onPressed: () async {
                    final wasRead = widget.library.chapterRead(
                      widget.comic,
                      finished.path,
                    );
                    await widget.library.setChapterRead(
                      widget.comic,
                      finished.path,
                      true,
                    );
                    if (!c.mounted) return;
                    Navigator.pop(c);
                    if (next != null) {
                      changeChapter(next);
                    } else if (mounted) {
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const LocalizedText('本章已标为已读'),
                          action: SnackBarAction(
                            label: translate(
                              '撤销',
                              Localizations.localeOf(context),
                            ),
                            onPressed: () => widget.library.setChapterRead(
                              widget.comic,
                              finished.path,
                              wasRead,
                            ),
                          ),
                        ),
                      );
                    }
                  },
                ),
                if (next != null)
                  TextButton(
                    onPressed: () {
                      Navigator.pop(c);
                      changeChapter(next);
                    },
                    child: const LocalizedText('仅继续下一章'),
                  ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(c);
                    catalog();
                  },
                  child: const LocalizedText('返回章节目录'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: const LocalizedText('留在当前页'),
                ),
              ],
            ),
          ),
        ),
      );
    } finally {
      endSheetOpen = false;
      if (mounted) armChromeTimer();
    }
  }

  Future<void> native(String method, dynamic args) async {
    try {
      await device.invokeMethod(method, args);
    } catch (_) {}
  }

  Widget surface(_ChapterScene value) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapUp: (d) {
        if (!identical(scene, value) || !value.presented) return;
        final width = MediaQuery.sizeOf(context).width;
        final tapToTurn =
            options['tapZones'] == true &&
            value.control.transform.getMaxScaleOnAxis() <= 1.001;
        final action = tapToTurn && mode != 'strip'
            ? readerTap(d.localPosition.dx / width, options, rtl)
            : ReaderTap.controls;
        switch (action) {
          case ReaderTap.previous:
            turn(-1);
          case ReaderTap.next:
            turn(1);
          case ReaderTap.controls:
            toggleChrome();
        }
      },
      child: ReaderLayout(
        key: ObjectKey(value),
        urls: value.urls,
        web: widget.web,
        mode: mode,
        rtl: rtl,
        paired: paired,
        startPage: value.page,
        position: value.position,
        control: value.control,
        onPosition: (p, f) {
          if (identical(scene, value) && value.presented) position(p, f);
        },
        onReady: () => ready(value),
        onLoadError: () => failed(value),
        onImageError: (index, error) {
          if (error is NetworkImageLoadException &&
              expiredImageStatus(error.statusCode)) {
            retryImage(value, index, automatic: true);
          }
        },
        onRetryPage: value.urls.any((url) => !url.startsWith('offline:'))
            ? (index) => retryImage(value, index)
            : null,
        speed: identical(scene, value) && value.presented
            ? (options['autoScroll'] as num).toDouble()
            : 0,
        paper: options['turn'] == 'paper',
        crop: (options['crop'] as num).toDouble(),
        autoCrop: options['autoCrop'] == true,
        decodeWidth: decodeWidth,
      ),
    );
  }

  Future<void> retryImage(
    _ChapterScene value,
    int index, {
    bool automatic = false,
  }) async {
    if (automatic &&
        pendingChapter != null &&
        pendingChapter!.path != value.chapter.path) {
      return;
    }
    if (!mounted ||
        (!identical(value, scene) && !identical(value, incoming)) ||
        (automatic && value.refreshed)) {
      return;
    }
    if (value.urls[index].startsWith('offline:')) return;
    value.refreshed = true;
    await load(value.chapter, value.page, value.position, true);
  }

  Widget chapterSurfaces() {
    final current = scene, previous = outgoing, prepared = incoming;
    final currentBody = current == null ? null : surface(current);
    final previousBody = previous == null ? null : surface(previous);
    final preparedBody = prepared == null ? null : surface(prepared);
    Widget layer(
      _ChapterScene value,
      Widget body,
      double alpha, {
      bool active = false,
    }) => KeyedSubtree(
      key: ValueKey(value),
      child: IgnorePointer(
        ignoring: !active || !value.presented,
        child: ExcludeSemantics(
          excluding: !active || !value.presented,
          child: TickerMode(
            // A prepared strip needs its short restore scroll before onReady.
            enabled: !identical(value, previous),
            child: Opacity(opacity: alpha, child: body),
          ),
        ),
      ),
    );
    Widget? waiting;
    if (current == null || (previous == null && !current.presented)) {
      if (chapterError != null && current == null) {
        waiting = SingleChildScrollView(
          child: Column(
            children: [
              EmptyState(
                icon: Icons.cloud_off_outlined,
                title: '这一章暂时无法打开',
                message: chapterError!,
                action: load,
                actionLabel: '重新加载',
              ),
              TextButton(
                onPressed: openChapterOriginal,
                child: const LocalizedText('在原站打开'),
              ),
            ],
          ),
        );
      } else {
        waiting = const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      }
    }
    return AnimatedBuilder(
      animation: transition,
      builder: (_, _) {
        final t = RoomMotion.ease.transform(transition.value);
        return Stack(
          fit: StackFit.expand,
          children: [
            if (waiting != null)
              Opacity(opacity: current == null ? 1 : 1 - t, child: waiting),
            if (previousBody != null) layer(previous!, previousBody, 1 - t),
            if (currentBody != null)
              layer(current!, currentBody, t, active: true),
            if (preparedBody != null) layer(prepared!, preparedBody, 0),
            TweenAnimationBuilder<double>(
              tween: Tween(
                begin: (options['warmth'] as num? ?? 0).toDouble(),
                end: (options['warmth'] as num? ?? 0).toDouble().clamp(0, 1),
              ),
              duration: RoomMotion.duration(context, RoomMotion.feedback),
              curve: RoomMotion.ease,
              builder: (_, value, _) => IgnorePointer(
                child: ColoredBox(
                  key: const ValueKey('reader-warmth'),
                  color: const Color(0xffffbb70).withValues(alpha: value * .24),
                ),
              ),
            ),
            if ((options['brightness'] as num) < 1)
              IgnorePointer(
                child: ColoredBox(
                  color: Colors.black.withValues(
                    alpha: 1 - (options['brightness'] as num).toDouble(),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> openChapterOriginal() async {
    final target = pendingChapter ?? chapter;
    try {
      final url =
          target.path.startsWith('custom:') && widget.source is SourceHub
          ? (widget.source as SourceHub)
                .profile(target.path)
                .decode(target.path)
          : Uri.parse('${Dm5Source.origin}${target.path}');
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: LocalizedText(friendlyError(e))));
      }
    }
  }

  Widget chapterStatus() => ContentHandoff(
    child: pendingChapter == null || scene == null
        ? const SizedBox.shrink(key: ValueKey('chapter-idle'))
        : Container(
            key: ValueKey((pendingChapter!.path, chapterError == null)),
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 8),
            decoration: BoxDecoration(
              color: readerTheme.colorScheme.surfaceContainerHigh.withValues(
                alpha: .95,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LocalizedText(
                  chapterError == null ? '正在打开 {chapter}' : '未能打开 {chapter}',
                  arguments: {'chapter': pendingChapter!.title},
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 7),
                if (chapterError == null) ...[
                  const LinearProgressIndicator(minHeight: 2),
                  const SizedBox(height: 7),
                  LocalizedText(
                    incoming == null ? '正在读取章节…' : '正在准备首屏图片…',
                    style: const TextStyle(fontSize: 11),
                  ),
                ] else
                  LocalizedText(
                    chapterError!,
                    style: const TextStyle(fontSize: 11),
                  ),
                Wrap(
                  spacing: 8,
                  children: [
                    if (chapterError != null)
                      TextButton(
                        onPressed: load,
                        child: LocalizedText(
                          chapterImagesChanged ? '从本章开头重新加载' : '重试',
                        ),
                      ),
                    if (chapterError != null &&
                        widget.comic.sourceId != 'local')
                      TextButton(
                        onPressed: openChapterOriginal,
                        child: const LocalizedText('在原站打开'),
                      ),
                    TextButton(
                      onPressed: cancelLoad,
                      child: const LocalizedText('继续当前章'),
                    ),
                  ],
                ),
              ],
            ),
          ),
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    warmGeneration++;
    preloader.dispose();
    chromeTimer?.cancel();
    saveTimer?.cancel();
    if (total > 0 && scene?.presented == true) {
      final value = record();
      final library = widget.library;
      scheduleMicrotask(() => library.save(value));
    }
    request++;
    transition.dispose();
    for (final value in ownedScenes.toList()) {
      retire(value);
    }
    idleCommand.dispose();
    device.setMethodCallHandler(null);
    native('volumeKeys', false);
    native('brightness', -1.0);
    WakelockPlus.disable().catchError((Object _) {});
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  ThemeData get readerTheme => Theme.of(context);

  Widget readerContent(Widget child) => Theme(
    data: readerTheme,
    child: DefaultTextStyle(
      style: readerTheme.textTheme.bodyMedium!,
      child: child,
    ),
  );

  Widget headerChrome(BuildContext context) => ReaderChrome(
    visible: controls,
    top: !bottomTools,
    child: MilkGlass(
      radius: 22,
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      high: widget.library.option<String>('quality', 'high') == 'high',
      tintOpacity: .90,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Row(
        children: [
          IconButton(
            tooltip: translate('返回目录', Localizations.localeOf(context)),
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, size: 21),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.comic.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
                ContentHandoff(
                  child: Text(
                    chapter.title,
                    key: ValueKey(chapter.path),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: readerTheme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: translate('章节与书签', Localizations.localeOf(context)),
            onPressed: catalog,
            icon: const Icon(Icons.format_list_bulleted, size: 20),
          ),
          IconButton(
            tooltip: translate('添加书签', Localizations.localeOf(context)),
            onPressed: total > 0 ? bookmark : null,
            icon: const Icon(Icons.bookmark_add_outlined, size: 20),
          ),
          if (bottomTools)
            IconButton(
              tooltip: translate('收起工具栏', Localizations.localeOf(context)),
              onPressed: toggleChrome,
              icon: const Icon(Icons.keyboard_arrow_down, size: 20),
            ),
          IconButton(
            tooltip: translate('阅读设置', Localizations.localeOf(context)),
            onPressed: settings,
            icon: const Icon(Icons.tune, size: 20),
          ),
        ],
      ),
    ),
  );
  Widget footerChrome(BuildContext context) => ReaderChrome(
    visible: controls,
    top: false,
    child: MilkGlass(
      radius: 22,
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      high: widget.library.option<String>('quality', 'high') == 'high',
      tintOpacity: .90,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (total > 1)
            Slider(
              value: (scrubPage ?? page).clamp(0, total - 1).toDouble(),
              max: (total - 1).toDouble(),
              divisions: total - 1,
              label: '${(scrubPage ?? page) + 1} / $total',
              onChangeStart: (v) {
                chromeTimer?.cancel();
                setState(() {
                  scrubbing = true;
                  scrubPage = v.round();
                });
              },
              onChanged: (v) {
                if (scrubbing) {
                  setState(() => scrubPage = v.round());
                } else {
                  // Keyboard and accessibility adjustments have no drag end.
                  go(v.round());
                }
              },
              onChangeEnd: (v) {
                setState(() {
                  scrubbing = false;
                  scrubPage = null;
                });
                go(v.round());
                armChromeTimer();
              },
            ),
          if (total > 0 && lastVisiblePage >= total - 1)
            TextButton.icon(
              onPressed: chapterEnd,
              icon: const Icon(Icons.done_all, size: 17),
              label: const LocalizedText('本章读完'),
            ),
          Row(
            children: [
              IconButton(
                tooltip: translate('上一页', Localizations.localeOf(context)),
                onPressed: page > 0 ? () => turn(-1) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LocalizedText(
                      total == 0
                          ? '加载章节中'
                          : scrubPage != null
                          ? '${scrubPage! + 1} / $total'
                          : pageLabel,
                      style: const TextStyle(fontSize: 12),
                    ),
                    LocalizedText(
                      '轻触中间收起工具栏 · 长按图片缩放',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9,
                        color: readerTheme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (total > 0 &&
                  lastVisiblePage >= total - 1 &&
                  chapters.indexWhere((c) => c.path == chapter.path) <
                      chapters.length - 1 &&
                  chapters.any((c) => c.path == chapter.path))
                TextButton(
                  onPressed: () => changeChapter(
                    chapters[chapters.indexWhere(
                          (c) => c.path == chapter.path,
                        ) +
                        1],
                  ),
                  child: const LocalizedText('下一章'),
                )
              else
                IconButton(
                  tooltip: translate('下一页', Localizations.localeOf(context)),
                  onPressed: lastVisiblePage < total - 1 ? () => turn(1) : null,
                  icon: const Icon(Icons.chevron_right),
                ),
            ],
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: readerTheme,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: switch (options['background']) {
          'theme' => Colors.transparent,
          'paper' => const Color(0xfff3f1e9),
          'sepia' => const Color(0xffdaceb9),
          _ => const Color(0xff111512),
        },
        body: SafeArea(
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                  turn(rtl ? -1 : 1),
              const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                  turn(rtl ? 1 : -1),
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  Navigator.maybePop(context),
              const SingleActivator(LogicalKeyboardKey.space): () =>
                  toggleChrome(),
            },
            child: Focus(
              autofocus: true,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(child: chapterSurfaces()),
                  AnimatedPositioned(
                    duration: RoomMotion.duration(context, RoomMotion.feedback),
                    curve: RoomMotion.ease,
                    top: controls ? 74 : 12,
                    left: 12,
                    right: 12,
                    child: chapterStatus(),
                  ),
                  if (!bottomTools)
                    Align(
                      alignment: Alignment.topCenter,
                      child: headerChrome(context),
                    ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (bottomTools) headerChrome(context),
                        footerChrome(context),
                      ],
                    ),
                  ),
                  Positioned(
                    right: 10,
                    bottom: 6,
                    child: ReaderChrome(
                      visible: !controls,
                      top: false,
                      child: LocalizedText(
                        pageLabel,
                        style: TextStyle(
                          fontSize: 10,
                          color: readerTheme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> bookmark() async {
    final input = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      animationStyle: RoomMotion.sheet(context),
      builder: (c) => readerContent(
        AlertDialog(
          title: const LocalizedText('留一枚书签'),
          content: TextField(
            controller: input,
            decoration: InputDecoration(
              hintText: translate(
                '{chapter} · 第 {page} 页，可添加备注',
                Localizations.localeOf(context),
                arguments: {'chapter': chapter.title, 'page': page + 1},
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const LocalizedText('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, '__page_favorite__'),
              child: const LocalizedText('收藏这一页'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, input.text),
              child: const LocalizedText('保存书签'),
            ),
          ],
        ),
      ),
    );
    Future.delayed(const Duration(seconds: 1), input.dispose);
    if (note != null) {
      await widget.library.addBookmark(
        record(),
        note: note == '__page_favorite__' ? '' : note,
        favorite: note == '__page_favorite__',
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: LocalizedText('书签已保存')));
      }
    }
  }

  Future<T?> showReaderSheet<T>(WidgetBuilder builder) =>
      showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: Colors.transparent,
        useSafeArea: true,
        sheetAnimationStyle: RoomMotion.sheet(context),
        builder: (c) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom),
          child: readerContent(
            MilkGlass(
              radius: 24,
              tintOpacity: .94,
              high: widget.library.option<String>('quality', 'high') == 'high',
              child: builder(c),
            ),
          ),
        ),
      );

  void catalog() => showReaderSheet(
    (c) => DefaultTabController(
      length: 2,
      animationDuration: RoomMotion.duration(c, RoomMotion.feedback),
      child: SizedBox(
        height: MediaQuery.sizeOf(c).height * .78,
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(child: LocalizedText('章节目录')),
                Tab(child: LocalizedText('我的书签')),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  chapters.isEmpty
                      ? const Center(
                          child: LocalizedText('当前没有完整目录，请返回漫画详情加载。'),
                        )
                      : ChapterCatalog(
                          chapters: chapters,
                          current: chapter.path,
                          isRead: (ch) =>
                              widget.library.chapterRead(widget.comic, ch.path),
                          onToggleRead: (ch) async {
                            await widget.library.setChapterRead(
                              widget.comic,
                              ch.path,
                              !widget.library.chapterRead(
                                widget.comic,
                                ch.path,
                              ),
                            );
                            if (mounted) setState(() {});
                          },
                          onSelected: (ch) {
                            Navigator.pop(c);
                            changeChapter(ch);
                          },
                        ),
                  ListenableBuilder(
                    listenable: widget.library,
                    builder: (c, _) {
                      final marks = widget.library.bookmarks
                          .where((b) => b['comicPath'] == widget.comic.path)
                          .toList();
                      return marks.isEmpty
                          ? const Center(
                              child: LocalizedText('还没有书签，点击阅读器右上角添加。'),
                            )
                          : ListView.builder(
                              itemCount: marks.length,
                              itemBuilder: (c, i) {
                                final mark = marks[i];
                                return ListTile(
                                  title: LocalizedText(
                                    '{chapter} · 第 {page} 页',
                                    arguments: {
                                      'chapter': mark['chapterTitle'],
                                      'page': (mark['page'] as int) + 1,
                                    },
                                  ),
                                  subtitle: LocalizedText(mark['note'] ?? ''),
                                  trailing: IconButton(
                                    tooltip: translate(
                                      '删除书签',
                                      Localizations.localeOf(context),
                                    ),
                                    onPressed: () => widget.library
                                        .removeBookmark(mark['id']),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                  onTap: () {
                                    Navigator.pop(c);
                                    if (mark['chapterPath'] == chapter.path) {
                                      go(
                                        mark['page'],
                                        offset: (mark['position'] as num? ?? 0)
                                            .toDouble(),
                                      );
                                    } else {
                                      changeChapter(
                                        Chapter(
                                          mark['chapterPath'],
                                          mark['chapterTitle'],
                                        ),
                                        at: mark['page'],
                                        offset:
                                            (mark['position'] as num?)
                                                ?.toDouble() ??
                                            0,
                                      );
                                    }
                                  },
                                );
                              },
                            );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  void settings() => showReaderSheet(
    (c) => StatefulBuilder(
      builder: (c, update) {
        void set(String key, dynamic value) {
          setState(() => options[key] = value);
          update(() {});
          widget.library.setReaderOption(widget.comic, key, value);
          preload();
        }

        Widget toggle(
          String title,
          String key, {
          void Function(bool)? action,
        }) => SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: LocalizedText(title, style: const TextStyle(fontSize: 13)),
          value: options[key] == true,
          onChanged: (v) {
            set(key, v);
            action?.call(v);
          },
        );
        Widget slider(String title, String key, double min, double max) =>
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LocalizedText(title, style: const TextStyle(fontSize: 12)),
                Slider(
                  value: (options[key] as num? ?? min).toDouble().clamp(
                    min,
                    max,
                  ),
                  min: min,
                  max: max,
                  onChanged: (v) => set(key, v),
                ),
              ],
            );
        final automatic = mode == 'strip'
            ? slider('自动滚动速度（0 为关闭）', 'autoScroll', 0, 120)
            : const SizedBox(width: double.infinity);
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(c).height * .8,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 25),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const LocalizedText(
                    '这本漫画的阅读方式',
                    style: TextStyle(fontSize: 21),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<String>(
                      direction:
                          MediaQuery.sizeOf(c).width < 600 &&
                              (Localizations.localeOf(c).languageCode == 'en' ||
                                  MediaQuery.textScalerOf(c).scale(14) > 18)
                          ? Axis.vertical
                          : Axis.horizontal,
                      segments: const [
                        ButtonSegment(
                          value: 'page',
                          label: LocalizedText('横向'),
                        ),
                        ButtonSegment(
                          value: 'strip',
                          label: LocalizedText('连续条漫'),
                        ),
                        ButtonSegment(
                          value: 'vertical',
                          label: LocalizedText('竖向'),
                        ),
                      ],
                      selected: {mode},
                      onSelectionChanged: (v) {
                        save();
                        set('mode', v.first);
                      },
                    ),
                  ),
                  const SizedBox(height: 15),
                  toggle('从右向左翻页', 'rtl'),
                  toggle('宽屏自动双页', 'doublePage'),
                  toggle('自动裁白边', 'autoCrop'),
                  toggle('分区点击翻页', 'tapZones'),
                  DropdownButtonFormField<String>(
                    initialValue: options['hand'] as String? ?? 'auto',
                    isExpanded: true,
                    decoration: const InputDecoration(
                      label: LocalizedText('单手操作预设'),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'auto',
                        child: LocalizedText('跟随阅读方向'),
                      ),
                      DropdownMenuItem(
                        value: 'left',
                        child: LocalizedText('左手为主'),
                      ),
                      DropdownMenuItem(
                        value: 'right',
                        child: LocalizedText('右手为主'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        set('hand', v);
                        set('toolbarDock', v == 'auto' ? 'top' : 'bottom');
                      }
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Row(
                        children: [
                          for (final zone in [
                            (options['leftTapWidth'] as num).toDouble(),
                            1 -
                                (options['leftTapWidth'] as num).toDouble() -
                                (options['rightTapWidth'] as num).toDouble(),
                            (options['rightTapWidth'] as num).toDouble(),
                          ].indexed)
                            Expanded(
                              flex: (zone.$2 * 100).round().clamp(1, 100),
                              child: ColoredBox(
                                color: readerTheme.colorScheme.primary
                                    .withValues(
                                      alpha: zone.$1 == 1 ? .04 : .12,
                                    ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  child: LocalizedText(
                                    zone.$1 == 1
                                        ? '工具栏'
                                        : readerTap(
                                                zone.$1 == 0 ? 0 : 1,
                                                options,
                                                rtl,
                                              ) ==
                                              ReaderTap.next
                                        ? '下一页'
                                        : '上一页',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 11),
                                    maxLines: 2,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  slider('左侧点击区域', 'leftTapWidth', .12, .4),
                  slider('右侧点击区域', 'rightTapWidth', .12, .4),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const LocalizedText('工具栏集中到底部'),
                    value: bottomTools,
                    onChanged: (v) => set('toolbarDock', v ? 'bottom' : 'top'),
                  ),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: options['turn'] as String,
                    decoration: const InputDecoration(
                      label: LocalizedText('翻页效果'),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'slide',
                        child: LocalizedText('平移'),
                      ),
                      DropdownMenuItem(
                        value: 'paper',
                        child: LocalizedText('纸页弯曲'),
                      ),
                    ],
                    onChanged: (v) => set('turn', v),
                  ),
                  const SizedBox(height: 18),
                  slider('手动裁边', 'crop', 0, .15),
                  slider('画面亮度', 'brightness', .15, 1),
                  slider('护眼暖色', 'warmth', 0, 1),
                  if (MediaQuery.disableAnimationsOf(c))
                    automatic
                  else
                    AnimatedSize(
                      duration: RoomMotion.feedback,
                      curve: RoomMotion.ease,
                      alignment: Alignment.topLeft,
                      child: automatic,
                    ),
                  toggle(
                    '保持屏幕常亮',
                    'keepAwake',
                    action: (v) => WakelockPlus.toggle(
                      enable: v,
                    ).catchError((Object _) {}),
                  ),
                  toggle(
                    '音量键翻页',
                    'volumeKeys',
                    action: (v) => native('volumeKeys', v),
                  ),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: options['background'] as String,
                    decoration: const InputDecoration(
                      label: LocalizedText('阅读背景'),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'theme',
                        child: LocalizedText('跟随应用'),
                      ),
                      DropdownMenuItem(
                        value: 'ink',
                        child: LocalizedText('夜墨'),
                      ),
                      DropdownMenuItem(
                        value: 'paper',
                        child: LocalizedText('纸白'),
                      ),
                      DropdownMenuItem(
                        value: 'sepia',
                        child: LocalizedText('旧纸'),
                      ),
                    ],
                    onChanged: (v) => set('background', v),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    children: [
                      OutlinedButton(
                        onPressed: () => SystemChrome.setPreferredOrientations([
                          DeviceOrientation.portraitUp,
                        ]),
                        child: const LocalizedText('锁定竖屏'),
                      ),
                      OutlinedButton(
                        onPressed: () => SystemChrome.setPreferredOrientations([
                          DeviceOrientation.landscapeLeft,
                          DeviceOrientation.landscapeRight,
                        ]),
                        child: const LocalizedText('锁定横屏'),
                      ),
                      TextButton(
                        onPressed: () => SystemChrome.setPreferredOrientations(
                          DeviceOrientation.values,
                        ),
                        child: const LocalizedText('自动旋转'),
                      ),
                    ],
                  ),
                  if (OfflineLibrary.instance != null)
                    TextButton.icon(
                      onPressed: () async {
                        await OfflineLibrary.instance!.enqueue(
                          widget.comic,
                          chapter,
                        );
                        if (c.mounted) {
                          ScaffoldMessenger.of(c).showSnackBar(
                            const SnackBar(
                              content: LocalizedText('当前章节已加入下载队列'),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.download_outlined),
                      label: const LocalizedText('下载当前章节'),
                    ),
                  const SizedBox(height: 15),
                  const LocalizedText(
                    '设置仅作用于当前漫画。自动滚动可随时设为 0 停止。',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _ChapterScene {
  _ChapterScene(
    this.chapter,
    this.urls,
    this.request,
    this.page,
    this.position,
  );
  final Chapter chapter;
  final List<String> urls;
  final int request;
  final control = ReaderControl();
  int page;
  double position;
  bool ready = false, failed = false, presented = false;
  bool refreshed = false;
  ({Chapter chapter, int page, double position})? previous;
}
