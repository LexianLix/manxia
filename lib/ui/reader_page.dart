import 'localized_text.dart';
import 'room_motion.dart';
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
import 'content_handoff.dart';

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
    with SingleTickerProviderStateMixin {
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
  int? pendingPage;
  double pendingFraction = 0;
  late final transition =
      AnimationController(vsync: this, duration: RoomMotion.feedback, value: 1)
        ..addListener(markPainted)
        ..addStatusListener(finishTransition);
  _ChapterScene? paintScheduled;
  int page = 0, total = 0, request = 0;
  double fraction = 0;
  bool controls = true, first = true;
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
    load();
    if (chapters.isEmpty) {
      widget.source
          .detail(widget.comic)
          .then((detail) {
            if (!mounted) return;
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

  Future<void> load([Chapter? selected, int? at, double? offset]) async {
    final target = selected ?? pendingChapter ?? chapter;
    if (selected != null &&
        pendingChapter?.path == target.path &&
        chapterError == null) {
      return;
    }
    final generation = ++request;
    final record = widget.library.record(widget.comic);
    final initial =
        first &&
        target.path == widget.chapter.path &&
        widget.initialPage != null;
    final wantedPage =
        at ??
        (selected == null && pendingChapter != null ? pendingPage : null) ??
        (initial
            ? widget.initialPage!
            : record?.chapterPath == target.path
            ? record!.page
            : 0);
    final wantedFraction =
        offset ??
        (selected == null && pendingChapter != null
            ? pendingFraction
            : initial
            ? widget.initialPosition
            : record?.chapterPath == target.path
            ? record!.position
            : 0);
    final obsolete = incoming;
    setState(() {
      incoming = null;
      pendingChapter = target;
      pendingPage = wantedPage;
      pendingFraction = wantedFraction;
      chapterError = null;
    });
    retire(obsolete);
    try {
      final list = await widget.source.pages(target.path);
      if (!mounted || generation != request) return;
      if (list.isEmpty) throw SourceException('这一章没有返回可读取的图片，请重新加载。');
      final prepared = _ChapterScene(
        target,
        List.unmodifiable(list),
        generation,
        wantedPage.clamp(0, list.length - 1),
        wantedFraction.clamp(0, 1),
      );
      ownedScenes.add(prepared);
      setState(() => incoming = prepared);
    } catch (e) {
      if (mounted && generation == request) {
        setState(() => chapterError = friendlyError(e));
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
    });
    retire(obsolete);
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
    scene?.page = value;
    scene?.position = offset;
    fraction = offset;
    if (value != page) setState(() => page = value);
    saveTimer?.cancel();
    saveTimer = Timer(const Duration(milliseconds: 350), save);
    preload();
  }

  final Set<String> precached = {};
  Future<void> preload() async {
    if (mode == 'strip' || total == 0) return;
    final count = widget.library.option<int>('preload', 2).clamp(0, 5);
    for (var i = page + 1; i < (page + count + 1).clamp(0, total); i++) {
      final url = urls[i];
      if (!precached.add(url)) continue;
      // PagePicture shares the same resized provider cache; decode hints bound memory.
      try {
        final provider = await pageProvider(url, widget.web, decodeWidth);
        if (mounted) await precacheImage(provider, context, onError: (_, _) {});
      } catch (_) {}
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
        if (options['tapZones'] == true &&
            mode != 'strip' &&
            d.localPosition.dx < width * .24) {
          turn(rtl ? 1 : -1);
        } else if (options['tapZones'] == true &&
            mode != 'strip' &&
            d.localPosition.dx > width * .76) {
          turn(rtl ? -1 : 1);
        } else {
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
              color: const Color(0xf21c2b20),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LocalizedText(
                  '正在打开 ${pendingChapter!.title}',
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
                        child: const LocalizedText('重试'),
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

  ThemeData get readerTheme => ThemeData.dark(useMaterial3: true).copyWith(
    textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'ArchiveSerif'),
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xff9cbaa0),
      brightness: Brightness.dark,
    ),
  );

  Widget readerContent(Widget child) => Theme(
    data: readerTheme,
    child: DefaultTextStyle(
      style: readerTheme.textTheme.bodyMedium!,
      child: child,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: readerTheme,
      child: Scaffold(
        backgroundColor: switch (options['background']) {
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
                  Align(
                    alignment: Alignment.topCenter,
                    child: ReaderChrome(
                      visible: controls,
                      top: true,
                      child: Container(
                        color: const Color(0xff1c231e),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: '返回目录',
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.arrow_back, size: 21),
                            ),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  LocalizedText(
                                    widget.comic.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  ContentHandoff(
                                    child: LocalizedText(
                                      chapter.title,
                                      key: ValueKey(chapter.path),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Color(0xff9cab9d),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: '章节与书签',
                              onPressed: catalog,
                              icon: const Icon(
                                Icons.format_list_bulleted,
                                size: 20,
                              ),
                            ),
                            IconButton(
                              tooltip: '添加书签',
                              onPressed: total > 0 ? bookmark : null,
                              icon: const Icon(
                                Icons.bookmark_add_outlined,
                                size: 20,
                              ),
                            ),
                            IconButton(
                              tooltip: '阅读设置',
                              onPressed: settings,
                              icon: const Icon(Icons.tune, size: 20),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: ReaderChrome(
                      visible: controls,
                      top: false,
                      child: Container(
                        color: const Color(0xff1c231e),
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (total > 1)
                              Slider(
                                value: page.toDouble(),
                                max: (total - 1).toDouble(),
                                divisions: total - 1,
                                onChanged: (v) => go(v.round()),
                              ),
                            Row(
                              children: [
                                IconButton(
                                  tooltip: '上一页',
                                  onPressed: page > 0 ? () => turn(-1) : null,
                                  icon: const Icon(Icons.chevron_left),
                                ),
                                Expanded(
                                  child: Column(
                                    children: [
                                      LocalizedText(
                                        total == 0 ? '加载章节中' : pageLabel,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      const LocalizedText(
                                        '轻触中间收起工具栏 · 长按图片缩放',
                                        style: TextStyle(
                                          fontSize: 9,
                                          color: Color(0xff8b9a8c),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (total > 0 &&
                                    lastVisiblePage >= total - 1 &&
                                    chapters.indexWhere(
                                          (c) => c.path == chapter.path,
                                        ) <
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
                                    tooltip: '下一页',
                                    onPressed: lastVisiblePage < total - 1
                                        ? () => turn(1)
                                        : null,
                                    icon: const Icon(Icons.chevron_right),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
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
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xff8b9a8c),
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
              hintText: '${chapter.title} · 第 ${page + 1} 页，可添加备注',
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
        backgroundColor: const Color(0xf51c231e),
        useSafeArea: true,
        sheetAnimationStyle: RoomMotion.sheet(context),
        builder: (c) => readerContent(builder(c)),
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
                Tab(text: '章节目录'),
                Tab(text: '我的书签'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  chapters.isEmpty
                      ? const Center(
                          child: LocalizedText('当前没有完整目录，请返回漫画详情加载。'),
                        )
                      : ListView.builder(
                          itemCount: chapters.length,
                          itemBuilder: (c, i) {
                            final ch = chapters[i];
                            return ListTile(
                              title: LocalizedText(
                                ch.title,
                                style: const TextStyle(fontSize: 13),
                              ),
                              selected: ch.path == chapter.path,
                              onTap: () {
                                Navigator.pop(c);
                                changeChapter(ch);
                              },
                            );
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
                                    '${mark['chapterTitle']} · 第 ${(mark['page'] as int) + 1} 页',
                                  ),
                                  subtitle: LocalizedText(mark['note'] ?? ''),
                                  trailing: IconButton(
                                    tooltip: '删除书签',
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
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'page', label: LocalizedText('横向')),
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
                  const SizedBox(height: 15),
                  toggle('从右向左翻页', 'rtl'),
                  toggle('宽屏自动双页', 'doublePage'),
                  toggle('自动裁白边', 'autoCrop'),
                  toggle('分区点击翻页', 'tapZones'),
                  DropdownButtonFormField<String>(
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
                    initialValue: options['background'] as String,
                    decoration: const InputDecoration(
                      label: LocalizedText('阅读背景'),
                    ),
                    items: const [
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
}
