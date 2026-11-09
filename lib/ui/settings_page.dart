import 'browse_chrome.dart';
import 'room_design.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'character_settings_page.dart';
import 'visible_listenable_builder.dart';
import 'package:flutter/material.dart';
import '../data/library.dart';
import '../data/dm5_source.dart';
import 'advanced_settings.dart';
import 'localized_text.dart';
import 'room_motion.dart';
import 'appearance_settings.dart';
import 'smoothness_page.dart';
import 'reading_profiles_page.dart';
import 'reading_stats_page.dart';
import 'plugins_page.dart';

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
          builder: (_) => section == 'plugins'
              ? PluginsPage(library: library)
              : section == 'stats'
              ? ReadingStatsPage(library: library, source: source, web: web)
              : section == 'reviews'
              ? PersonalReviewsPage(library: library)
              : SettingsSection(
                  library: library,
                  source: source,
                  web: web,
                  section: section,
                  title: title,
                ),
        ),
      );
  Widget entry(
    BuildContext context,
    String id,
    String title,
    IconData icon,
    Color color,
  ) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
    minLeadingWidth: 32,
    leading: Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .05),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 19, color: Theme.of(context).colorScheme.primary),
    ),
    title: LocalizedText(
      title,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
    ),
    trailing: Icon(
      CupertinoIcons.chevron_right,
      size: 14,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .3),
    ),
    onTap: () => open(context, id, title),
  );
  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: BrowseEdges(
        child: ListView(
          key: const PageStorageKey('settings-home-scroll'),
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 112),
          children: [
            const RoomPageHeading(title: '偏好设置'),
            const SizedBox(height: 22),
            RoomGroupedSection(
              children: [
                entry(
                  context,
                  'appearance',
                  '外观与动效',
                  CupertinoIcons.paintbrush,
                  const Color(0xff7765ce),
                ),
                entry(
                  context,
                  'reading',
                  '阅读习惯',
                  CupertinoIcons.book,
                  const Color(0xff387edb),
                ),
                entry(
                  context,
                  'stats',
                  '阅读统计',
                  CupertinoIcons.chart_bar,
                  const Color(0xff4b94b6),
                ),
                entry(
                  context,
                  'reviews',
                  '我的评分与短评',
                  CupertinoIcons.star,
                  const Color(0xffd79535),
                ),
              ],
            ),
            const SizedBox(height: 22),
            RoomGroupedSection(
              children: [
                entry(
                  context,
                  'plugins',
                  '插件商城',
                  CupertinoIcons.square_grid_2x2,
                  const Color(0xff535964),
                ),
                entry(
                  context,
                  'sources',
                  '漫画源',
                  CupertinoIcons.globe,
                  const Color(0xff35a180),
                ),
                entry(
                  context,
                  'storage',
                  '下载与缓存',
                  CupertinoIcons.arrow_down_circle,
                  const Color(0xffec9a30),
                ),
                entry(
                  context,
                  'backup',
                  '备份与同步',
                  CupertinoIcons.cloud,
                  const Color(0xff5795dc),
                ),
              ],
            ),
            const SizedBox(height: 22),
            RoomGroupedSection(
              children: [
                entry(
                  context,
                  'updates',
                  '关于与更新',
                  CupertinoIcons.info_circle,
                  const Color(0xff89909c),
                ),
              ],
            ),
          ],
        ),
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
    appBar: RoomGlassBar(title: title),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: VisibleListenableBuilder(
            listenable: library,
            builder: (context, _) => ListView(
              key: PageStorageKey('settings-section-$section'),
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
              children: [
                if (section == 'appearance') ...[
                  AppearanceSettings(library: library),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const LocalizedText('小夏与阅读伙伴'),
                    subtitle: const LocalizedText('角色包、陪伴提醒与显示偏好'),
                    leading: const Icon(Icons.face_outlined),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => CharacterSettingsPage(library: library),
                      ),
                    ),
                  ),
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
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const LocalizedText('流畅度检测'),
                    subtitle: const LocalizedText('记录滑动与翻页时的画面耗时'),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SmoothnessPage(),
                      ),
                    ),
                  ),
                ],
                if (section == 'reading')
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.bookmarks_outlined),
                    title: const LocalizedText('个人阅读方案'),
                    subtitle: const LocalizedText('保存自己的样式，预览后再应用'),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ReadingProfilesPage(library: library),
                      ),
                    ),
                  ),
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
