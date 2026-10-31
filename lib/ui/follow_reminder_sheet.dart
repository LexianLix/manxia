import 'package:flutter/material.dart';
import '../platform/follow_reminder.dart';
import 'localized_text.dart';
import 'room_motion.dart';

Future<void> showFollowReminder(BuildContext context) async {
  Map<String, dynamic> config;
  try {
    config = await FollowReminder.load();
  } catch (_) {
    config = {'available': false};
  }
  if (!context.mounted) return;
  var enabled = config['enabled'] == true, busy = false;
  final available = config['available'] == true;
  final days = Set<int>.from(config['days'] as List? ?? [5]);
  var time = TimeOfDay(
    hour: config['hour'] as int? ?? 20,
    minute: config['minute'] as int? ?? 0,
  );
  String? message;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    sheetAnimationStyle: RoomMotion.sheet(context),
    builder: (c) => StatefulBuilder(
      builder: (c, update) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const LocalizedText(
                '追漫提醒',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const LocalizedText('按你设置的时间提醒打开日历，不代表作品必定更新。系统省电策略可能延迟通知。'),
              if (!available)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: LocalizedText('本机提醒仅在 Android 安装版提供；日历仍可正常使用。'),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const LocalizedText('每周提醒'),
                value: enabled,
                onChanged: available && !busy
                    ? (value) => update(() => enabled = value)
                    : null,
              ),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (var day = 1; day <= 7; day++)
                    FilterChip(
                      label: Text(
                        MaterialLocalizations.of(c).narrowWeekdays[day % 7],
                      ),
                      selected: days.contains(day),
                      onSelected: !available || busy
                          ? null
                          : (value) => update(() {
                              if (value) {
                                days.add(day);
                              } else {
                                days.remove(day);
                              }
                            }),
                    ),
                ],
              ),
              TextButton.icon(
                icon: const Icon(Icons.schedule),
                label: Text(time.format(c)),
                onPressed: available && !busy
                    ? () async {
                        final value = await showTimePicker(
                          context: c,
                          initialTime: time,
                        );
                        if (value != null && c.mounted) {
                          update(() => time = value);
                        }
                      }
                    : null,
              ),
              if (message != null) LocalizedText(message!),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: !available || busy || (enabled && days.isEmpty)
                    ? null
                    : () async {
                        update(() {
                          busy = true;
                          message = null;
                        });
                        try {
                          final locale = Localizations.localeOf(c);
                          final result = await FollowReminder.save(
                            enabled: enabled,
                            days: days.toList(),
                            hour: time.hour,
                            minute: time.minute,
                            title: translate('该看看喜欢的漫画了', locale),
                            body: translate('打开追漫日历，检查收藏的新章节。', locale),
                          );
                          if (!c.mounted) return;
                          if (enabled && result['allowed'] != true) {
                            update(() {
                              enabled = false;
                              message = '系统未允许通知，提醒尚未开启；可在系统通知设置中允许后重试。';
                            });
                          } else {
                            Navigator.pop(c);
                          }
                        } catch (_) {
                          if (c.mounted) update(() => message = '提醒保存失败，请稍后重试');
                        } finally {
                          if (c.mounted) update(() => busy = false);
                        }
                      },
                child: LocalizedText(busy ? '正在保存…' : '保存'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
