import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../data/offline_library.dart';
import '../data/dm5_source.dart';
import 'cover_arrival.dart';

String imageAddress(String original, bool web) =>
    web && original.startsWith('https://')
    ? Uri.base
          .resolve('/api/image')
          .replace(queryParameters: {'url': original})
          .toString()
    : original;

/// No new cache: reuse the offline library's bounded cache or Flutter's
/// existing NetworkImage cache. A known disk-only cover still loads normally.
ImageProvider? immediateComicImageProvider(String url, bool web) {
  final offline = OfflineLibrary.instance;
  if (url.startsWith('offline:')) {
    final bytes = offline?.peek(url.substring(8));
    return bytes == null ? null : MemoryImage(bytes);
  }
  final entry = offline?.entries
      .where((e) => e['comic']['cover'] == url && e['coverKey'] != null)
      .firstOrNull;
  if (entry != null) {
    final bytes = offline!.peek(entry['coverKey']);
    return bytes == null ? null : MemoryImage(bytes);
  }
  return NetworkImage(
    imageAddress(url, web),
    headers: web ? null : Dm5Source.headersForImage(url),
  );
}

Future<ImageProvider> comicImageProvider(String url, bool web) async {
  if (url.startsWith('offline:')) {
    final Uint8List? bytes = await OfflineLibrary.instance?.read(
      url.substring(8),
    );
    if (bytes == null) throw StateError('离线图片不存在');
    return MemoryImage(bytes);
  }
  final cover = await OfflineLibrary.instance?.cachedCover(url);
  if (cover != null) return MemoryImage(cover);
  return NetworkImage(
    imageAddress(url, web),
    headers: web ? null : Dm5Source.headersForImage(url),
  );
}

class ComicImage extends StatefulWidget {
  const ComicImage(
    this.url, {
    super.key,
    required this.web,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.fallback,
    this.animate = true,
  });
  final String url;
  final bool web;
  final bool animate;
  final BoxFit fit;
  final int? cacheWidth;
  final Widget? fallback;
  @override
  State<ComicImage> createState() => _ComicImageState();
}

class _ComicImageState extends State<ComicImage> {
  late ImageProvider? immediate = immediateComicImageProvider(
    widget.url,
    widget.web,
  );
  late Future<ImageProvider> provider = comicImageProvider(
    widget.url,
    widget.web,
  );
  @override
  void didUpdateWidget(ComicImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url || old.web != widget.web) {
      immediate = immediateComicImageProvider(widget.url, widget.web);
      provider = comicImageProvider(widget.url, widget.web);
    }
  }

  Widget fallback() =>
      widget.fallback ??
      const Center(child: Icon(Icons.broken_image_outlined, size: 25));
  Widget loading(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .04),
    child: const Center(child: Icon(Icons.image_outlined, size: 20)),
  );
  Widget picture(BuildContext c, ImageProvider provider) => Image(
    image: widget.cacheWidth == null
        ? provider
        : ResizeImage.resizeIfNeeded(widget.cacheWidth, null, provider),
    fit: widget.fit,
    gaplessPlayback: true,
    frameBuilder: (_, child, frame, sync) => CoverArrival(
      identity: widget.url,
      ready: frame != null,
      immediate: sync || !widget.animate,
      placeholder: loading(c),
      child: child,
    ),
    errorBuilder: (_, _, _) => fallback(),
  );
  @override
  Widget build(BuildContext c) => immediate != null
      ? picture(c, immediate!)
      : FutureBuilder<ImageProvider>(
          key: ValueKey(widget.url),
          future: provider,
          builder: (c, s) {
            if (s.hasError) return fallback();
            if (!s.hasData) {
              return loading(c);
            }
            return picture(c, s.data!);
          },
        );
}
