import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'comic_image.dart';
import 'localized_text.dart';

class ReaderThumbnail extends StatelessWidget {
  const ReaderThumbnail({super.key, required this.url, required this.web});
  final String url;
  final bool web;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .04),
    child: ComicImage(
      url,
      web: web,
      fit: BoxFit.contain,
      cacheWidth: 160,
      cacheHeight: 240,
      animate: false,
      fallback: const Center(
        child: Icon(Icons.image_not_supported_outlined, size: 20),
      ),
    ),
  );
}

/// Only visible thumbnails decode; opening or scrolling does not seek the reader.
class ReaderPageMap extends StatefulWidget {
  const ReaderPageMap({
    super.key,
    required this.urls,
    required this.web,
    required this.selected,
  });
  final List<String> urls;
  final bool web;
  final int selected;
  @override
  State<ReaderPageMap> createState() => _ReaderPageMapState();
}

class _ReaderPageMapState extends State<ReaderPageMap> {
  ScrollController? scroll;
  @override
  void dispose() {
    scroll?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .78,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
            child: Row(
              children: [
                const Expanded(
                  child: LocalizedText(
                    '页面缩略图',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: translate('关闭', Localizations.localeOf(context)),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: LocalizedText(
                '点击页面跳转，可返回刚才的阅读位置',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                final columns = (box.maxWidth / 100).floor().clamp(3, 8);
                final cell = (box.maxWidth - 40 - (columns - 1) * 12) / columns;
                final extent = cell * 1.5 + 30;
                scroll ??= ScrollController(
                  initialScrollOffset: math.max(
                    0,
                    (widget.selected ~/ columns - 1) * (extent + 12),
                  ),
                );
                return GridView.builder(
                  scrollCacheExtent: ScrollCacheExtent.pixels(extent),
                  key: const ValueKey('reader-page-map-grid'),
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisExtent: extent,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: widget.urls.length,
                  itemBuilder: (context, index) {
                    final selected = index == widget.selected;
                    return Semantics(
                      selected: selected,
                      button: true,
                      label: translate(
                        '第 {page} 页',
                        Localizations.localeOf(context),
                        arguments: {'page': index + 1},
                      ),
                      child: InkWell(
                        key: ValueKey('page-map-$index'),
                        onTap: () => Navigator.pop(context, index),
                        borderRadius: BorderRadius.circular(10),
                        child: Column(
                          children: [
                            Expanded(
                              child: Container(
                                clipBehavior: Clip.antiAlias,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    width: selected ? 2 : 1,
                                    color: selected
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(context).dividerColor,
                                  ),
                                ),
                                child: ReaderThumbnail(
                                  url: widget.urls[index],
                                  web: widget.web,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${index + 1}',
                              style: TextStyle(
                                fontSize: 12,
                                color: selected
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
