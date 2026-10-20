import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/comic.dart';
import '../data/dm5_source.dart';
import '../data/library.dart';
import 'app_shell.dart';
import 'book_object.dart';

class ReaderPage extends StatefulWidget {
  const ReaderPage({
    super.key,
    required this.comic,
    required this.chapter,
    required this.library,
    required this.source,
    required this.web,
    this.chapters = const [],
  });
  final Comic comic;
  final Chapter chapter;
  final Library library;
  final Dm5Source source;
  final bool web;
  final List<Chapter> chapters;
  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  late Chapter chapter = widget.chapter;
  late Future<List<String>> loading;
  PageController? controller;
  int page = 0, total = 0;
  bool controls = true;
  late bool rtl = widget.library.rtl;
  late String mode = widget.library.mode;
  Timer? saveTimer;
  int request = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    final generation = ++request;
    final record = widget.library.record(widget.comic);
    page = record?.chapterPath == chapter.path ? record!.page : 0;
    total = 0;
    controller?.dispose();
    controller = null;
    loading = widget.source.pages(chapter.path).then((pages) {
      if (!mounted || generation != request) return pages;
      setState(() {
        total = pages.length;
        page = page.clamp(0, total - 1);
        controller = PageController(initialPage: page);
      });
      save();
      return pages;
    });
  }

  void save() {
    if (total == 0) return;
    widget.library.save(
      ReadingRecord(
        comic: widget.comic,
        chapterPath: chapter.path,
        chapterTitle: chapter.title,
        page: page,
        total: total,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  void changePage(int value) {
    setState(() => page = value);
    saveTimer?.cancel();
    saveTimer = Timer(const Duration(milliseconds: 250), save);
  }

  void turn(int delta) {
    if (controller?.hasClients ?? false) {
      final next = page + delta;
      if (next >= 0 && next < total) {
        controller!.animateToPage(
          next,
          duration: Duration(
            milliseconds:
                widget.library.motion &&
                    !MediaQuery.disableAnimationsOf(context)
                ? 240
                : 1,
          ),
          curve: Curves.easeOut,
        );
      }
    }
  }

  void nextChapter() {
    final index = widget.chapters.indexWhere((c) => c.path == chapter.path);
    if (index >= 0 && index < widget.chapters.length - 1) {
      save();
      setState(() {
        chapter = widget.chapters[index + 1];
        load();
      });
    }
  }

  @override
  void dispose() {
    saveTimer?.cancel();
    if (total > 0) {
      final library = widget.library;
      final record = ReadingRecord(
        comic: widget.comic,
        chapterPath: chapter.path,
        chapterTitle: chapter.title,
        page: page,
        total: total,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      scheduleMicrotask(() => library.save(record));
    }
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final next = widget.chapters.indexWhere((c) => c.path == chapter.path);
    final hasNext = next >= 0 && next < widget.chapters.length - 1;
    return Scaffold(
      backgroundColor: const Color(0xff111512),
      body: SafeArea(
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                turn(rtl ? -1 : 1),
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                turn(rtl ? 1 : -1),
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                Navigator.maybePop(context),
          },
          child: Focus(
            autofocus: true,
            child: Column(
              children: [
                AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  child: controls
                      ? Container(
                          color: const Color(0xff1c231e),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                tooltip: '返回目录',
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(
                                  Icons.arrow_back,
                                  color: Color(0xffe7e9e3),
                                  size: 21,
                                ),
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.comic.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xffe7e9e3),
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      chapter.title,
                                      style: const TextStyle(
                                        color: Color(0xff9ca99d),
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: '阅读设置',
                                onPressed: settings,
                                icon: const Icon(
                                  Icons.tune,
                                  color: Color(0xffd5ddd3),
                                  size: 21,
                                ),
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                Expanded(
                  child: FutureBuilder<List<String>>(
                    future: loading,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xff9cbaa0),
                          ),
                        );
                      }
                      if (snapshot.hasError) {
                        return Theme(
                          data: ThemeData.dark().copyWith(
                            textTheme: Theme.of(context).textTheme.apply(
                              bodyColor: const Color(0xffe7e9e3),
                              displayColor: const Color(0xffe7e9e3),
                            ),
                          ),
                          child: SingleChildScrollView(
                            child: Column(
                              children: [
                                EmptyState(
                                  icon: Icons.cloud_off_outlined,
                                  title: '这一章暂时无法打开',
                                  message: friendlyError(snapshot.error),
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
                                  child: const Text(
                                    '在动漫屋打开',
                                    style: TextStyle(color: Color(0xffa9c6ad)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                      final urls = snapshot.data!;
                      return GestureDetector(
                        onTap: () => setState(() => controls = !controls),
                        child: PageView.builder(
                          key: ValueKey('${chapter.path}-$mode-$rtl'),
                          controller: controller,
                          reverse: mode == 'page' && rtl,
                          scrollDirection: mode == 'page'
                              ? Axis.horizontal
                              : Axis.vertical,
                          onPageChanged: changePage,
                          itemCount: urls.length,
                          itemBuilder: (context, i) => Center(
                            child: InteractiveViewer(
                              key: ValueKey('${chapter.path}-$i'),
                              minScale: 1,
                              maxScale: 4,
                              panEnabled: true,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 1100,
                                ),
                                child: ReaderImage(
                                  url: urls[i],
                                  web: widget.web,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  child: controls
                      ? Container(
                          color: const Color(0xff1c231e),
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
                          child: Column(
                            children: [
                              if (total > 1)
                                SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 2,
                                    thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 5,
                                    ),
                                  ),
                                  child: Slider(
                                    value: page.toDouble(),
                                    max: (total - 1).toDouble(),
                                    divisions: total - 1,
                                    activeColor: const Color(0xff9cbaa0),
                                    inactiveColor: const Color(0xff3c473d),
                                    onChanged: (v) {
                                      if (controller?.hasClients ?? false) {
                                        controller!.jumpToPage(v.round());
                                      }
                                    },
                                  ),
                                ),
                              Row(
                                children: [
                                  IconButton(
                                    tooltip: '上一页',
                                    onPressed: page > 0 ? () => turn(-1) : null,
                                    icon: Icon(
                                      Icons.chevron_left,
                                      color: page > 0
                                          ? const Color(0xffcbd7ca)
                                          : const Color(0xff536053),
                                    ),
                                  ),
                                  Expanded(
                                    child: Column(
                                      children: [
                                        Text(
                                          total == 0
                                              ? '加载章节中'
                                              : '${page + 1} / $total',
                                          style: const TextStyle(
                                            color: Color(0xffd5ddd3),
                                            fontSize: 12,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        const Text(
                                          '轻触画面收起工具栏 · 双指缩放',
                                          style: TextStyle(
                                            color: Color(0xff8b9a8c),
                                            fontSize: 9,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (total > 0 && page == total - 1 && hasNext)
                                    TextButton(
                                      onPressed: nextChapter,
                                      child: const Text(
                                        '下一章',
                                        style: TextStyle(
                                          color: Color(0xffa9c6ad),
                                        ),
                                      ),
                                    )
                                  else
                                    IconButton(
                                      tooltip: '下一页',
                                      onPressed: page < total - 1
                                          ? () => turn(1)
                                          : null,
                                      icon: Icon(
                                        Icons.chevron_right,
                                        color: page < total - 1
                                            ? const Color(0xffcbd7ca)
                                            : const Color(0xff536053),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                if (!controls)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 12, bottom: 5),
                      child: Text(
                        '${page + 1} / $total',
                        style: const TextStyle(
                          color: Color(0xff8b9a8c),
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void settings() => showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 0, 26, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('阅读方式', style: TextStyle(fontSize: 22)),
              const SizedBox(height: 23),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'page',
                    label: Text('横向翻页'),
                    icon: Icon(Icons.swap_horiz),
                  ),
                  ButtonSegment(
                    value: 'vertical',
                    label: Text('纵向翻页'),
                    icon: Icon(Icons.swap_vert),
                  ),
                ],
                selected: {mode},
                onSelectionChanged: (v) {
                  setState(() => mode = v.first);
                  widget.library.setMode(mode);
                  update(() {});
                },
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('从右向左翻页', style: TextStyle(fontSize: 14)),
                value: rtl,
                onChanged: mode == 'page'
                    ? (v) {
                        setState(() => rtl = v);
                        widget.library.setting('rtl', v);
                        update(() {});
                      }
                    : null,
              ),
              const SizedBox(height: 12),
              Text(
                '双指缩放查看细节，轻触画面隐藏工具栏。\n阅读位置自动保存在这台设备。',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.9,
                  color: quiet(context),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class ReaderImage extends StatefulWidget {
  const ReaderImage({super.key, required this.url, required this.web});
  final String url;
  final bool web;
  @override
  State<ReaderImage> createState() => _ReaderImageState();
}

class _ReaderImageState extends State<ReaderImage> {
  int retry = 0;
  @override
  Widget build(BuildContext context) => Image.network(
    imageAddress(widget.url, widget.web),
    key: ValueKey(retry),
    fit: BoxFit.contain,
    headers: widget.web ? null : const {'Referer': 'https://m.dm5.com/'},
    loadingBuilder: (_, child, progress) => progress == null
        ? child
        : const Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xff9cbaa0),
            ),
          ),
    errorBuilder: (_, _, _) => Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.broken_image_outlined,
            color: Color(0xff8b9a8c),
            size: 32,
          ),
          const SizedBox(height: 15),
          const Text(
            '这一页加载失败',
            style: TextStyle(color: Color(0xffcbd7ca), fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () async {
              await NetworkImage(imageAddress(widget.url, widget.web)).evict();
              if (mounted) setState(() => retry++);
            },
            child: const Text(
              '重新加载图片',
              style: TextStyle(color: Color(0xffa9c6ad)),
            ),
          ),
        ],
      ),
    ),
  );
}
