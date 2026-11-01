const characterStates = ['idle', 'blink', 'happy', 'puzzled'];

class CharacterFrame {
  CharacterFrame(this.file, this.sha256) {
    if (!RegExp(r'^[a-z][a-z0-9_-]{0,30}\.png$').hasMatch(file) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256)) {
      throw const FormatException('角色图片名称或 SHA-256 无效');
    }
  }
  final String file, sha256;
}

/// Fixed expression slots, not an executable animation or script runtime.
class CharacterDefinition {
  CharacterDefinition(Map<String, dynamic> raw) {
    if (raw.keys.any((k) => k != 'states') || raw['states'] is! Map) {
      throw const FormatException('角色包定义无效');
    }
    final entries = Map<String, dynamic>.from(raw['states']);
    if (!entries.containsKey('idle') ||
        entries.keys.any((s) => !characterStates.contains(s))) {
      throw const FormatException('角色包需提供 idle 表情，且只接受四种宿主表情');
    }
    for (final e in entries.entries) {
      final frame = Map<String, dynamic>.from(e.value);
      if (frame.keys.any((k) => !['file', 'sha256'].contains(k))) {
        throw const FormatException('角色图片字段无效');
      }
      frames[e.key] = CharacterFrame(
        frame['file'] as String,
        frame['sha256'] as String,
      );
    }
    final files = <String, String>{};
    for (final f in frames.values) {
      if (files[f.file] != null && files[f.file] != f.sha256) {
        throw const FormatException('同名角色图片内容冲突');
      }
      files[f.file] = f.sha256;
    }
  }
  final Map<String, CharacterFrame> frames = {};
  CharacterFrame frame(String state) => frames[state] ?? frames['idle']!;
}
