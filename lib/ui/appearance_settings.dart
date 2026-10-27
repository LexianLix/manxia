import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../data/appearance.dart';
import '../data/library.dart';
import 'localized_text.dart';
import 'materials.dart';

class AppearanceSettings extends StatefulWidget {
  const AppearanceSettings({super.key, required this.library});
  final Library library;
  @override
  State<AppearanceSettings> createState() => _AppearanceSettingsState();
}

class _AppearanceSettingsState extends State<AppearanceSettings> {
  bool busy = false;
  final sliderValues = <String, double>{};
  String? error;
  RoomAppearance get appearance => RoomAppearance(widget.library.options);
  Future<void> change(Map<String, dynamic> values) =>
      widget.library.setOption('appearance', {...appearance.values, ...values});

  Future<void> pick() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    final library = widget.library;
    final old = appearance.wallpaper;
    try {
      final file = await FilePicker.pickFile(type: FileType.image);
      if (file == null) return;
      if ((await file.length() ?? 0) > 20 * 1024 * 1024) {
        throw const FormatException('请选择 20 MB 以内的背景图片。');
      }
      final wallpaper = await WallpaperStore.shared.save(
        await file.readAsBytes(),
      );
      // A completed import can safely finish even if this settings page closed.
      final current = RoomAppearance(library.options);
      await library.setOption('appearance', {
        ...current.values,
        'wallpaper': wallpaper.key,
        'name': file.name,
        'seed': wallpaper.seed.toARGB32(),
      });
      if (old != null && old != wallpaper.key) {
        try {
          await WallpaperStore.shared.remove(old);
        } catch (_) {
          /* Optional old image cleanup. */
        }
      }
    } catch (e) {
      if (mounted) {
        setState(
          () =>
              error = e is FormatException ? e.message : '无法导入这张背景图片，请选择其他图片。',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> reset() async {
    final old = appearance.wallpaper;
    await widget.library.setOption('appearance', {
      'follow': appearance.follow,
      'veil': appearance.veil,
      'blur': appearance.blur,
    });
    if (old != null) {
      try {
        await WallpaperStore.shared.remove(old);
      } catch (_) {
        /* Preferences already reset. */
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = appearance;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MilkGlass(
          radius: 20,
          high: widget.library.option<String>('quality', 'high') == 'high',
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 48,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.wallpaper_outlined, color: scheme.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const LocalizedText(
                      '晴昼玻璃',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      style.wallpaper == null
                          ? translate(
                              '清透的阅读室，换上你的背景。',
                              Localizations.localeOf(context),
                            )
                          : style.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (busy)
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                IconButton(
                  key: const ValueKey('choose-wallpaper'),
                  tooltip: translate('选择背景图片', Localizations.localeOf(context)),
                  onPressed: pick,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                ),
            ],
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: LocalizedText(
              error!,
              style: TextStyle(color: scheme.error, fontSize: 12),
            ),
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const LocalizedText('跟随背景配色'),
          subtitle: const LocalizedText('从图片提取主题色，统一导航、按钮与阅读工具栏'),
          value: style.follow,
          onChanged: busy ? null : (v) => change({'follow': v}),
        ),
        if (style.wallpaper != null) ...[
          _slider('背景遮罩', style.veil, .20, .90, 'veil'),
          _slider('背景柔化', style.blur, 0, 12, 'blur'),
          const LocalizedText(
            '图片只保存在本机；备份中的外观设置不包含背景图片文件。',
            style: TextStyle(fontSize: 12),
          ),
          TextButton.icon(
            onPressed: busy ? null : reset,
            icon: const Icon(Icons.restart_alt, size: 18),
            label: const LocalizedText('恢复默认背景'),
          ),
        ],
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _slider(
    String title,
    double value,
    double min,
    double max,
    String key,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 10),
        child: LocalizedText(title),
      ),
      Slider(
        value: sliderValues[key] ?? value,
        min: min,
        max: max,
        semanticFormatterCallback: (v) =>
            '${(v * (key == 'veil' ? 100 : 1)).round()}',
        onChanged: busy ? null : (v) => setState(() => sliderValues[key] = v),
        onChangeEnd: busy
            ? null
            : (v) async {
                await change({key: v});
                if (mounted) setState(() => sliderValues.remove(key));
              },
      ),
    ],
  );
}
