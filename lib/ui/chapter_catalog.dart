import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../data/comic.dart';
import 'localized_text.dart';
import 'room_motion.dart';

class ChapterCatalog extends StatefulWidget {
  const ChapterCatalog({
    super.key,
    required this.chapters,
    required this.current,
    required this.onSelected,
  });
  final List<Chapter> chapters;
  final String current;
  final ValueChanged<Chapter> onSelected;
  @override
  State<ChapterCatalog> createState() => _ChapterCatalogState();
}

class _ChapterCatalogState extends State<ChapterCatalog> {
  final input = TextEditingController();
  ItemScrollController scroll = ItemScrollController();
  String query = '';
  List<Chapter> get shown => widget.chapters
      .where((c) => c.title.toLowerCase().contains(query.toLowerCase()))
      .toList();
  void filter(String value) {
    if (query == value.trim()) return;
    setState(() {
      query = value.trim();
      scroll = ItemScrollController();
    });
  }

  void locate() {
    if (query.isNotEmpty) {
      input.clear();
      filter('');
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scroll.isAttached) return;
      final index = shown.indexWhere((c) => c.path == widget.current);
      if (index < 0) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        scroll.jumpTo(index: index, alignment: .1);
      } else {
        scroll.scrollTo(
          index: index,
          alignment: .1,
          duration: RoomMotion.page,
          curve: RoomMotion.ease,
        );
      }
    });
    setState(() {});
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = shown;
    final index = list.indexWhere((c) => c.path == widget.current);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: input,
                  onChanged: filter,
                  decoration: InputDecoration(
                    isDense: true,
                    hint: const LocalizedText('搜索章节'),
                    prefixIcon: const Icon(Icons.search, size: 18),
                  ),
                ),
              ),
              IconButton(
                tooltip: translate('定位当前章节', Localizations.localeOf(context)),
                onPressed: locate,
                icon: const Icon(Icons.my_location_outlined, size: 20),
              ),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? const Center(child: LocalizedText('没有匹配的章节'))
              : ScrollablePositionedList.builder(
                  key: ValueKey(query),
                  itemScrollController: scroll,
                  initialScrollIndex: index < 0 ? 0 : index,
                  itemCount: list.length,
                  itemBuilder: (context, i) => ListTile(
                    title: Text(
                      list[i].title,
                      style: const TextStyle(fontSize: 13),
                    ),
                    selected: list[i].path == widget.current,
                    trailing: list[i].path == widget.current
                        ? const Icon(Icons.bookmark_outline, size: 18)
                        : null,
                    onTap: () => widget.onSelected(list[i]),
                  ),
                ),
        ),
      ],
    );
  }
}
