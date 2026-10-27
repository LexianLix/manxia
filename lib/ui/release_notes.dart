import 'package:flutter/material.dart';

/// Release notes are text from GitHub. Render their simple headings and lists
/// without executing HTML or importing another Markdown rendering stack.
class ReleaseNotes extends StatelessWidget {
  const ReleaseNotes(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final line in text.split('\n'))
        if (line.trim().isEmpty)
          const SizedBox(height: 8)
        else if (RegExp(r'^#{1,6}\s+').hasMatch(line))
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 6),
            child: Text(
              line.replaceFirst(RegExp(r'^#{1,6}\s+'), ''),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                height: 1.6,
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Text(
              line.replaceFirst(RegExp(r'^[-*]\s+'), '• '),
              style: const TextStyle(fontSize: 13, height: 1.8),
            ),
          ),
    ],
  );
}
