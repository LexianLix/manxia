import 'package:flutter/material.dart';
import '../data/backup_preview.dart';
import '../data/file_actions.dart';
import '../data/library.dart';
import '../data/metadata_backups.dart';
import 'localized_text.dart';

Future<bool> reviewBackup(
  BuildContext context,
  Library library,
  Map<String, dynamic> data,
) async {
  validateBackup(data);
  if (!context.mounted) return false;
  return await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => BackupReviewPage(library: library, data: data),
        ),
      ) ??
      false;
}

class BackupReviewPage extends StatefulWidget {
  const BackupReviewPage({
    super.key,
    required this.library,
    required this.data,
  });
  final Library library;
  final Map<String, dynamic> data;
  @override
  State<BackupReviewPage> createState() => _BackupReviewState();
}

class _BackupReviewState extends State<BackupReviewPage> {
  bool local = false, deletions = false, options = true, busy = false;
  String? error;
  Future<void> apply() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final snapshots = await MetadataBackups.open(widget.library);
      await snapshots.capture(force: true, reason: '恢复前备份');
      final plan = BackupPreview(widget.library.backup(), widget.data);
      await widget.library.restore(
        plan.mergeInput(keepLocal: local, applyDeletions: deletions),
        restoreOptions: options,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const LocalizedText('恢复预览')),
    body: ListenableBuilder(
      listenable: widget.library,
      builder: (context, _) {
        final plan = BackupPreview(widget.library.backup(), widget.data);
        return Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  LocalizedText(
                    '新增收藏 {books} · 进度变化 {progress} · 冲突 {conflicts}',
                    arguments: {
                      'books': plan.newBooks,
                      'progress': plan.progressChanges.length,
                      'conflicts': plan.conflicts,
                    },
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const LocalizedText('确认前不会修改资料。恢复前会保存一份本机资料备份；离线图片不在此资料备份中。'),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const LocalizedText('冲突时保留本机资料'),
                    subtitle: const LocalizedText('关闭时按记录时间合并；书签相同标识使用备份内容'),
                    value: local,
                    onChanged: busy ? null : (v) => setState(() => local = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const LocalizedText('应用备份中的删除记录'),
                    subtitle: const LocalizedText('可能移除已删除过的收藏、足迹或书签；默认关闭'),
                    value: deletions,
                    onChanged: busy
                        ? null
                        : (v) => setState(() => deletions = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const LocalizedText('恢复应用偏好'),
                    value: options,
                    onChanged: busy ? null : (v) => setState(() => options = v),
                  ),
                  const Divider(),
                  const LocalizedText('进度变化明细', style: TextStyle(fontSize: 18)),
                  for (final record in plan.progressChanges.take(100))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(record['comic']['title']),
                      subtitle: LocalizedText(
                        '{chapter} · 第 {page} 页',
                        arguments: {
                          'chapter': record['chapterTitle'],
                          'page': (record['page'] as int) + 1,
                        },
                      ),
                    ),
                  if (plan.progressChanges.length > 100)
                    const LocalizedText('仅预览前 100 条，合并仍包含全部记录'),
                  if (error != null) Text(error!),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: busy ? null : apply,
                  icon: const Icon(Icons.restore),
                  label: LocalizedText(busy ? '正在恢复…' : '确认合并资料'),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class MetadataBackupsPage extends StatefulWidget {
  const MetadataBackupsPage({super.key, required this.library});
  final Library library;
  @override
  State<MetadataBackupsPage> createState() => _MetadataBackupsState();
}

class _MetadataBackupsState extends State<MetadataBackupsPage> {
  late final service = MetadataBackups.open(widget.library);
  String? error;
  bool busy = false;
  Future<void> run(Future<void> Function() task) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await task();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const LocalizedText('自动资料备份')),
    body: FutureBuilder<MetadataBackups>(
      future: service,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: LocalizedText('自动备份暂不可用，请稍后重试'));
        }
        final backups = snapshot.data;
        if (backups == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListenableBuilder(
          listenable: Listenable.merge([backups, widget.library]),
          builder: (context, _) => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const LocalizedText(
                '备份保存在本机应用目录，不含正文图片和 WebDAV 密码。卸载应用可能一并清除，请另行导出重要资料。',
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const LocalizedText('定期保存资料'),
                value: backups.enabled,
                onChanged: (v) =>
                    widget.library.setOption('autoBackupEnabled', v),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const LocalizedText('备份间隔'),
                trailing: DropdownButton<int>(
                  value: backups.interval,
                  items: {1, 24, 168, backups.interval}
                      .map(
                        (v) => DropdownMenuItem(
                          value: v,
                          child: LocalizedText(
                            '{hours} 小时',
                            arguments: {'hours': v},
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) =>
                      widget.library.setOption('autoBackupHours', v),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const LocalizedText('保留份数'),
                trailing: DropdownButton<int>(
                  value: widget.library
                      .option<int>('autoBackupKeep', 5)
                      .clamp(3, 10),
                  items: [
                    for (var i = 3; i <= 10; i++)
                      DropdownMenuItem(value: i, child: Text('$i')),
                  ],
                  onChanged: (v) =>
                      widget.library.setOption('autoBackupKeep', v),
                ),
              ),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.tonal(
                    onPressed: busy
                        ? null
                        : () => run(
                            () => backups.capture(force: true, reason: '手动快照'),
                          ),
                    child: const LocalizedText('立即保存快照'),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => run(() async {
                            final data = await FileActions.pickBackup();
                            if (data != null && context.mounted) {
                              await reviewBackup(context, widget.library, data);
                            }
                          }),
                    child: const LocalizedText('导入资料并预览'),
                  ),
                ],
              ),
              if ((error ?? backups.error) != null)
                Text(error ?? backups.error!),
              const Divider(),
              if (backups.entries.isEmpty)
                const LocalizedText('资料发生变化后会按间隔保存，空书库不会生成快照。'),
              for (final entry in backups.entries)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    MaterialLocalizations.of(context).formatFullDate(
                      DateTime.fromMillisecondsSinceEpoch(entry['at']),
                    ),
                  ),
                  subtitle: LocalizedText(
                    '{reason} · {size} KB',
                    arguments: {
                      'reason': translate(
                        entry['reason'] ?? '自动备份',
                        Localizations.localeOf(context),
                      ),
                      'size': ((entry['bytes'] as int) / 1024).toStringAsFixed(
                        1,
                      ),
                    },
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: busy
                      ? null
                      : () => run(() async {
                          final data = await backups.read(entry);
                          if (context.mounted) {
                            await reviewBackup(context, widget.library, data);
                          }
                        }),
                ),
            ],
          ),
        );
      },
    ),
  );
}
