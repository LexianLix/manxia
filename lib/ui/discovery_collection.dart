import 'package:flutter/material.dart';
import '../data/comic.dart';
import '../data/dm5_source.dart';
import '../data/library.dart';
import 'app_shell.dart' show ComicGrid, EmptyState, small;
import 'localized_text.dart';
import 'source_browser.dart';

/// A full collection has its own scroll position and loads the source's real
/// pagination only when a corresponding source link is present.
class DiscoveryCollection extends StatelessWidget {
  const DiscoveryCollection({
    super.key,
    required this.title,
    required this.books,
    required this.library,
    required this.source,
    required this.web,
    required this.onOpen,
    this.path,
  });
  final String title;
  final List<Comic> books;
  final Library library;
  final Dm5Source source;
  final bool web;
  final ValueChanged<Comic> onOpen;
  final String? path;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: library,
    builder: (context, _) => buildCollection(context),
  );
  Widget buildCollection(BuildContext context) => Scaffold(
    appBar: AppBar(title: LocalizedText(title)),
    body: LayoutBuilder(
      builder: (context, box) {
        final displayed = library.browseBooks(books);
        final inset = box.maxWidth > 1148 ? (box.maxWidth - 1100) / 2 : 24.0;
        if (path != null) {
          return CustomScrollView(
            key: PageStorageKey('source-collection-$path'),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(inset, 16, inset, 48),
                sliver: SourceBrowser(
                  source: source,
                  library: library,
                  web: web,
                  onOpen: onOpen,
                  initialPath: path,
                  initialBooks: books,
                  sliver: true,
                ),
              ),
            ],
          );
        }
        return CustomScrollView(
          key: PageStorageKey('discovery-collection-$title'),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(inset, 16, inset, 24),
              sliver: SliverToBoxAdapter(
                child: LocalizedText(
                  '${displayed.length} 部漫画',
                  style: small(context),
                ),
              ),
            ),
            if (displayed.isEmpty)
              const SliverToBoxAdapter(
                child: EmptyState(
                  icon: Icons.auto_stories_outlined,
                  title: '这里还没有漫画',
                  message: '试试其他栏目，或稍后刷新。',
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(inset, 0, inset, 48),
                sliver: ComicGrid(
                  books: displayed,
                  library: library,
                  web: web,
                  onOpen: onOpen,
                  sliver: true,
                ),
              ),
          ],
        );
      },
    ),
  );
}
