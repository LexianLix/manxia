import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoSlidingSegmentedControl;
import 'localized_text.dart';
import 'materials.dart';

/// Content stays quiet and solid; glass belongs to the floating control layer.
class RoomPageHeading extends StatelessWidget {
  const RoomPageHeading({
    super.key,
    required this.title,
    this.actions = const [],
  });
  final String title;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: LocalizedText(
            title,
            style: Theme.of(context).textTheme.headlineLarge,
          ),
        ),
        ...actions,
      ],
    ),
  );
}

class RoomGroupedSection extends StatelessWidget {
  const RoomGroupedSection({
    super.key,
    required this.children,
    this.dividerIndent = 62,
  });
  final List<Widget> children;
  final double dividerIndent;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Material(
        color: scheme.surfaceContainerLowest.withValues(alpha: .38),
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  thickness: .5,
                  indent: dividerIndent,
                  endIndent: 16,
                ),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

class RoomGlassBar extends StatelessWidget implements PreferredSizeWidget {
  const RoomGlassBar({
    super.key,
    required this.title,
    this.actions,
    this.large = false,
    this.automaticallyImplyLeading = true,
  });
  final String title;
  final List<Widget>? actions;
  final bool large, automaticallyImplyLeading;
  @override
  Size get preferredSize => Size.fromHeight(large ? 72 : 54);
  @override
  Widget build(BuildContext context) => AppBar(
    automaticallyImplyLeading: automaticallyImplyLeading,
    centerTitle: !large,
    toolbarHeight: preferredSize.height,
    titleSpacing: large ? 22 : null,
    title: LocalizedText(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: large ? Theme.of(context).textTheme.headlineMedium : null,
    ),
    actions: actions,
    flexibleSpace: large
        ? null
        : const MilkGlass(
            radius: 0,
            role: GlassRole.chrome,
            child: SizedBox.expand(),
          ),
  );
}

class RoomTabs<T extends Object> extends StatelessWidget {
  const RoomTabs({
    super.key,
    required this.value,
    required this.labels,
    required this.onChanged,
  });
  final T value;
  final Map<T, String> labels;
  final ValueChanged<T> onChanged;
  @override
  Widget build(BuildContext context) => CupertinoSlidingSegmentedControl<T>(
    key: MediaQuery.disableAnimationsOf(context) ? ValueKey(value) : null,
    groupValue: value,
    onValueChanged: (next) {
      if (next != null) onChanged(next);
    },
    backgroundColor: Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: .055),
    thumbColor: Theme.of(context).brightness == Brightness.dark
        ? Theme.of(context).colorScheme.surfaceContainerHigh
        : Theme.of(context).colorScheme.surfaceContainerLowest,
    padding: const EdgeInsets.all(4),
    children: {
      for (final entry in labels.entries)
        entry.key: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          child: LocalizedText(
            entry.value,
            maxLines: 1,
            style: TextStyle(
              fontSize: 13,
              fontWeight: value == entry.key
                  ? FontWeight.w600
                  : FontWeight.w400,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
    },
  );
}
