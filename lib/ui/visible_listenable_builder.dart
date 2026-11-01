import 'package:flutter/material.dart';

/// Pause subscriptions behind another route or a retained, hidden tab. On
/// return, dependency changes rebuild once from the latest data.
class VisibleListenableBuilder extends StatefulWidget {
  const VisibleListenableBuilder({
    super.key,
    required this.listenable,
    required this.builder,
    this.child,
  });
  final Listenable listenable;
  final TransitionBuilder builder;
  final Widget? child;
  @override
  State<VisibleListenableBuilder> createState() => _VisibleListenableState();
}

class _VisibleListenableState extends State<VisibleListenableBuilder> {
  bool listening = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    if (listening == enabled) return;
    listening = enabled;
    if (enabled) {
      widget.listenable.addListener(changed);
    } else {
      widget.listenable.removeListener(changed);
    }
  }

  @override
  void didUpdateWidget(VisibleListenableBuilder old) {
    super.didUpdateWidget(old);
    if (listening && old.listenable != widget.listenable) {
      old.listenable.removeListener(changed);
      widget.listenable.addListener(changed);
    }
  }

  void changed() {
    if (mounted && listening) setState(() {});
  }

  @override
  void dispose() {
    if (listening) widget.listenable.removeListener(changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, widget.child);
}
