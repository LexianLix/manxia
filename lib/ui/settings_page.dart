import 'package:flutter/material.dart';
import '../data/library.dart';
import '../data/dm5_source.dart';
import 'advanced_settings.dart';
import 'localized_text.dart';
import 'room_motion.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.library,
    required this.source,
    required this.web,
  });
  final Library library;
  final Dm5Source source;
  final bool web;
  void open(BuildContext context, String section, String title) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SettingsSection(
            library: library,
            source: source,
            web: web,
            section: section,
            title: title,
          ),
        ),
      );
  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: ListView(
        key: const PageStorageKey('settings-home-scroll'),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
        children: [
          const LocalizedText(
            '偏好设置',
            style: TextStyle(fontSize: 24, height: 1.4),
          ),
          const SizedBox(height: 6),
          LocalizedText(
            '按习惯整理，让阅读更简单。',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          for (final entry in const [
            ('appearance', '外观与动效', '主题、书架、导航与可读性', Icons.palette_outlined),
            ('reading', '阅读习惯', '背景、双页与工具栏', Icons.auto_stories_outlined),
            ('sources', '漫画源', '默认来源、管理与连接检查', Icons.public),
            ('storage', '下载与缓存', '预载、下载并行与图片缓存', Icons.download_outlined),
            ('backup', '备份与同步', '资料备份、离线书库与 WebDAV', Icons.cloud_sync_outlined),
            ('updates', '关于与更新', '检查版本、在线升级与开源许可', Icons.info_outline),
          ]) ...[
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 6,
              ),
              leading: Icon(entry.$4, size: 21),
              title: LocalizedText(
                entry.$2,
                style: const TextStyle(fontSize: 14),
              ),
              subtitle: LocalizedText(
                entry.$3,
                style: const TextStyle(fontSize: 11, height: 1.6),
              ),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () => open(context, entry.$1, entry.$2),
            ),
            const Divider(height: 1, indent: 46),
          ],
        ],
      ),
    ),
  );
}

class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.library,
    required this.source,
    required this.web,
    required this.section,
    required this.title,
  });
  final Library library;
  final Dm5Source source;
  final bool web;
  final String section, title;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: LocalizedText(title)),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListenableBuilder(
            listenable: library,
            builder: (context, _) => ListView(
              key: PageStorageKey('settings-section-$section'),
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
              children: [
                if (section == 'appearance') ...[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const LocalizedText('夜间阅读室'),
                    value: library.dark,
                    onChanged: (v) => library.setting('dark', v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const LocalizedText('书架动效'),
                    subtitle: const LocalizedText('抽书与页面转场；跟随系统减少动画偏好'),
                    value: library.motion,
                    onChanged: (v) => library.setting('motion', v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const LocalizedText('封面网格'),
                    value: library.grid,
                    onChanged: (v) => library.setting('grid', v),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const LocalizedText('语言与可读性'),
                    subtitle: const LocalizedText('界面语言、文字大小与高对比度'),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SettingsSection(
                          library: library,
                          source: source,
                          web: web,
                          section: 'accessibility',
                          title: '语言与可读性',
                        ),
                      ),
                    ),
                  ),
                ],
                AdvancedSettings(
                  library: library,
                  source: source,
                  web: web,
                  section: section,
                ),
                if (section == 'backup')
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.delete_outline),
                    title: const LocalizedText('清空阅读足迹'),
                    subtitle: const LocalizedText('仅清除本机页码记录，保留收藏'),
                    onTap: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        animationStyle: RoomMotion.sheet(context),
                        builder: (c) => AlertDialog(
                          title: const LocalizedText('清空阅读足迹？'),
                          content: const LocalizedText('已保存的章节和页码记录将被清除。'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: const LocalizedText('取消'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(c, true),
                              child: const LocalizedText('清空'),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) await library.clearHistory();
                    },
                  ),
                if (section == 'updates') ...[
                  const SizedBox(height: 28),
                  const LocalizedText(
                    '漫匣 MANXIA',
                    style: TextStyle(fontSize: 20, letterSpacing: 2),
                  ),
                  const SizedBox(height: 8),
                  const LocalizedText(
                    '为每一段故事，留一个位置。',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const LocalizedText('开源许可与字体声明'),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () => showLicensePage(
                      context: context,
                      applicationName: '漫匣',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
