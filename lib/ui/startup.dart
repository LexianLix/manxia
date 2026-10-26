import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/library.dart';
import '../data/offline_library.dart';
import '../data/source_hub.dart';
import '../data/plugin.dart';
import '../platform/storage.dart';
import 'content_handoff.dart';

typedef StartupProgress = void Function(String stage);
typedef StartupLoader = Future<Library> Function(StartupProgress report);

Future<Library> initializeLibrary(StartupProgress report) async {
  const limit = Duration(seconds: 15);
  report('正在读取本地设置');
  final prefs = await SharedPreferences.getInstance().timeout(limit);
  final library = Library(prefs);
  report('正在整理书架');
  await library.load().timeout(limit);
  report('正在打开离线书库');
  // Resolve native storage before constructing OfflineLibrary. A timed-out
  // plugin call cannot later replace the active offline callbacks on retry.
  final store = await createBlobStore().timeout(limit);
  await OfflineLibrary(
    library,
    SourceHub(library, gateway: kIsWeb ? Uri.base : null),
    store: store,
  ).initialize();
  return library;
}

/// Paint a first frame before touching plugins; never hide startup failures
/// behind Android's launch surface or silently replace the user's saved data.
class ManxiaStartup extends StatefulWidget {
  const ManxiaStartup({
    super.key,
    required this.builder,
    this.load = initializeLibrary,
  });
  final Widget Function(Library library) builder;
  final StartupLoader load;

  @override
  State<ManxiaStartup> createState() => _ManxiaStartupState();
}

class _ManxiaStartupState extends State<ManxiaStartup> {
  Library? _library;
  String _stage = '正在打开漫匣';
  String? _diagnostics;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (!mounted || _loading) return;
    setState(() {
      _loading = true;
      _diagnostics = null;
      _stage = '正在打开漫匣';
    });
    try {
      final library = await widget.load((stage) {
        if (mounted) setState(() => _stage = stage);
      });
      if (mounted) setState(() => _library = library);
    } catch (error, stack) {
      final details = 'Manxia startup\n$_stage\n$error\n$stack';
      debugPrint(details);
      if (mounted) setState(() => _diagnostics = details);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => MediaQuery.fromView(
    view: View.of(context),
    child: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations:
              MediaQuery.disableAnimationsOf(context) ||
              _library?.motion == false,
        ),
        child: ColoredBox(
          color: handoffColor(),
          child: ContentHandoff(
            fill: true,
            child: _library != null
                ? KeyedSubtree(
                    key: const ValueKey('startup-ready'),
                    child: widget.builder(_library!),
                  )
                : KeyedSubtree(
                    key: const ValueKey('startup-waiting'),
                    child: startupSurface(),
                  ),
          ),
        ),
      ),
    ),
  );

  Color handoffColor() {
    final library = _library;
    final dark = library?.dark == true;
    final surface = library == null
        ? null
        : PluginSnapshot(library.options).theme[dark
              ? 'darkSurface'
              : 'lightSurface'];
    return surface is String
        ? Color(0xff000000 | int.parse(surface.substring(1), radix: 16))
        : dark
        ? const Color(0xff171d1a)
        : const Color(0xfff7f7f2);
  }

  Widget startupSurface() {
    final failed = _diagnostics != null;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff47775e)),
        scaffoldBackgroundColor: const Color(0xfff7f7f2),
        fontFamily: 'ArchiveSerif',
      ),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.auto_stories_outlined,
                      color: Color(0xff47775e),
                      size: 48,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      failed ? '启动未完成' : '漫匣',
                      style: const TextStyle(fontSize: 26),
                    ),
                    const SizedBox(height: 16),
                    Text(_stage, textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    if (!failed)
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else ...[
                      const Text(
                        '本地初始化遇到问题。请重试；若仍无法打开，可复制诊断信息反馈。',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _start,
                        child: const Text('重试启动'),
                      ),
                      const SizedBox(height: 8),
                      Builder(
                        builder: (context) => TextButton(
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: _diagnostics!),
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('诊断信息已复制')),
                              );
                            }
                          },
                          child: const Text('复制诊断信息'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
