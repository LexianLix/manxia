import 'localized_text.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'comic_image.dart';
import 'room_motion.dart';

class ReaderControl extends ChangeNotifier {
  int page = 0;
  int? target;
  double position = 0;
  Matrix4 transform = Matrix4.identity();
  int transformPage = 0;
  void go(int value, {double position = 0}) {
    page = value;
    target = value;
    this.position = position;
    notifyListeners();
  }

  void settle(int value) {
    page = value;
    target = null;
  }
}

typedef PagePosition = void Function(int page, double fraction);
Future<ImageProvider> pageProvider(String url, bool web, int width) async =>
    ResizeImage(
      await comicImageProvider(url, web),
      width: width,
      height: 8192,
      policy: ResizeImagePolicy.fit,
    );

class PagedSurface extends StatefulWidget {
  const PagedSurface({
    super.key,
    required this.urls,
    required this.web,
    required this.startPage,
    required this.control,
    required this.onPosition,
    this.onReady,
    this.onLoadError,
    this.rtl = false,
    this.vertical = false,
    this.doublePage = false,
    this.paper = false,
    this.crop = 0,
    this.autoCrop = false,
    this.decodeWidth = 1800,
  });
  final List<String> urls;
  final bool web, rtl, vertical, doublePage, paper, autoCrop;
  final int startPage, decodeWidth;
  final double crop;
  final ReaderControl control;
  final PagePosition onPosition;
  final VoidCallback? onReady, onLoadError;
  @override
  State<PagedSurface> createState() => _PagedSurfaceState();
}

class _PagedSurfaceState extends State<PagedSurface> {
  late final viewport = TransformationController(
    Matrix4.copy(widget.control.transform),
  );
  Drag? drag;
  ScrollHoldController? hold;
  Offset gestureTravel = Offset.zero;
  bool zoomed = false;
  void interactStart(ScaleStartDetails details) {
    if (!controller.hasClients) return;
    gestureTravel = Offset.zero;
    if (zoomed || details.pointerCount > 1) {
      hold ??= controller.position.hold(() => hold = null);
    } else {
      widget.control.target = null;
      drag = controller.position.drag(
        DragStartDetails(
          globalPosition: details.focalPoint,
          localPosition: details.localFocalPoint,
        ),
        () => drag = null,
      );
    }
  }

  void interactUpdate(ScaleUpdateDetails details) {
    if (!controller.hasClients) return;
    if (zoomed || details.pointerCount > 1 || details.scale != 1) {
      drag?.cancel();
      drag = null;
      hold ??= controller.position.hold(() => hold = null);
      return;
    }
    drag ??= controller.position.drag(
      DragStartDetails(
        globalPosition: details.focalPoint,
        localPosition: details.localFocalPoint,
      ),
      () => drag = null,
    );
    gestureTravel += details.focalPointDelta;
    final primary = widget.vertical ? gestureTravel.dy : gestureTravel.dx;
    final cross = widget.vertical ? gestureTravel.dx : gestureTravel.dy;
    if (primary.abs() < cross.abs()) return;
    final delta = widget.vertical
        ? details.focalPointDelta.dy
        : details.focalPointDelta.dx;
    drag!.update(
      DragUpdateDetails(
        delta: widget.vertical ? Offset(0, delta) : Offset(delta, 0),
        primaryDelta: delta,
        globalPosition: details.focalPoint,
        localPosition: details.localFocalPoint,
      ),
    );
  }

  void interactEnd(ScaleEndDetails details) {
    final active = drag;
    drag = null;
    if (details.pointerCount > 0) {
      active?.cancel();
    } else {
      var speed = widget.vertical
          ? details.velocity.pixelsPerSecond.dy
          : details.velocity.pixelsPerSecond.dx;
      final primary = widget.vertical ? gestureTravel.dy : gestureTravel.dx;
      final cross = widget.vertical ? gestureTravel.dx : gestureTravel.dy;
      if (primary.abs() < cross.abs() ||
          speed.abs() < controller.position.physics.minFlingVelocity) {
        speed = 0;
      }
      active?.end(
        DragEndDetails(
          velocity: Velocity(
            pixelsPerSecond: widget.vertical
                ? Offset(0, speed)
                : Offset(speed, 0),
          ),
          primaryVelocity: speed,
        ),
      );
    }
    hold?.cancel();
    hold = null;
  }

  void transformed() {
    widget.control.transform = Matrix4.copy(viewport.value);
    if (controller.hasClients) {
      widget.control.transformPage = page((controller.page ?? 0).round());
    }
    final value = viewport.value.getMaxScaleOnAxis() > 1.001;
    if (mounted && value != zoomed) setState(() => zoomed = value);
  }

  final prepared = <int, String>{};
  String? announced;
  String identity(int index) =>
      '${widget.urls[index]}|${widget.decodeWidth}|${widget.autoCrop}';
  Set<int> get initialPages {
    final first = page(view(widget.startPage));
    return {
      first,
      if (widget.doublePage && first > 0 && first + 1 < widget.urls.length)
        first + 1,
    };
  }

  void ready(int index) {
    if (!mounted) return;
    prepared[index] = identity(index);
    checkReady();
  }

  void checkReady() {
    if (!mounted) return;
    final required = initialPages;
    if (!required.every((p) => prepared[p] == identity(p))) return;
    final key = required.map(identity).join('|');
    if (announced == key) return;
    announced = key;
    widget.onReady?.call();
  }

  late PageController controller = PageController(
    initialPage: view(widget.startPage),
  );
  int view(int p) => !widget.doublePage
      ? p
      : p == 0
      ? 0
      : 1 + (p - 1) ~/ 2;
  int page(int v) => !widget.doublePage
      ? v
      : v == 0
      ? 0
      : 1 + (v - 1) * 2;
  @override
  void initState() {
    super.initState();
    viewport.addListener(transformed);
    zoomed = viewport.value.getMaxScaleOnAxis() > 1.001;
    widget.control.addListener(jump);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final target = widget.control.target;
    if (target != null && MediaQuery.disableAnimationsOf(context)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            widget.control.target == target &&
            controller.hasClients) {
          controller.jumpToPage(view(target));
          widget.control.settle(page(view(target)));
        }
      });
    }
  }

  void jump() {
    if (controller.hasClients) {
      if (zoomed) viewport.value = Matrix4.identity();
      final target = view(widget.control.page);
      if (MediaQuery.disableAnimationsOf(context)) {
        controller.jumpToPage(target);
        widget.control.settle(page(target));
        return;
      }
      final distance = (target - (controller.page ?? target)).abs();
      controller.animateToPage(
        target,
        duration: Duration(
          milliseconds: (RoomMotion.page.inMilliseconds * math.sqrt(distance))
              .round()
              .clamp(100, 340),
        ),
        curve: RoomMotion.ease,
      );
    }
  }

  @override
  void didUpdateWidget(PagedSurface old) {
    super.didUpdateWidget(old);
    if (old.doublePage != widget.doublePage) {
      final prior = controller;
      controller = PageController(initialPage: view(widget.startPage));
      WidgetsBinding.instance.addPostFrameCallback((_) => prior.dispose());
    }
    if (prepared.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) checkReady();
      });
    }
  }

  @override
  void dispose() {
    drag?.cancel();
    hold?.cancel();
    widget.control.removeListener(jump);
    viewport.dispose();
    controller.dispose();
    super.dispose();
  }

  Widget picture(
    String url, {
    required int index,
    double curl = 0,
    Alignment alignment = Alignment.center,
  }) => PagePicture(
    url,
    web: widget.web,
    crop: widget.crop,
    autoCrop: widget.autoCrop,
    decodeWidth: widget.decodeWidth,
    curl: curl,
    alignment: alignment,
    onReady: (_) => ready(index),
    onLoadError: () {
      if (initialPages.contains(index)) widget.onLoadError?.call();
    },
  );
  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return RepaintBoundary(
      child: MediaQuery(
        // Scale's pan threshold is twice touchSlop. Match the normal scroll
        // threshold here, while leaving child taps/long presses unchanged.
        data: media.copyWith(
          gestureSettings: DeviceGestureSettings(
            touchSlop: (media.gestureSettings.touchSlop ?? kTouchSlop) / 2,
          ),
        ),
        child: InteractiveViewer(
          transformationController: viewport,
          minScale: 1,
          maxScale: 4,
          panEnabled: zoomed,
          onInteractionStart: interactStart,
          onInteractionUpdate: interactUpdate,
          onInteractionEnd: interactEnd,
          // One recognizer owns both gestures. Single-finger deltas drive the
          // actual scroll position; a pinch remains inside InteractiveViewer.
          child: MediaQuery(
            data: media,
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification.depth != 0) return false;
                if (notification is ScrollStartNotification &&
                    notification.dragDetails != null) {
                  widget.control.target = null;
                } else if (notification is ScrollEndNotification &&
                    controller.hasClients) {
                  widget.control.settle(page((controller.page ?? 0).round()));
                }
                return false;
              },
              child: PageView.builder(
                // Delegate pointer drags to the single outer recognizer;
                // keep scroll physics, wheel input and semantic actions.
                scrollBehavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: const <PointerDeviceKind>{},
                  scrollbars: false,
                ),
                key: ValueKey(
                  '${widget.rtl}-${widget.vertical}-${widget.doublePage}',
                ),
                controller: controller,
                reverse: widget.rtl && !widget.vertical,
                scrollDirection: widget.vertical
                    ? Axis.vertical
                    : Axis.horizontal,
                itemCount: widget.doublePage
                    ? 1 + ((widget.urls.length - 1) / 2).ceil()
                    : widget.urls.length,
                onPageChanged: (v) => widget.onPosition(page(v), 0),
                itemBuilder: (context, i) {
                  final p = page(i);
                  final images = [
                    p,
                    if (widget.doublePage &&
                        p > 0 &&
                        p + 1 < widget.urls.length)
                      p + 1,
                  ];
                  if (widget.rtl) images.sort((a, b) => b.compareTo(a));
                  final content = Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final entry in images.indexed)
                        Expanded(
                          child: picture(
                            widget.urls[entry.$2],
                            index: entry.$2,
                            alignment: images.length == 1
                                ? Alignment.center
                                : entry.$1 == 0
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                          ),
                        ),
                    ],
                  );
                  if (!widget.paper || widget.vertical) {
                    return content;
                  }
                  return AnimatedBuilder(
                    animation: controller,
                    builder: (context, _) {
                      final progress =
                          !MediaQuery.disableAnimationsOf(context) &&
                              controller.hasClients &&
                              controller.position.hasContentDimensions
                          ? (controller.page ?? i.toDouble()) - i
                          : 0.0;
                      // The image mesh owns the fold and shadow. A second clipping
                      // curve/rotation used to cut across it and darken whole pages.
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (final entry in images.indexed)
                            Expanded(
                              child: picture(
                                widget.urls[entry.$2],
                                index: entry.$2,
                                curl: progress <= 0
                                    ? 0
                                    : widget.rtl
                                    ? -progress
                                    : progress,
                                alignment: images.length == 1
                                    ? Alignment.center
                                    : entry.$1 == 0
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                              ),
                            ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class StripSurface extends StatefulWidget {
  const StripSurface({
    super.key,
    required this.urls,
    required this.web,
    required this.startPage,
    required this.position,
    required this.control,
    required this.onPosition,
    this.onReady,
    this.onLoadError,
    this.speed = 0,
    this.crop = 0,
    this.autoCrop = false,
    this.decodeWidth = 1800,
  });
  final List<String> urls;
  final bool web, autoCrop;
  final int startPage, decodeWidth;
  final double position, speed, crop;
  final ReaderControl control;
  final PagePosition onPosition;
  final VoidCallback? onReady, onLoadError;
  @override
  State<StripSurface> createState() => _StripSurfaceState();
}

class _StripSurfaceState extends State<StripSurface> {
  final scroll = ItemScrollController();
  final positions = ItemPositionsListener.create();
  final offset = ScrollOffsetController();
  Timer? timer;
  bool restored = false;
  late final initialPage = widget.startPage;
  late final initialFraction = widget.position;
  double height = 600;
  @override
  void initState() {
    super.initState();
    positions.itemPositions.addListener(report);
    widget.control.addListener(jump);
    auto();
  }

  void report() {
    if (!restored && initialFraction > 0) return;
    final visible =
        positions.itemPositions.value
            .where((p) => p.itemTrailingEdge > 0 && p.itemLeadingEdge < 1)
            .toList()
          ..sort((a, b) => a.index.compareTo(b.index));
    if (visible.isEmpty) return;
    final first = visible.first;
    final size = first.itemTrailingEdge - first.itemLeadingEdge;
    widget.onPosition(
      first.index,
      size <= 0 ? 0 : (-first.itemLeadingEdge / size).clamp(0, 1),
    );
  }

  void jump() {
    if (scroll.isAttached) {
      final target = widget.control.page.clamp(0, widget.urls.length - 1);
      if (MediaQuery.disableAnimationsOf(context)) {
        scroll.jumpTo(index: target);
        widget.control.settle(target);
      } else {
        scroll
            .scrollTo(
              index: target,
              duration: RoomMotion.page,
              curve: RoomMotion.ease,
            )
            .then((_) {
              if (mounted && widget.control.target == target) {
                widget.control.settle(target);
              }
            });
      }
    }
  }

  void restore(double contentHeight) {
    if (restored || !mounted) return;
    restored = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (scroll.isAttached) {
        // Earlier images can grow from placeholders during decode. The target
        // page may no longer start at the viewport edge, so include its actual
        // leading position instead of treating a relative delta as absolute.
        final leading =
            positions.itemPositions.value
                .where((p) => p.index == initialPage)
                .firstOrNull
                ?.itemLeadingEdge ??
            0;
        final delta = leading * height + initialFraction * contentHeight;
        if (delta.abs() > .5) {
          await offset.animateScroll(
            offset: delta,
            duration: const Duration(milliseconds: 1),
          );
        }
      }
      if (mounted) widget.onReady?.call();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void auto() {
    timer?.cancel();
    if (widget.speed > 0) {
      timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (mounted &&
            scroll.isAttached &&
            positions.itemPositions.value.isNotEmpty) {
          offset.animateScroll(
            offset: widget.speed / 10,
            duration: const Duration(milliseconds: 100),
          );
        }
      });
    }
  }

  @override
  void didUpdateWidget(StripSurface old) {
    super.didUpdateWidget(old);
    if (old.speed != widget.speed) auto();
  }

  @override
  void dispose() {
    timer?.cancel();
    positions.itemPositions.removeListener(report);
    widget.control.removeListener(jump);
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => LayoutBuilder(
    builder: (c, b) {
      height = b.maxHeight;
      return ScrollablePositionedList.builder(
        itemScrollController: scroll,
        itemPositionsListener: positions,
        scrollOffsetController: offset,
        initialScrollIndex: initialPage.clamp(0, widget.urls.length - 1),
        minCacheExtent: height * .6,
        itemCount: widget.urls.length,
        padding: EdgeInsets.zero,
        itemBuilder: (c, i) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: PagePicture(
              widget.urls[i],
              web: widget.web,
              strip: true,
              crop: widget.crop,
              autoCrop: widget.autoCrop,
              decodeWidth: widget.decodeWidth,
              onReady: i == initialPage ? restore : null,
              onLoadError: i == initialPage ? widget.onLoadError : null,
            ),
          ),
        ),
      );
    },
  );
}

Rect detectWhiteMargins(Uint8List bytes, int width, int height) {
  bool row(int y) {
    var white = 0, total = 0;
    for (var x = 0; x < width; x += math.max(1, width ~/ 32)) {
      final p = (y * width + x) * 4;
      total++;
      if (bytes[p] > 246 && bytes[p + 1] > 246 && bytes[p + 2] > 246) white++;
    }
    return white / total > .98;
  }

  bool col(int x) {
    var white = 0, total = 0;
    for (var y = 0; y < height; y += math.max(1, height ~/ 32)) {
      final p = (y * width + x) * 4;
      total++;
      if (bytes[p] > 246 && bytes[p + 1] > 246 && bytes[p + 2] > 246) white++;
    }
    return white / total > .98;
  }

  var top = 0, bottom = height - 1, left = 0, right = width - 1;
  while (top < height * .15 && row(top)) {
    top++;
  }
  while (bottom > height * .85 && row(bottom)) {
    bottom--;
  }
  while (left < width * .15 && col(left)) {
    left++;
  }
  while (right > width * .85 && col(right)) {
    right--;
  }
  return Rect.fromLTRB(
    left.toDouble(),
    top.toDouble(),
    (right + 1).toDouble(),
    (bottom + 1).toDouble(),
  );
}

class PagePicture extends StatefulWidget {
  const PagePicture(
    this.url, {
    super.key,
    required this.web,
    this.strip = false,
    this.crop = 0,
    this.autoCrop = false,
    this.decodeWidth = 1800,
    this.onReady,
    this.onLoadError,
    this.curl = 0,
    this.alignment = Alignment.center,
  });
  final String url;
  final bool web, strip, autoCrop;
  final double crop;
  final int decodeWidth;
  final ValueChanged<double>? onReady;
  final VoidCallback? onLoadError;
  final double curl;
  final Alignment alignment;
  @override
  State<PagePicture> createState() => _PagePictureState();
}

class _PagePictureState extends State<PagePicture> {
  ImageStream? stream;
  ImageStreamListener? listener;
  ui.Image? image;
  ImageInfo? frame;
  Rect? trim;
  String? error;
  int request = 0;
  int decodedRequest = -1;
  bool announced = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (stream == null) load();
  }

  @override
  void didUpdateWidget(PagePicture old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url ||
        old.autoCrop != widget.autoCrop ||
        old.decodeWidth != widget.decodeWidth) {
      load();
    }
  }

  Future<void> load() async {
    announced = false;
    final generation = ++request;
    if (listener != null) stream?.removeListener(listener!);
    try {
      final provider = await pageProvider(
        widget.url,
        widget.web,
        widget.decodeWidth,
      );
      if (!mounted || generation != request) return;
      stream = provider.resolve(createLocalImageConfiguration(context));
      listener = ImageStreamListener(
        (info, _) async {
          Rect? crop;
          if (widget.autoCrop) {
            final data = await info.image.toByteData();
            if (data != null) {
              crop = detectWhiteMargins(
                data.buffer.asUint8List(),
                info.image.width,
                info.image.height,
              );
            }
          }
          if (!mounted || generation != request) {
            info.dispose();
            return;
          }
          final previous = frame;
          frame = info;
          setState(() {
            decodedRequest = generation;
            image = info.image;
            trim = crop;
            error = null;
          });
          previous?.dispose();
        },
        onError: (Object e, StackTrace? _) {
          if (mounted && generation == request) {
            setState(() => error = '这一页加载失败');
            widget.onLoadError?.call();
          }
        },
      );
      stream!.addListener(listener!);
    } catch (_) {
      if (mounted && generation == request) {
        setState(() => error = '离线图片不存在或无法读取');
        widget.onLoadError?.call();
      }
    }
  }

  @override
  void dispose() {
    request++;
    if (listener != null) stream?.removeListener(listener!);
    frame?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    if (error != null) {
      return SizedBox(
        height: widget.strip ? 260 : null,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.broken_image_outlined, color: Colors.grey),
              const SizedBox(height: 12),
              LocalizedText(
                error!,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              TextButton(onPressed: load, child: const LocalizedText('重新加载图片')),
            ],
          ),
        ),
      );
    }
    if (image == null) {
      return SizedBox(
        height: widget.strip ? 300 : null,
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Theme.of(c).colorScheme.primary,
          ),
        ),
      );
    }
    final bitmap = image!;
    var source =
        trim ??
        Rect.fromLTWH(0, 0, bitmap.width.toDouble(), bitmap.height.toDouble());
    source = source.deflate(
      math.min(source.width, source.height) * widget.crop.clamp(0, .18),
    );
    return LayoutBuilder(
      builder: (c, b) {
        final width = b.maxWidth;
        final natural = width * source.height / source.width;
        final height = widget.strip ? natural : b.maxHeight;
        if (!announced && widget.onReady != null && decodedRequest == request) {
          announced = true;
          final generation = request;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && generation == request && error == null) {
              widget.onReady?.call(height);
            }
          });
        }
        return GestureDetector(
          onLongPress: () => showDialog(
            context: c,
            animationStyle: RoomMotion.sheet(c),
            builder: (dialogContext) => Dialog.fullscreen(
              backgroundColor: Colors.black,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: InteractiveViewer(
                      minScale: 1,
                      maxScale: 5,
                      child: Center(
                        child: RawImage(image: bitmap, fit: BoxFit.contain),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton(
                      tooltip: '关闭大图',
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
          child: SizedBox(
            width: width,
            height: height,
            child: CustomPaint(
              painter: _PicturePainter(
                bitmap,
                source,
                widget.curl,
                widget.alignment,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PicturePainter extends CustomPainter {
  _PicturePainter(this.image, this.source, this.curl, this.alignment);
  final ui.Image image;
  final Rect source;
  final double curl;
  final Alignment alignment;
  @override
  void paint(Canvas canvas, Size size) {
    final fitted = applyBoxFit(BoxFit.contain, source.size, size);
    final rect = alignment.inscribe(fitted.destination, Offset.zero & size);
    if (curl.abs() > .002) {
      final t = curl.abs().clamp(0.0, 1.0);
      final positions = <Offset>[], textures = <Offset>[];
      final colors = <Color>[], indices = <int>[];
      const segments = 40;
      final edge = 1 - t * .85;
      final radius = rect.width * (.13 + .2 * t);
      for (var i = 0; i <= segments; i++) {
        final u = i / segments;
        final fold = ((u - edge) * rect.width / radius).clamp(
          0.0,
          math.pi * .92,
        );
        final x = u < edge
            ? u * rect.width
            : edge * rect.width + math.sin(fold) * radius;
        final z = (1 - math.cos(fold)) * radius;
        final perspective = 1 / (1 + z / 1300);
        final light = (.65 + .35 * math.cos(fold)).clamp(.4, 1.0);
        for (final v in [0.0, 1.0]) {
          positions.add(
            Offset(
              rect.left + (curl >= 0 ? x : rect.width - x),
              rect.center.dy + (v - .5) * rect.height * perspective,
            ),
          );
          textures.add(
            Offset(
              source.left + (curl >= 0 ? u : 1 - u) * source.width,
              source.top + v * source.height,
            ),
          );
          colors.add(
            Color.fromRGBO(
              (255 * light).round(),
              (255 * light).round(),
              (255 * light).round(),
              1,
            ),
          );
        }
        if (i < segments) {
          final k = i * 2;
          indices.addAll([k, k + 1, k + 2, k + 2, k + 1, k + 3]);
        }
      }
      final outline = Path()..moveTo(positions.first.dx, positions.first.dy);
      for (var i = 0; i < positions.length; i += 2) {
        outline.lineTo(positions[i].dx, positions[i].dy);
      }
      for (var i = positions.length - 1; i >= 1; i -= 2) {
        outline.lineTo(positions[i].dx, positions[i].dy);
      }
      outline.close();
      canvas.drawShadow(
        outline,
        Colors.black.withValues(alpha: .5 * t),
        12 * t,
        false,
      );
      // The bent front exposes the paper back, not a transparent hole between
      // sheets. Keep this inside the image bounds, including letterboxing.
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: curl >= 0 ? Alignment.centerRight : Alignment.centerLeft,
            end: curl >= 0 ? Alignment.centerLeft : Alignment.centerRight,
            colors: const [
              Color(0xffd9d6ca),
              Color(0xfff5f2e8),
              Color(0xfffaf8f1),
            ],
            stops: const [0, .16, 1],
          ).createShader(rect),
      );
      final mesh = ui.Vertices(
        ui.VertexMode.triangles,
        positions,
        textureCoordinates: textures,
        colors: colors,
        indices: indices,
      );
      canvas.drawVertices(
        mesh,
        BlendMode.modulate,
        Paint()
          ..shader = ui.ImageShader(
            image,
            TileMode.clamp,
            TileMode.clamp,
            Matrix4.identity().storage,
          )
          ..filterQuality = FilterQuality.medium,
      );
      mesh.dispose();
      return;
    }
    canvas.drawImageRect(
      image,
      source,
      rect,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_PicturePainter old) =>
      old.image != image ||
      old.source != source ||
      old.curl != curl ||
      old.alignment != alignment;
}
