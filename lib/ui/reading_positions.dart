import 'package:flutter/material.dart';
import '../data/comic.dart';
import '../data/library.dart';
import 'localized_text.dart';
import 'materials.dart';
import 'room_motion.dart';

Future<ReadingRecord?> selectReadingPosition(
  BuildContext context,
  Library library,
  Comic comic,
) async {
  ModalRoute<dynamic>? route;
  final result = await showModalBottomSheet<ReadingRecord>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: .22),
    sheetAnimationStyle: RoomMotion.sheet(context),
    builder: (c) {
      route = ModalRoute.of(c);
      final points = library.journal.forComic(comic);
      return MilkGlass(
        radius: 28,
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        child: SizedBox(
          height: MediaQuery.sizeOf(c).height * .65,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: LocalizedText(
                      '阅读位置记录',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: translate('关闭', Localizations.localeOf(c)),
                    onPressed: () => Navigator.pop(c),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
              Text(comic.title, maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 12),
              const LocalizedText(
                '选择曾经停留的位置；打开记录前保留当前进度。',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: points.isEmpty
                    ? const Center(child: LocalizedText('还没有可恢复的位置，阅读后会自动保留。'))
                    : ListView.builder(
                        itemCount: points.length,
                        itemBuilder: (c, i) {
                          final point = points[i],
                              at = DateTime.fromMillisecondsSinceEpoch(
                                points[i].updatedAt,
                              );
                          return ListTile(
                            key: ValueKey('reading-position-$i'),
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.history, size: 20),
                            title: Text(
                              '${point.chapterTitle} · ${point.page + 1} / ${point.total}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${MaterialLocalizations.of(c).formatCompactDate(at)} ${TimeOfDay.fromDateTime(at).format(c)}',
                            ),
                            trailing: const Icon(Icons.chevron_right, size: 18),
                            onTap: () => Navigator.pop(c, point),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      );
    },
  );
  await route?.completed;
  return result;
}
