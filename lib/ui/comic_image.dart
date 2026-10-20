import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../data/offline_library.dart';
import '../data/dm5_source.dart';

String imageAddress(String original, bool web) =>
    web && original.startsWith('https://')
    ? Uri.base
          .resolve('/api/image')
          .replace(queryParameters: {'url': original})
          .toString()
    : original;
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
  });
  final String url;
  final bool web;
  final BoxFit fit;
  final int? cacheWidth;
  final Widget? fallback;
  @override
  State<ComicImage> createState() => _ComicImageState();
}

class _ComicImageState extends State<ComicImage> {
  late Future<ImageProvider> provider = comicImageProvider(
    widget.url,
    widget.web,
  );
  @override
  void didUpdateWidget(ComicImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      provider = comicImageProvider(widget.url, widget.web);
    }
  }

  Widget fallback() =>
      widget.fallback ??
      const Center(child: Icon(Icons.broken_image_outlined, size: 25));
  @override
  Widget build(BuildContext c) => FutureBuilder<ImageProvider>(
    future: provider,
    builder: (c, s) {
      if (s.hasError) return fallback();
      if (!s.hasData) {
        return ColoredBox(
          color: Theme.of(c).colorScheme.onSurface.withValues(alpha: .04),
          child: const Center(child: Icon(Icons.image_outlined, size: 20)),
        );
      }
      return Image(
        image: widget.cacheWidth == null
            ? s.data!
            : ResizeImage.resizeIfNeeded(widget.cacheWidth, null, s.data!),
        fit: widget.fit,
        gaplessPlayback: true,
        frameBuilder: (_, child, frame, sync) => AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: Duration(
            milliseconds: MediaQuery.disableAnimationsOf(c) ? 0 : 180,
          ),
          child: child,
        ),
        errorBuilder: (_, _, _) => fallback(),
      );
    },
  );
}
