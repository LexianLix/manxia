import 'package:flutter/material.dart';
import '../data/comic.dart';
import '../data/library.dart';
import '../data/reading_queue.dart';
import 'book_link.dart';
import 'localized_text.dart';
import 'room_design.dart';
import 'room_motion.dart';

class ReadingQueuePage extends StatelessWidget {
  const ReadingQueuePage({
    super.key,
    required this.library,
    required this.web,
    required this.onOpen,
  });

  final Library library;
  final bool web;
  final ValueChanged<Comic> onOpen;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const RoomGlassBar(title: '待读队列'),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListenableBuilder(
            listenable: library,
            builder: (context, _) {
              final books = library.readingQueue.books;
              if (books.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: LocalizedText(
                    '在发现页长按封面，把想读的漫画加入这里。',
                    textAlign: TextAlign.center,
                  ),
                );
              }
              return ReorderableListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                buildDefaultDragHandles: false,
                itemCount: books.length,
                onReorderItem: (from, to) =>
                    library.moveQueued(books[from], to),
                itemBuilder: (context, index) {
                  final book = books[index];
                  final progress = library.record(book);
                  return BookLink(
                    key: ValueKey(ReadingQueue.identity(book)),
                    comic: book,
                    web: web,
                    onOpen: onOpen,
                    builder: (cover, open) => ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      leading: SizedBox(
                        width: 36,
                        height: 50,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: cover,
                        ),
                      ),
                      title: Text(
                        book.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: progress == null
                          ? null
                          : Text(
                              progress.chapterTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                      onTap: open,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ReorderableDragStartListener(
                            index: index,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Tooltip(
                                message: translate(
                                  '拖动排序',
                                  Localizations.localeOf(context),
                                ),
                                child: const Icon(Icons.drag_handle_rounded),
                              ),
                            ),
                          ),
                          PopupMenuButton<int>(
                            popUpAnimationStyle: RoomMotion.sheet(context),
                            onSelected: (position) {
                              if (position < 0) {
                                library.setQueued(book, false);
                              } else {
                                library.moveQueued(book, position);
                              }
                            },
                            itemBuilder: (_) => [
                              if (index > 0)
                                PopupMenuItem(
                                  value: index - 1,
                                  child: const LocalizedText('上移'),
                                ),
                              if (index + 1 < books.length)
                                PopupMenuItem(
                                  value: index + 1,
                                  child: const LocalizedText('下移'),
                                ),
                              const PopupMenuItem(
                                value: -1,
                                child: LocalizedText('移出待读'),
                              ),
                            ],
                            icon: const Icon(Icons.more_horiz),
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
      ),
    ),
  );
}
