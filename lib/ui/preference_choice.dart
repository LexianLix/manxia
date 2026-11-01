import 'package:flutter/material.dart';
import 'localized_text.dart';

/// Keep long translated labels out of the narrow trailing slot of a ListTile.
class PreferenceChoice<T> extends StatelessWidget {
  const PreferenceChoice({
    super.key,
    required this.title,
    required this.value,
    required this.choices,
    required this.onChanged,
  });
  final String title;
  final T value;
  final Map<T, String> choices;
  final ValueChanged<T?>? onChanged;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: LayoutBuilder(
      builder: (context, box) {
        final stacked =
            box.maxWidth < 340 ||
            (box.maxWidth < 550 &&
                MediaQuery.textScalerOf(context).scale(14) > 17);
        final label = LocalizedText(
          title,
          style: const TextStyle(fontSize: 13),
        );
        final field = DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            isExpanded: true,
            isDense: true,
            value: value,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontSize: 13),
            items: choices.entries
                .map(
                  (e) => DropdownMenuItem(
                    value: e.key,
                    child: LocalizedText(
                      e.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: onChanged,
          ),
        );
        final control = Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: field,
        );
        return stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [label, const SizedBox(height: 6), control],
              )
            : Row(
                children: [
                  Expanded(child: label),
                  const SizedBox(width: 16),
                  SizedBox(width: box.maxWidth * .48, child: control),
                ],
              );
      },
    ),
  );
}
