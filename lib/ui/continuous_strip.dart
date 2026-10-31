import 'dart:async';
import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../data/comic.dart';
import '../data/dm5_source.dart';
import '../data/chapter_links.dart';
import 'localized_text.dart';
import 'reader_surfaces.dart';
import 'room_motion.dart';

class ContinuousStrip extends StatefulWidget {
  const ContinuousStrip({
    super.key,
    required this.chapter,
    required this.urls,
    required this.catalog,
    required this.source,
    required this.control,
    required this.startPage,
    required this.position,
    required this.web,
    required this.onPosition,
    required this.onReady,
    required this.onInitialError,
    required this.onRestart,
    required this.active,
    this.warm = true,
    this.speed = 0,
    this.crop = 0,
    this.autoCrop = false,
    this.decodeWidth = 1800,
  });
  final Chapter chapter;
  final List<String> urls;
  final List<Chapter> catalog;
  final Dm5Source source;
  final ReaderControl control;
  final int startPage, decodeWidth;
  final double position, speed, crop;
  final bool web, autoCrop, active, warm;
  final void Function(Chapter, List<String>, int, double) onPosition;
  final VoidCallback onReady;
  final ValueChanged<Object> onInitialError;
  final ValueChanged<Chapter> onRestart;
  @override
  State<ContinuousStrip> createState() => _ContinuousStripState();
}

class _Segment {
  _Segment(this.chapter, this.urls);
  final Chapter chapter;
  List<String> urls;
  Object? error;
  bool refreshed = false, refreshing = false;
  int get count => urls.length + 1;
}

typedef _Item = ({_Segment segment, int page});

class _ContinuousStripState extends State<ContinuousStrip> {
  late final seed = _Segment(widget.chapter, List.unmodifiable(widget.urls));
  late final segments = <_Segment>[seed];
  late String currentPath = seed.chapter.path;
  late final initialPage = widget.startPage.clamp(0, seed.urls.length - 1);
  late final initialFraction = widget.position;
  final scroll = ItemScrollController();
  final positions = ItemPositionsListener.create();
  final offset = ScrollOffsetController();
  final zoomTargets = <Object, bool Function(Offset)>{};
  final aspects = <String, double>{};
  String aspectKey(String url) =>
      '$url|${widget.crop}|${widget.autoCrop}|${widget.decodeWidth}';
  final loading = <int>{};
  final failures = <int, Object>{};
  final firstPageReady = <String>{};
  _Segment? pendingBefore;
  Timer? timer;
  bool restored = false, scrolling = false, anchoring = false;
  int reserve = 0;
  double height = 600;
  List<_Item> get items => [
    for (final s in segments) ...[
      (segment: s, page: -1),
      for (var i = 0; i < s.urls.length; i++) (segment: s, page: i),
    ],
  ];
  List<ItemPosition> visible() =>
      positions.itemPositions.value
          .where((p) => p.itemTrailingEdge > .001 && p.itemLeadingEdge < .999)
          .toList()
        ..sort((a, b) => a.index.compareTo(b.index));
  @override
  void initState() {
    super.initState();
    positions.itemPositions.addListener(report);
    widget.control.addListener(jump);
    widget.control.onZoom = (point) {
      for (final open in zoomTargets.values.toList().reversed) {
        if (open(point)) break;
      }
    };
    auto();
  }

  @override
  void didUpdateWidget(ContinuousStrip old) {
    super.didUpdateWidget(old);
    if (old.crop != widget.crop ||
        old.autoCrop != widget.autoCrop ||
        old.decodeWidth != widget.decodeWidth) {
      aspects.clear();
    }
    if (old.speed != widget.speed || old.active != widget.active) auto();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) report();
    });
  }

  void auto() {
    timer?.cancel();
    if (widget.active && widget.speed > 0) {
      timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (mounted && scroll.isAttached && restored) {
          offset.animateScroll(
            offset: widget.speed / 10,
            duration: const Duration(milliseconds: 100),
          );
        }
      });
    }
  }

  void report() {
    if (!mounted || !restored || anchoring) return;
    final list = items, shown = visible();
    for (final p in shown) {
      final i = p.index - 1;
      if (i < 0 || i >= list.length || list[i].page < 0) continue;
      final item = list[i];
      if (!firstPageReady.contains(item.segment.chapter.path)) break;
      currentPath = item.segment.chapter.path;
      final extent = p.itemTrailingEdge - p.itemLeadingEdge;
      widget.onPosition(
        item.segment.chapter,
        item.segment.urls,
        item.page,
        extent <= 0 ? 0 : (-p.itemLeadingEdge / extent).clamp(0, 1),
      );
      break;
    }
    if (!widget.active || shown.isEmpty) return;
    if (shown.last.index >= list.length + (widget.warm ? -3 : 1)) {
      loadNeighbor(1);
    }
    if (shown.first.index <= (widget.warm ? 3 : 0)) loadNeighbor(-1);
    if (!scrolling) {
      commitBefore();
      prune();
    }
  }

  Chapter? neighbor(int direction) {
    final edge = direction < 0 ? segments.first.chapter : segments.last.chapter;
    final index = widget.catalog.indexWhere((c) => c.path == edge.path);
    final target = index + direction;
    return index >= 0 && target >= 0 && target < widget.catalog.length
        ? widget.catalog[target]
        : null;
  }

  Future<void> loadNeighbor(int direction) async {
    if (!widget.active ||
        loading.contains(direction) ||
        failures.containsKey(direction) ||
        segments.length >= 7 ||
        (direction < 0 && pendingBefore != null)) {
      return;
    }
    final next = neighbor(direction);
    if (next == null || segments.any((s) => s.chapter.path == next.path)) {
      return;
    }
    setState(() => loading.add(direction));
    try {
      final urls = await widget.source.pages(next.path);
      if (urls.isEmpty) throw SourceException('这一章没有返回可读取的图片，请重新加载。');
      if (!mounted || !widget.active) return;
      // A prepared first image avoids showing a new chapter as an empty frame.
      var decoded = true;
      final provider = await pageProvider(
        urls.first,
        widget.web,
        widget.decodeWidth,
      );
      if (!mounted) return;
      await precacheImage(
        provider,
        context,
        onError: (_, _) => decoded = false,
      );
      if (!mounted || !widget.active) return;
      final segment = _Segment(next, List.unmodifiable(urls));
      if (decoded) firstPageReady.add(next.path);
      if (direction < 0) {
        pendingBefore = segment;
        await commitBefore();
      } else {
        setState(() => segments.add(segment));
      }
    } catch (error) {
      if (mounted) setState(() => failures[direction] = error);
    } finally {
      if (mounted) setState(() => loading.remove(direction));
    }
  }

  Future<void> commitBefore() async {
    final incoming = pendingBefore;
    if (incoming == null || scrolling || anchoring || !mounted) return;
    anchoring = true;
    // Reserve indices before moving the anchor. Both list states then rebuild
    // in one frame, so jumpTo cannot clamp to the old shorter item count.
    setState(() => reserve = incoming.count);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final anchor = visible().firstOrNull;
    if (scrolling || anchor == null) {
      setState(() => reserve = 0);
      anchoring = false;
      return;
    }
    setState(() {
      segments.insert(0, incoming);
      pendingBefore = null;
      reserve = 0;
    });
    scroll.jumpTo(
      index: anchor.index + incoming.count,
      alignment: anchor.itemLeadingEdge,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      anchoring = false;
      report();
      prune();
    });
  }

  void prune() {
    if (scrolling || anchoring || segments.length <= 5 || !scroll.isAttached) {
      return;
    }
    final current = segments.indexWhere((s) => s.chapter.path == currentPath);
    final start = (current - 2).clamp(0, segments.length - 5);
    final anchor = visible().firstOrNull;
    if (anchor == null) return;
    final removed = segments.take(start).fold<int>(0, (n, s) => n + s.count);
    final kept = segments.skip(start).take(5).toList();
    final live = kept.expand((s) => s.urls).map(aspectKey).toSet();
    aspects.removeWhere((key, _) => !live.contains(key));
    anchoring = true;
    setState(
      () => segments
        ..clear()
        ..addAll(kept),
    );
    if (removed > 0) {
      scroll.jumpTo(
        index: anchor.index - removed,
        alignment: anchor.itemLeadingEdge,
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        anchoring = false;
        report();
      }
    });
  }

  void jump() {
    if (!scroll.isAttached) return;
    final list = items;
    final index = list.indexWhere(
      (i) =>
          i.segment.chapter.path == currentPath &&
          i.page == widget.control.page,
    );
    if (index < 0) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      scroll.jumpTo(index: index + 1);
      widget.control.settle(widget.control.page);
    } else {
      scroll
          .scrollTo(
            index: index + 1,
            duration: RoomMotion.page,
            curve: RoomMotion.ease,
          )
          .then((_) {
            if (mounted) widget.control.settle(widget.control.page);
          });
    }
  }

  void restore(double contentHeight) {
    if (restored || !mounted) return;
    restored = true;
    firstPageReady.add(seed.chapter.path);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (scroll.isAttached) {
        // Anchor absolutely after decode: relative offsets can be stale while
        // adjacent placeholders grow, especially at the end of a chapter.
        scroll.jumpTo(
          index: initialPage + 2,
          alignment: -initialFraction * contentHeight / height,
        );
        await WidgetsBinding.instance.endOfFrame;
      }
      if (mounted) {
        widget.onReady();
        report();
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  Future<void> refresh(_Segment segment, {bool automatic = false}) async {
    if (segment.refreshing || (automatic && segment.refreshed)) return;
    segment.refreshed = true;
    segment.refreshing = true;
    try {
      final fresh = await refreshChapterLinks(
        widget.source,
        segment.chapter.path,
        segment.urls,
        completed: segment.urls.length,
      );
      if (!mounted || !segments.contains(segment)) return;
      setState(() {
        segment.urls = List.unmodifiable(fresh);
        segment.error = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) report();
      });
    } catch (e) {
      if (mounted && segments.contains(segment)) {
        setState(() => segment.error = e);
        if (!restored && identical(segment, seed)) widget.onInitialError(e);
      }
    } finally {
      segment.refreshing = false;
    }
  }

  void imageError(_Segment segment, int page, Object error) {
    if (error is NetworkImageLoadException &&
        expiredImageStatus(error.statusCode) &&
        !segment.refreshed) {
      refresh(segment, automatic: true);
    } else if (!restored && identical(segment, seed) && page == initialPage) {
      widget.onInitialError(error);
    }
  }

  Widget boundary(int direction) => SizedBox(
    height: 72,
    child: Center(
      child: loading.contains(direction)
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : neighbor(direction) == null
          ? LocalizedText(
              direction < 0 ? '已到本书开头' : '已到当前目录末尾',
              style: const TextStyle(fontSize: 12),
            )
          : TextButton.icon(
              onPressed: () {
                setState(() => failures.remove(direction));
                loadNeighbor(direction);
              },
              icon: Icon(
                failures.containsKey(direction)
                    ? Icons.refresh
                    : direction < 0
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
              ),
              label: LocalizedText(
                failures.containsKey(direction)
                    ? '邻章准备失败，点此重试'
                    : direction < 0
                    ? '接入上一章'
                    : '接入下一章',
              ),
            ),
    ),
  );
  @override
  void dispose() {
    timer?.cancel();
    positions.itemPositions.removeListener(report);
    widget.control.removeListener(jump);
    widget.control.onZoom = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      height = box.maxHeight;
      final list = items;
      return NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.depth != 0) return false;
          if (n is ScrollStartNotification) {
            scrolling = true;
            widget.control.target = null;
          }
          if (n is ScrollEndNotification) {
            scrolling = false;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                commitBefore();
                prune();
                report();
              }
            });
          }
          return false;
        },
        child: ScrollablePositionedList.builder(
          itemScrollController: scroll,
          itemPositionsListener: positions,
          scrollOffsetController: offset,
          initialScrollIndex: initialPage + 2,
          minCacheExtent: height * .6,
          padding: EdgeInsets.zero,
          itemCount: list.length + 2 + reserve,
          itemBuilder: (context, index) {
            if (index >= list.length + 2) return const SizedBox.shrink();
            if (index == 0) return boundary(-1);
            if (index == list.length + 1) return boundary(1);
            final item = list[index - 1], segment = item.segment;
            if (item.page < 0) {
              return SizedBox(
                height: 72,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    children: [
                      const Icon(Icons.menu_book_outlined, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          segment.chapter.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (segment.error != null)
                        TextButton(
                          onPressed: () => widget.onRestart(segment.chapter),
                          child: const LocalizedText('从章首重新打开'),
                        ),
                    ],
                  ),
                ),
              );
            }
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: PagePicture(
                  segment.urls[item.page],
                  web: widget.web,
                  strip: true,
                  knownAspect: aspects[aspectKey(segment.urls[item.page])],
                  crop: widget.crop,
                  autoCrop: widget.autoCrop,
                  decodeWidth: widget.decodeWidth,
                  registerZoom: (owner, open) {
                    if (open == null) {
                      zoomTargets.remove(owner);
                    } else {
                      zoomTargets[owner] = open;
                    }
                  },
                  onReady: (extent) {
                    aspects[aspectKey(segment.urls[item.page])] =
                        box.maxWidth.clamp(0, 1000) / extent;
                    firstPageReady.add(segment.chapter.path);
                    if (identical(segment, seed) && item.page == initialPage) {
                      restore(extent);
                    }
                  },
                  onImageError: (e) => imageError(segment, item.page, e),
                  onRetry: segment.urls[item.page].startsWith('offline:')
                      ? null
                      : () => refresh(segment),
                ),
              ),
            );
          },
        ),
      );
    },
  );
}
