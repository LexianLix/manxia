import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/frame_monitor.dart';
import 'localized_text.dart';
import 'content_handoff.dart';

class SmoothnessPage extends StatelessWidget {
  const SmoothnessPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const LocalizedText('流畅度检测')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListenableBuilder(
            listenable: FrameMonitor.shared,
            builder: (context, _) {
              final monitor = FrameMonitor.shared, report = monitor.report;
              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const LocalizedText(
                    '开始后返回书架或阅读器，重复滑动、开书和翻页。20 秒后自动结束，再回到这里查看结果。',
                    style: TextStyle(fontSize: 14, height: 1.7),
                  ),
                  const SizedBox(height: 12),
                  const LocalizedText(
                    '只在本机记录画面耗时，不记录漫画内容。切到后台会停止检测。',
                    style: TextStyle(fontSize: 12, height: 1.7),
                  ),
                  if (kIsWeb) ...[
                    const SizedBox(height: 12),
                    const LocalizedText('浏览器可能不提供帧耗时，请使用 Android 发行版检测。'),
                  ],
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      icon: Icon(
                        monitor.recording ? Icons.stop : Icons.play_arrow,
                      ),
                      onPressed: () {
                        if (monitor.recording) {
                          monitor.stop();
                        } else {
                          monitor.start(View.of(context).display.refreshRate);
                        }
                      },
                      label: LocalizedText(
                        monitor.recording ? '结束检测' : '开始 20 秒检测',
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ContentHandoff(
                    child: monitor.recording
                        ? const LocalizedText(
                            '正在检测，可以返回继续操作。',
                            key: ValueKey('recording'),
                          )
                        : report == null
                        ? const SizedBox.shrink(key: ValueKey('idle'))
                        : Column(
                            key: const ValueKey('report'),
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (report.samples.isEmpty)
                                const LocalizedText(
                                  '没有收到画面样本，请在 Android 发行版中操作后重试。',
                                )
                              else ...[
                                _metric('记录帧数', '${report.samples.length}'),
                                _metric(
                                  '参考刷新率',
                                  '${report.refreshRate.round()} Hz',
                                ),
                                _metric(
                                  '画面准备 P95',
                                  '${report.percentile(report.samples.map((s) => s.build)).toStringAsFixed(1)} ms',
                                ),
                                _metric(
                                  '画面绘制 P95',
                                  '${report.percentile(report.samples.map((s) => s.raster)).toStringAsFixed(1)} ms',
                                ),
                                _metric(
                                  '超过帧预算',
                                  '${report.slowFrames} / ${report.samples.length}',
                                ),
                                const SizedBox(height: 12),
                                const LocalizedText(
                                  '这些是应用准备与绘制画面的耗时，不代表屏幕实际 FPS 或发热情况。P95 表示 95% 的样本不超过该耗时。',
                                  style: TextStyle(fontSize: 12, height: 1.7),
                                ),
                              ],
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: () async {
                                  await Clipboard.setData(
                                    ClipboardData(
                                      text: const JsonEncoder.withIndent(
                                        '  ',
                                      ).convert(report.toJson()),
                                    ),
                                  );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: LocalizedText('已复制检测结果'),
                                      ),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.copy, size: 16),
                                label: const LocalizedText('复制检测结果'),
                              ),
                            ],
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
  Widget _metric(String name, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Expanded(child: LocalizedText(name)),
        Text(value),
      ],
    ),
  );
}
