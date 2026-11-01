import 'package:flutter/material.dart';
import '../data/comic.dart';
import '../data/library.dart';
import '../data/reading_profiles.dart';
import 'localized_text.dart';
import 'room_motion.dart';
import 'visible_listenable_builder.dart';

class ReadingProfileSelection {
  const ReadingProfileSelection(this.profile, this.asDefault);
  final ReadingProfile profile;
  final bool asDefault;
}

String readingProfileName(BuildContext context, ReadingProfile p) =>
    p.builtin ? translate(p.name, Localizations.localeOf(context)) : p.name;

const readingOptionLabels = <String, String>{
  'mode': '阅读布局',
  'background': '阅读背景',
  'turn': '翻页方式',
  'hand': '操作习惯',
  'toolbarDock': '工具栏位置',
  'chromeTimeout': '工具栏自动收起',
  'brightness': '画面亮度',
  'warmth': '护眼暖色',
  'crop': '手动裁边',
  'rtl': '从右向左翻页',
  'doublePage': '宽屏双页',
  'autoCrop': '自动裁白边',
  'tapZones': '分区点击翻页',
  'doubleTapZoom': '双击局部放大',
  'continuousStrip': '条漫连续跨章',
  'leftTapWidth': '左侧点击区域',
  'rightTapWidth': '右侧点击区域',
};
String readingValue(BuildContext context, String key, dynamic value) {
  final raw = value is bool
      ? (value ? '开启' : '关闭')
      : switch (value) {
          'page' => '横向',
          'vertical' => '竖向',
          'strip' => '连续条漫',
          'theme' => '跟随应用',
          'ink' => '夜墨',
          'paper' => key == 'turn' ? '曲面翻页' : '纸白',
          'sepia' => '旧纸',
          'slide' => '滑动',
          'auto' => '自动',
          'left' => '左手',
          'right' => '右手',
          'top' => '顶部',
          'bottom' => '底部',
          _ => value.toString(),
        };
  if (value is num && key == 'chromeTimeout') {
    return value == 0
        ? translate('手动控制', Localizations.localeOf(context))
        : translate(
            '{count} 秒',
            Localizations.localeOf(context),
            arguments: {'count': value},
          );
  }
  if (value is num) return '${(value * 100).round()}%';
  return translate(raw, Localizations.localeOf(context));
}

class ReadingProfilesPage extends StatelessWidget {
  const ReadingProfilesPage({super.key, required this.library});
  final Library library;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const LocalizedText('个人阅读方案')),
    body: ReadingProfilesPanel(
      library: library,
      current: library.defaultReaderOptions(),
    ),
  );
}

class ReadingProfilesPanel extends StatefulWidget {
  const ReadingProfilesPanel({
    super.key,
    required this.library,
    required this.current,
    this.comic,
    this.onPreview,
  });
  final Library library;
  final Map<String, dynamic> current;
  final Comic? comic;
  final ValueChanged<ReadingProfileSelection>? onPreview;
  @override
  State<ReadingProfilesPanel> createState() => _ReadingProfilesPanelState();
}

class _ReadingProfilesPanelState extends State<ReadingProfilesPanel> {
  String? selected;
  late bool asDefault = widget.comic == null;
  bool busy = false;
  Future<String?> name(String initial) async {
    var value = initial;
    return showDialog<String>(
      context: context,
      animationStyle: RoomMotion.sheet(context),
      builder: (c) => AlertDialog(
        title: const LocalizedText('方案名称'),
        content: TextFormField(
          initialValue: initial,
          maxLength: 32,
          autofocus: true,
          onChanged: (v) => value = v,
          decoration: InputDecoration(
            hintText: translate('例如：睡前阅读', Localizations.localeOf(c)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const LocalizedText('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (value.trim().isNotEmpty) Navigator.pop(c, value.trim());
            },
            child: const LocalizedText('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> save() async {
    final title = await name('');
    if (title == null || !mounted) return;
    try {
      final profile = await widget.library.saveReadingProfile(
        title,
        widget.comic == null
            ? widget.library.defaultReaderOptions()
            : widget.current,
      );
      if (mounted) setState(() => selected = profile.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> edit(ReadingProfile p, String action) async {
    if (action == 'rename') {
      final title = await name(p.name);
      if (title != null) {
        await widget.library.saveReadingProfile(title, p.values, id: p.id);
      }
    } else {
      final ok = await showDialog<bool>(
        context: context,
        animationStyle: RoomMotion.sheet(context),
        builder: (c) => AlertDialog(
          title: const LocalizedText('删除阅读方案？'),
          content: const LocalizedText('只删除方案，保留漫画、阅读进度和逐本设置。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const LocalizedText('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const LocalizedText('删除'),
            ),
          ],
        ),
      );
      if (ok == true) await widget.library.deleteReadingProfile(p.id);
    }
  }

  Future<void> apply(ReadingProfile p) async {
    if (widget.onPreview != null) {
      widget.onPreview!(ReadingProfileSelection(p, asDefault));
      return;
    }
    setState(() => busy = true);
    try {
      final change = await widget.library.applyReadingProfile(
        widget.comic,
        p,
        asDefault: asDefault,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const LocalizedText('阅读方案已应用'),
          action: SnackBarAction(
            label: translate('撤销', Localizations.localeOf(context)),
            onPressed: () => change.undo(),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => VisibleListenableBuilder(
    listenable: widget.library,
    builder: (context, _) {
      final profiles = widget.library.readingProfiles;
      final active =
          profiles
              .where(
                (p) =>
                    p.id ==
                    (selected ??
                        widget.library.options['reader.profileDefault']),
              )
              .firstOrNull ??
          profiles.firstOrNull;
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          const LocalizedText(
            '把顺手的阅读方式，留成自己的方案。',
            style: TextStyle(fontSize: 16, height: 1.5),
          ),
          const SizedBox(height: 8),
          const LocalizedText(
            '逐本设置优先于默认方案；默认方案优先于阅读插件和基础设置。',
            style: TextStyle(fontSize: 12, height: 1.7),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: busy ? null : save,
              icon: const Icon(Icons.add, size: 18),
              label: const LocalizedText('保存当前设置为方案'),
            ),
          ),
          if (widget.onPreview == null &&
              widget.library.options['reader.profileDefault'] != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: busy
                    ? null
                    : () => widget.library.setOption(
                        'reader.profileDefault',
                        null,
                      ),
                child: const LocalizedText('恢复基础默认设置'),
              ),
            ),
          const SizedBox(height: 12),
          if (profiles.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: LocalizedText('还没有阅读方案，可以保存当前设置。'),
            ),
          RadioGroup<String>(
            groupValue: active?.id,
            onChanged: (id) => setState(() => selected = id),
            child: Column(
              children: [
                for (final p in profiles)
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<String>(
                          value: p.id,
                          contentPadding: EdgeInsets.zero,
                          title: Text(readingProfileName(context, p)),
                          subtitle:
                              widget.library.options['reader.profileDefault'] ==
                                  p.id
                              ? const LocalizedText('默认方案')
                              : null,
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: translate(
                          '方案操作',
                          Localizations.localeOf(context),
                        ),
                        onSelected: (v) => edit(p, v),
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'rename',
                            child: LocalizedText('重命名'),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: LocalizedText('删除'),
                          ),
                        ],
                      ),
                    ],
                  ),
              ],
            ),
          ),
          if (active != null) ...[
            const Divider(height: 28),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const LocalizedText('包含的设置'),
              children: [
                for (final e in active.values.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: LocalizedText(
                            readingOptionLabels[e.key] ?? e.key,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            readingValue(context, e.key, e.value),
                            style: const TextStyle(fontSize: 12),
                            textAlign: TextAlign.end,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            if (widget.comic != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const LocalizedText('设为所有漫画的默认方案'),
                subtitle: const LocalizedText('本书已有的单独设置仍然优先。'),
                value: asDefault,
                onChanged: (v) => setState(() => asDefault = v),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: busy ? null : () => apply(active),
              icon: Icon(
                widget.onPreview != null
                    ? Icons.visibility_outlined
                    : Icons.check,
                size: 18,
              ),
              label: LocalizedText(
                widget.onPreview != null ? '预览方案' : '应用为默认方案',
              ),
            ),
          ],
        ],
      );
    },
  );
}
