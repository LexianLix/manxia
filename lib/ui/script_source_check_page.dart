import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../data/script_source.dart';
import '../data/script_source_policy.dart';
import '../data/source_profile.dart';
import '../platform/script_source_http.dart';
import 'localized_text.dart';

class ScriptSourceCheckPage extends StatefulWidget {
  const ScriptSourceCheckPage({super.key, required this.source});
  final SourceProfile source;

  @override
  State<ScriptSourceCheckPage> createState() => _ScriptSourceCheckPageState();
}

class _ScriptSourceCheckPageState extends State<ScriptSourceCheckPage> {
  final query = TextEditingController();
  ScriptSourceRuntime? runtime;
  int passed = 0;
  String? error, book, chapter;
  String? errorCategory;
  Uint8List? preview;

  Future<void> run() async {
    if (runtime != null || query.text.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    final probe = ScriptSourceRuntime();
    setState(() {
      runtime = probe;
      passed = 0;
      error = book = chapter = null;
      errorCategory = null;
      preview = null;
    });
    final source = widget.source;
    bool current() => mounted && identical(runtime, probe);
    var loadingImage = false;
    try {
      final books = await probe.catalog(source, query: query.text.trim());
      if (!current()) return;
      if (books.isEmpty) {
        throw ScriptSourceFailure(ScriptFailureKind.empty, '搜索未找到作品');
      }
      setState(() {
        passed = 1;
        book = books.first.title;
      });
      final detail = await probe.detail(source, books.first);
      if (!current()) return;
      final first = detail.chapters.first;
      setState(() {
        passed = 2;
        chapter = first.title;
      });
      final pages = await probe.pages(source, first.path);
      if (!current()) return;
      loadingImage = true;
      final bytes = await fetchScriptResource(
        decodeScriptImage(pages.first),
        maxBytes: 20 * 1024 * 1024,
        image: true,
        abort: probe.closed,
      );
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 360);
      try {
        (await codec.getNextFrame()).image.dispose();
      } finally {
        codec.dispose();
      }
      if (current()) {
        setState(() {
          passed = 3;
          preview = bytes;
        });
      }
    } catch (failure) {
      if (current()) {
        setState(() {
          error = failure.toString();
          errorCategory = switch (failure) {
            ScriptSourceFailure(kind: ScriptFailureKind.permission) => '域名权限失败',
            ScriptSourceFailure(kind: ScriptFailureKind.request) => '网络请求失败',
            ScriptSourceFailure(kind: ScriptFailureKind.execution) => '脚本执行失败',
            ScriptSourceFailure(kind: ScriptFailureKind.empty) => '未找到内容',
            _ => loadingImage ? '图片加载失败' : '结果解析失败',
          };
        });
      }
    } finally {
      probe.close();
      if (current()) setState(() => runtime = null);
    }
  }

  void stop() {
    runtime?.close();
    setState(() => runtime = null);
  }

  @override
  void dispose() {
    runtime?.close();
    query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const LocalizedText('试跑脚本源')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                widget.source.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const LocalizedText('搜索后试读首个结果的第一章，并实际解码第一张图片。'),
              const SizedBox(height: 16),
              TextField(
                controller: query,
                enabled: runtime == null,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => run(),
                decoration: const InputDecoration(
                  label: LocalizedText('测试关键词'),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: runtime == null ? run : stop,
                  icon: Icon(runtime == null ? Icons.play_arrow : Icons.stop),
                  label: LocalizedText(runtime == null ? '开始试跑' : '停止试跑'),
                ),
              ),
              const Divider(height: 32),
              for (final (index, label, info) in [
                (0, '搜索作品', book),
                (1, '读取目录', chapter),
                (2, '加载首图', null),
              ])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: LocalizedText(label),
                  leading: Icon(
                    passed > index
                        ? Icons.check_circle_outline
                        : passed == index && error != null
                        ? Icons.error_outline
                        : Icons.circle_outlined,
                  ),
                  subtitle: passed == index && error != null
                      ? LocalizedText(
                          '{category} · {message}',
                          arguments: {
                            'category': translate(
                              errorCategory!,
                              Localizations.localeOf(context),
                            ),
                            'message': error!,
                          },
                        )
                      : info == null
                      ? null
                      : Text(info),
                  trailing: runtime != null && passed == index
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                ),
              if (preview != null) ...[
                const LocalizedText('首图已解码'),
                const SizedBox(height: 8),
                SizedBox(
                  height: 220,
                  child: Image.memory(
                    preview!,
                    cacheWidth: 360,
                    fit: BoxFit.contain,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
