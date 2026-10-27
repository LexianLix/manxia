import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/settings_checks.dart';
import '../platform/app_update.dart';
import 'localized_text.dart';
import 'content_handoff.dart';
import 'release_notes.dart';

class AppUpdatePage extends StatefulWidget {
  const AppUpdatePage({super.key, required this.release});
  final UpdateRelease release;
  @override
  State<AppUpdatePage> createState() => _AppUpdatePageState();
}

class _AppUpdatePageState extends State<AppUpdatePage> {
  CheckControl? control;
  String? path;
  String message = '下载后校验安装包，再交给系统覆盖安装。收藏和阅读记录会保留。';
  double progress = 0;
  bool installing = false;
  Future<void> download() async {
    if (control != null || installing) return;
    final next = CheckControl();
    setState(() {
      control = next;
      progress = 0;
      message = '正在读取发行清单…';
    });
    final watch = Stopwatch()..start();
    int last = 0;
    try {
      final file = await AppUpdateDownload.download(widget.release, next, (
        received,
        total,
      ) {
        if (!mounted || next.cancelled) return;
        if (watch.elapsedMilliseconds - last < 100 && received != total) return;
        last = watch.elapsedMilliseconds;
        setState(() {
          progress = received / total;
          message = received == total ? '正在校验安装包…' : '正在下载更新…';
        });
      });
      next.ensureActive();
      if (mounted) {
        setState(() {
          path = file;
          message = '安装包已通过 SHA-256 校验，可以安装更新。';
        });
      }
    } on CheckCancelled {
      if (mounted) setState(() => message = '下载已取消，可重新开始。');
    } catch (e) {
      if (mounted) {
        setState(
          () => message = e is FormatException
              ? e.message
              : '下载失败，请检查网络后重试，或打开发行页下载。',
        );
      }
    } finally {
      if (mounted) setState(() => control = null);
    }
  }

  Future<void> install() async {
    if (path == null || installing) return;
    setState(() => installing = true);
    try {
      final state = await AppUpdateDownload.install(path!);
      if (mounted) {
        setState(
          () => message = state == 'permission'
              ? '请允许漫匣安装应用，返回后点击“安装更新”。'
              : '已打开系统安装器；若取消安装，可再次点击“安装更新”。',
        );
      }
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() => message = e.message ?? '无法打开系统安装器，请到发行页下载后覆盖安装。');
      }
    } catch (_) {
      if (mounted) setState(() => message = '无法打开系统安装器，请到发行页下载后覆盖安装。');
    } finally {
      if (mounted) setState(() => installing = false);
    }
  }

  @override
  void dispose() {
    control?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const LocalizedText('在线更新')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(widget.release.tag, style: const TextStyle(fontSize: 28)),
              const SizedBox(height: 20),
              ReleaseNotes(
                widget.release.body.isEmpty
                    ? translate(
                        '更新说明请在 GitHub 发行页查看。',
                        Localizations.localeOf(context),
                      )
                    : widget.release.body,
              ),
              const Divider(height: 40),
              ContentHandoff(
                child: LocalizedText(
                  message,
                  key: ValueKey(message),
                  style: const TextStyle(fontSize: 12, height: 1.8),
                ),
              ),
              if (control != null) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(value: progress > 0 ? progress : null),
                const SizedBox(height: 8),
                Text(
                  '${(progress * 100).round()}%',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
              const SizedBox(height: 20),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (AppUpdateDownload.supported)
                    FilledButton.icon(
                      onPressed: installing
                          ? null
                          : control != null
                          ? control!.cancel
                          : path != null
                          ? install
                          : download,
                      icon: Icon(
                        control != null
                            ? Icons.close
                            : path != null
                            ? Icons.system_update
                            : Icons.download_outlined,
                        size: 18,
                      ),
                      label: LocalizedText(
                        control != null
                            ? '取消下载'
                            : path != null
                            ? '安装更新'
                            : '下载更新',
                      ),
                    ),
                  OutlinedButton(
                    onPressed: () async {
                      try {
                        if (!await launchUrl(
                          widget.release.uri,
                          mode: LaunchMode.externalApplication,
                        )) {
                          throw StateError('browser');
                        }
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: LocalizedText('未能打开浏览器，可以复制发行链接后自行打开。'),
                            ),
                          );
                        }
                      }
                    },
                    child: const LocalizedText('打开发行页'),
                  ),
                  TextButton(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: widget.release.uri.toString()),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: LocalizedText('发行链接已复制')),
                        );
                      }
                    },
                    child: const LocalizedText('复制链接'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
