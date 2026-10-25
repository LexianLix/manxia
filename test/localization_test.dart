import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manxia/ui/localized_text.dart';

void main() {
  test('reader and search labels match the current interface wording', () {
    for (final locale in [const Locale('zh', 'TW'), const Locale('en')]) {
      for (final label in [
        '横向',
        '连续条漫',
        '竖向',
        '护眼暖色',
        '纸页弯曲',
        '搜索漫画名称',
        '搜索漫画作者',
        '搜索漫画、章节或笔记',
        '手动裁边',
        '自动滚动速度（0 为关闭）',
      ]) {
        expect(
          translate(label, locale),
          isNot(label),
          reason: '$locale: $label',
        );
      }
    }
    expect(translate('书签已保存', const Locale('zh', 'TW')), '書籤已儲存');
    expect(translate('未读', const Locale('zh', 'TW')), '未讀');
    expect(translate('检查更新', const Locale('en')), 'Check for updates');
    expect(translate('下载', const Locale('en')), 'Downloads');
    expect(translate('插件', const Locale('en')), 'Plugins');
    expect(translate('下载', const Locale('zh', 'TW')), '下載');
    expect(translate('插件', const Locale('zh', 'TW')), '外掛');
  });

  test('copyright notices survive merging while source titles stay intact', () {
    const tw = Locale('zh', 'TW');
    expect(translate('当前书源没有版权', tw), '當前書源沒有版權');
    expect(translate('书源没有版权', tw), '書源沒有版權');
    expect(translate('阅读已下载章节', tw), '閱讀已下載章節');
    expect(
      translate('阅读已下载章节', const Locale('en')),
      'Read downloaded chapters',
    );
    expect(translate('火影忍者', tw), '火影忍者');
    expect(translate('Book title', const Locale('en')), 'Book title');
    expect(translate('书签已保存', const Locale('zh', 'CN')), '书签已保存');
  });
}
