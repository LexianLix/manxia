import 'package:flutter/material.dart';
import '../data/comic.dart';
import '../data/discovery_preferences.dart';
import '../data/library.dart';
import 'localized_text.dart';
import 'room_motion.dart';

Future<void> showDiscoveryInterest(
  BuildContext context,
  Library library,
  Comic book,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  sheetAnimationStyle: RoomMotion.sheet(context),
  builder: (c) => SafeArea(
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              book.title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.visibility_off_outlined),
            title: const LocalizedText('对此不感兴趣'),
            onTap: () async {
              await library.hideDiscoveryBook(book, true);
              if (c.mounted) Navigator.pop(c);
            },
          ),
          if (book.author.trim().isNotEmpty)
            ListTile(
              leading: const Icon(Icons.person_off_outlined),
              title: const LocalizedText('屏蔽相同作者'),
              subtitle: Text(book.author),
              onTap: () async {
                await library.blockInterest(
                  'blockedAuthors',
                  book.author,
                  true,
                );
                if (c.mounted) Navigator.pop(c);
              },
            ),
          for (final tag in book.tags)
            ListTile(
              leading: const Icon(Icons.label_off_outlined),
              title: LocalizedText('屏蔽题材：{tag}', arguments: {'tag': tag}),
              onTap: () async {
                await library.blockInterest('blockedTags', tag, true);
                if (c.mounted) Navigator.pop(c);
              },
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextButton(
              onPressed: () => Navigator.pop(c),
              child: const LocalizedText('取消'),
            ),
          ),
        ],
      ),
    ),
  ),
);

class DiscoveryPreferencesPage extends StatelessWidget {
  const DiscoveryPreferencesPage({super.key, required this.library});
  final Library library;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const LocalizedText('发现偏好')),
    body: ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final hidden = library.metadata.values
            .where(
              (m) =>
                  m['discoveryHidden'] == true &&
                  m['discoveryHiddenBook'] is Map,
            )
            .map(
              (m) => Comic.fromJson(
                Map<String, dynamic>.from(m['discoveryHiddenBook']),
              ),
            )
            .toList();
        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const LocalizedText('只整理发现与分类推荐；收藏、离线漫画和主动搜索不受影响。'),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const LocalizedText('隐藏已收藏漫画'),
              value: library.option<bool>('discoveryHideFavorites', false),
              onChanged: (v) => library.setOption('discoveryHideFavorites', v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const LocalizedText('隐藏整本已读漫画'),
              value: library.option<bool>('discoveryHideRead', false),
              onChanged: (v) => library.setOption('discoveryHideRead', v),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: LocalizedText('长按推荐漫画可标记不感兴趣、屏蔽作者或题材。可在下方随时恢复。'),
            ),
            for (final key in ['blockedAuthors', 'blockedTags']) ...[
              const Divider(),
              LocalizedText(
                key == 'blockedAuthors' ? '已屏蔽作者' : '已屏蔽题材',
                style: const TextStyle(fontSize: 18),
              ),
              if (library.blocked(key).isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: LocalizedText('暂无屏蔽项'),
                ),
              for (final value in library.blocked(key))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(value),
                  trailing: TextButton(
                    onPressed: () => library.blockInterest(key, value, false),
                    child: const LocalizedText('恢复显示'),
                  ),
                ),
            ],
            const Divider(),
            const LocalizedText('不感兴趣的漫画', style: TextStyle(fontSize: 18)),
            if (hidden.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LocalizedText('暂无屏蔽项'),
              ),
            for (final book in hidden)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(book.title),
                trailing: TextButton(
                  onPressed: () => library.hideDiscoveryBook(book, false),
                  child: const LocalizedText('恢复显示'),
                ),
              ),
          ],
        );
      },
    ),
  );
}
