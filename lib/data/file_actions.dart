import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:pdfx/pdfx.dart';
import 'comic.dart';
import 'library.dart';
import 'offline_library.dart';
import '../platform/storage.dart';

class FileActions {
  static Future<Uri?> exportLibrary(
    OfflineLibrary offline,
  ) async => FilePicker.saveFile(
    fileName:
        'manxia-library-${DateTime.now().toIso8601String().substring(0, 10)}.zip',
    bytes: await offline.exportBundle(),
    mimeType: 'application/zip',
  );
  static Future<bool> importLibrary(OfflineLibrary offline) async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (file == null) return false;
    if ((await file.length() ?? 0) > 512 * 1024 * 1024) {
      throw const FormatException('书库备份超过 512 MB。');
    }
    await offline.importBundle(await file.readAsBytes());
    return true;
  }

  static Future<Comic?> importBook(
    OfflineLibrary offline, {
    bool images = false,
    bool folder = false,
  }) async {
    if (folder) {
      final path = await FilePicker.getDirectoryPath(dialogTitle: '选择漫画图片文件夹');
      if (path == null) return null;
      final list = await readImageFolder(path);
      return offline.importImages(path.split(RegExp(r'[/\\]')).last, list);
    }
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: images
          ? ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp']
          : ['cbz', 'zip', 'pdf'],
    );
    if (files.isEmpty) return null;
    if (images) {
      final list = <({String name, Uint8List bytes})>[];
      for (final file in files) {
        list.add((name: file.name, bytes: await file.readAsBytes()));
      }
      return offline.importImages(
        files.length == 1 ? files.first.name : '本地图片漫画',
        list,
      );
    }
    Comic? result;
    for (final file in files) {
      final length = await file.length();
      if ((length ?? 0) > 256 * 1024 * 1024) {
        throw const FormatException('单个压缩包或 PDF 请控制在 256 MB 内。');
      }
      final bytes = await file.readAsBytes();
      if (file.extension?.toLowerCase() == 'pdf') {
        final doc = await PdfDocument.openData(bytes);
        final pages = <({String name, Uint8List bytes})>[];
        try {
          if (doc.pagesCount > 1000) {
            throw const FormatException('PDF 超过 1000 页，请分卷导入。');
          }
          for (var i = 1; i <= doc.pagesCount; i++) {
            final page = await doc.getPage(i);
            try {
              final image = await page.render(
                width: 1600,
                height: 1600 * page.height / page.width,
                format: PdfPageImageFormat.jpeg,
                quality: 92,
                backgroundColor: '#FFFFFF',
              );
              if (image != null) {
                pages.add((
                  name: '${i.toString().padLeft(4, '0')}.jpg',
                  bytes: image.bytes,
                ));
              }
            } finally {
              await page.close();
            }
          }
          result = await offline.importImages(
            file.name.replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), ''),
            pages,
          );
        } finally {
          await doc.close();
        }
      } else {
        result = await offline.importZip(file.name, bytes);
      }
    }
    return result;
  }

  static Future<Uri?> exportBackup(Library library) => FilePicker.saveFile(
    fileName:
        'manxia-backup-${DateTime.now().toIso8601String().substring(0, 10)}.json',
    bytes: Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(library.backup())),
    ),
    mimeType: 'application/json',
  );
  static Future<Map<String, dynamic>?> pickBackup() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (file == null) return null;
    if ((await file.length() ?? 0) > 10 * 1024 * 1024) {
      throw const FormatException('资料备份超过 10 MB。');
    }
    return Map<String, dynamic>.from(
      jsonDecode(utf8.decode(await file.readAsBytes())),
    );
  }

  static Future<bool> importBackup(Library library) async {
    final data = await pickBackup();
    if (data == null) return false;
    await library.restore(data, restoreOptions: true);
    return true;
  }

  static Future<Uri?> exportChapter(
    OfflineLibrary offline,
    Map<String, dynamic> entry,
  ) async => FilePicker.saveFile(
    fileName: '${entry['comic']['title']}-${entry['chapter']['title']}.cbz',
    bytes: await offline.exportChapter(entry),
    mimeType: 'application/zip',
  );
}
