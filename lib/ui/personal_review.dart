import 'package:flutter/material.dart';
import '../data/comic.dart';
import '../data/library.dart';
import '../data/personal_review.dart';
import 'localized_text.dart';
import 'materials.dart';
import 'room_motion.dart';
import 'visible_listenable_builder.dart';

Future<void> editPersonalReview(
  BuildContext context,
  Library library,
  Comic comic,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  barrierColor: Colors.black.withValues(alpha: .22),
  sheetAnimationStyle: RoomMotion.sheet(context),
  builder: (_) => _ReviewEditor(library: library, comic: comic),
);

class PersonalReviewTile extends StatelessWidget {
  const PersonalReviewTile({
    super.key,
    required this.library,
    required this.comic,
    this.showBookTitle = false,
  });
  final Library library;
  final Comic comic;
  final bool showBookTitle;
  @override
  Widget build(BuildContext context) => VisibleListenableBuilder(
    listenable: library,
    builder: (context, _) => ListTile(
      key: const ValueKey('personal-review'),
      contentPadding: showBookTitle
          ? const EdgeInsets.symmetric(horizontal: 16, vertical: 4)
          : EdgeInsets.zero,
      leading: const Icon(Icons.star_outline_rounded),
      title: showBookTitle
          ? Text(comic.title, maxLines: 2, overflow: TextOverflow.ellipsis)
          : const LocalizedText('我的评分与短评'),
      subtitle:
          library.rating(comic) == null && library.reviewText(comic).isEmpty
          ? const LocalizedText('记下自己的阅读感受')
          : Text(
              '${library.rating(comic) == null ? '' : '${'★' * library.rating(comic)!}  '}${library.reviewText(comic)}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: () => editPersonalReview(context, library, comic),
    ),
  );
}

class _ReviewEditor extends StatefulWidget {
  const _ReviewEditor({required this.library, required this.comic});
  final Library library;
  final Comic comic;
  @override
  State<_ReviewEditor> createState() => _ReviewEditorState();
}

class _ReviewEditorState extends State<_ReviewEditor> {
  late int? stars = widget.library.rating(widget.comic);
  late final text = TextEditingController(
    text: widget.library.reviewText(widget.comic),
  );
  bool saving = false;
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: MilkGlass(
      radius: 28,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: LocalizedText(
                    '我的评分与短评',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: translate('关闭', Localizations.localeOf(context)),
                  onPressed: saving ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
            Text(
              widget.comic.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    tooltip: translate(
                      '评分 {count} 星',
                      Localizations.localeOf(context),
                      arguments: {'count': i},
                    ),
                    isSelected: stars != null && i <= stars!,
                    onPressed: saving
                        ? null
                        : () => setState(() => stars = stars == i ? null : i),
                    icon: Icon(
                      stars != null && i <= stars!
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      size: 32,
                    ),
                    color: Theme.of(context).colorScheme.primary,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('review-text'),
              controller: text,
              maxLength: 500,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(
                hintText: translate(
                  '写下自己的感想，仅保存在个人书库',
                  Localizations.localeOf(context),
                ),
              ),
            ),
            const SizedBox(height: 12),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 12,
              overflowSpacing: 8,
              children: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () => setState(() {
                          stars = null;
                          text.clear();
                        }),
                  child: const LocalizedText('清空内容'),
                ),
                FilledButton(
                  key: const ValueKey('save-review'),
                  onPressed: saving
                      ? null
                      : () async {
                          setState(() => saving = true);
                          try {
                            await widget.library.setReview(
                              widget.comic,
                              stars,
                              text.text,
                            );
                            if (context.mounted) Navigator.pop(context);
                          } catch (_) {
                            if (mounted) setState(() => saving = false);
                          }
                        },
                  child: const LocalizedText('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
