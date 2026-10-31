import 'dm5_source.dart';

/// Retain completed pages only when the refreshed catalog still identifies them.
Future<List<String>> refreshChapterLinks(
  Dm5Source source,
  String path,
  List<String> previous, {
  int completed = 0,
}) async {
  final fresh = await source.networkPages(path);
  if (fresh.isEmpty || fresh.length != previous.length) {
    throw ChapterImagesChanged('章节图片数量已变化，请从本章开头重新加载或重新下载。');
  }
  for (var i = 0; i < completed.clamp(0, previous.length); i++) {
    if (Uri.parse(previous[i]).path != Uri.parse(fresh[i]).path) {
      throw ChapterImagesChanged('章节图片顺序已变化，已有页面保留，请从本章开头重新加载或重新下载。');
    }
  }
  return fresh;
}

class ChapterImagesChanged extends SourceException {
  ChapterImagesChanged(super.message);
}

bool expiredImageStatus(int status) => [401, 403, 404, 410].contains(status);
