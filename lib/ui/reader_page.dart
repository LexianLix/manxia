import 'localized_text.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../data/comic.dart';
import '../data/dm5_source.dart';
import '../data/library.dart';
import '../data/offline_library.dart';
import 'app_shell.dart' show EmptyState, friendlyError;
import 'reader_surfaces.dart';

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

class _ReaderPageState extends State<ReaderPage> {
  static const device = MethodChannel('io.manxia/device');
  late Chapter chapter = widget.chapter;
  late List<Chapter> chapters = widget.chapters;
  late Map<String, dynamic> options = widget.library.readerOptions(
    widget.comic,
  );
  late Future<List<String>> loading;
  final command = ReaderControl();
  int page = 0, total = 0, request = 0;
  int surfaceGeneration = 0;
  double fraction = 0;
  bool controls = true, first = true;
  int? pendingPage;
  double pendingFraction = 0;
  Timer? saveTimer;
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
    device.setMethodCallHandler((call) async {
      if (call.method == 'volume') turn((call.arguments as int?) ?? 1);
    });
  }

  void load() {
    final generation = ++request;
    final record = widget.library.record(widget.comic);
    page =
        pendingPage ??
        (first && widget.initialPage != null
            ? widget.initialPage!
            : record?.chapterPath == chapter.path
            ? record!.page
            : 0);
    fraction = pendingPage != null
        ? pendingFraction
        : first && widget.initialPage != null
        ? widget.initialPosition
        : record?.chapterPath == chapter.path
        ? record!.position
        : 0;
    first = false;
    pendingPage = null;
    total = 0;
    loading = widget.source.pages(chapter.path).then((list) {
      if (!mounted || generation != request) return list;
      setState(() {
        urls = list;
        total = list.length;
        page = page.clamp(0, total - 1);
      });
      save();
      preload();
      return list;
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
    if (total > 0) widget.library.save(record());
  }

  void position(int value, double offset) {
    if (!mounted) return;
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
    if (total == 0) return;
    if (mode == 'strip' && offset > 0) {
      setState(() {
        page = value.clamp(0, total - 1);
        fraction = offset.clamp(0, 1);
        surfaceGeneration++;
      });
      return;
    }
    command.go(value.clamp(0, total - 1));
  }

  void turn(int direction) {
    final step = paired && firstVisiblePage > 0 ? 2 : 1;
    go(firstVisiblePage + direction * step);
  }

  Future<void> changeChapter(
    Chapter value, {
    int? at,
    double offset = 0,
  }) async {
    save();
    if (value.path == chapter.path && at != null) {
      go(at, offset: offset);
      return;
    }
    setState(() {
      chapter = value;
      pendingPage = at;
      pendingFraction = offset;
      load();
    });
  }

  Future<void> native(String method, dynamic args) async {
    try {
      await device.invokeMethod(method, args);
    } catch (_) {}
  }

  @override
  void dispose() {
    saveTimer?.cancel();
    if (total > 0) {
      final value = record();
      final library = widget.library;
      scheduleMicrotask(() => library.save(value));
    }
    request++;
    command.dispose();
    device.setMethodCallHandler(null);
    native('volumeKeys', false);
    native('brightness', -1.0);
    WakelockPlus.disable().catchError((Object _) {});
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final darkTheme = ThemeData.dark(useMaterial3: true).copyWith(
      textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'ArchiveSerif'),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff9cbaa0),
        brightness: Brightness.dark,
      ),
    );
    return Theme(
      data: darkTheme,
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
                  setState(() => controls = !controls),
            },
            child: Focus(
              autofocus: true,
              child: Column(
                children: [
                  if (controls)
                    Container(
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
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                LocalizedText(
                                  widget.comic.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13),
                                ),
                                LocalizedText(
                                  chapter.title,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Color(0xff9cab9d),
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
                  Expanded(
                    child: FutureBuilder<List<String>>(
                      future: loading,
                      builder: (context, s) {
                        if (s.connectionState != ConnectionState.done) {
                          return const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          );
                        }
                        if (s.hasError) {
                          return SingleChildScrollView(
                            child: Column(
                              children: [
                                EmptyState(
                                  icon: Icons.cloud_off_outlined,
                                  title: '这一章暂时无法打开',
                                  message: friendlyError(s.error),
                                  action: () => setState(load),
                                  actionLabel: '重新加载',
                                ),
                                TextButton(
                                  onPressed: () => launchUrl(
                                    Uri.parse(
                                      '${Dm5Source.origin}${chapter.path}',
                                    ),
                                    mode: LaunchMode.externalApplication,
                                  ),
                                  child: const LocalizedText('在动漫屋打开'),
                                ),
                              ],
                            ),
                          );
                        }
                        final pages = s.data!;
                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onTapUp: (d) {
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
                                  setState(() => controls = !controls);
                                }
                              },
                              child: mode == 'strip'
                                  ? StripSurface(
                                      key: ValueKey(
                                        '${chapter.path}-$surfaceGeneration',
                                      ),
                                      urls: pages,
                                      web: widget.web,
                                      startPage: page,
                                      position: fraction,
                                      control: command,
                                      onPosition: position,
                                      speed: (options['autoScroll'] as num)
                                          .toDouble(),
                                      crop: (options['crop'] as num).toDouble(),
                                      autoCrop: options['autoCrop'] == true,
                                      decodeWidth: decodeWidth,
                                    )
                                  : PagedSurface(
                                      key: ValueKey('${chapter.path}-$mode'),
                                      urls: pages,
                                      web: widget.web,
                                      startPage: page,
                                      control: command,
                                      onPosition: position,
                                      rtl: rtl,
                                      vertical: mode == 'vertical',
                                      doublePage: paired,
                                      paper: options['turn'] == 'paper',
                                      crop: (options['crop'] as num).toDouble(),
                                      autoCrop: options['autoCrop'] == true,
                                      decodeWidth: decodeWidth,
                                    ),
                            ),
                            if ((options['brightness'] as num) < 1)
                              IgnorePointer(
                                child: ColoredBox(
                                  color: Colors.black.withValues(
                                    alpha:
                                        1 -
                                        (options['brightness'] as num)
                                            .toDouble(),
                                  ),
                                ),
                              ),
                            if ((options['warmth'] as num) > 0)
                              IgnorePointer(
                                child: ColoredBox(
                                  color: const Color(0xffffad5b).withValues(
                                    alpha:
                                        (options['warmth'] as num).toDouble() *
                                        .18,
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                  if (controls)
                    Container(
                      color: const Color(0xff1c231e),
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: Column(
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
                  if (!controls)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(0, 2, 10, 4),
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
      builder: (c) => AlertDialog(
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

  void catalog() => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => DefaultTabController(
      length: 2,
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
  void settings() => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => StatefulBuilder(
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
                  if (mode == 'strip')
                    slider('自动滚动速度（0 为关闭）', 'autoScroll', 0, 120),
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
