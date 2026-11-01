/// Portable appearance and gesture preferences. Network queues and device
/// permissions are intentionally outside a reading-profile preview.
class ReadingProfile {
  ReadingProfile({
    required this.id,
    required this.name,
    this.builtin = false,
    required Map<String, dynamic> values,
  }) : values = Map.unmodifiable(clean(values, strict: true)) {
    if (!RegExp(r'^[a-z0-9_-]{1,64}$').hasMatch(id) ||
        name.trim().isEmpty ||
        name.length > 32 ||
        this.values.isEmpty) {
      throw const FormatException('阅读方案名称或内容无效');
    }
  }
  factory ReadingProfile.fromJson(Map<String, dynamic> data) => ReadingProfile(
    id: data['id'] as String,
    name: data['name'] as String,
    builtin: data['builtin'] == true,
    values: Map<String, dynamic>.from(data['options'] as Map),
  );
  final String id, name;
  final bool builtin;
  final Map<String, dynamic> values;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'options': values,
    if (builtin) 'builtin': true,
  };

  static const choices = <String, List<Object>>{
    'mode': ['page', 'vertical', 'strip'],
    'background': ['theme', 'ink', 'paper', 'sepia'],
    'turn': ['slide', 'paper'],
    'hand': ['auto', 'left', 'right'],
    'toolbarDock': ['top', 'bottom'],
    'chromeTimeout': [0, 3, 5, 8],
  };
  static const toggles = {
    'rtl',
    'doublePage',
    'autoCrop',
    'tapZones',
    'doubleTapZoom',
    'continuousStrip',
  };
  static const ranges = <String, (double, double)>{
    'brightness': (.15, 1),
    'warmth': (0, 1),
    'crop': (0, .15),
    'leftTapWidth': (.12, .4),
    'rightTapWidth': (.12, .4),
  };
  static Map<String, dynamic> clean(
    Map<String, dynamic> input, {
    bool strict = false,
  }) {
    final result = <String, dynamic>{};
    for (final e in input.entries) {
      final known =
          choices.containsKey(e.key) ||
          toggles.contains(e.key) ||
          ranges.containsKey(e.key);
      if (!known && !strict) continue;
      final bounds = ranges[e.key];
      final valid = choices.containsKey(e.key)
          ? choices[e.key]!.contains(e.value)
          : toggles.contains(e.key)
          ? e.value is bool
          : bounds != null &&
                e.value is num &&
                (e.value as num).isFinite &&
                e.value >= bounds.$1 &&
                e.value <= bounds.$2;
      if (!valid) throw FormatException('阅读方案字段 ${e.key} 无效');
      result[e.key] = e.value;
    }
    return result;
  }

  static List<ReadingProfile> get templates => [
    ReadingProfile(
      id: 'night',
      builtin: true,
      name: '夜间',
      values: {
        'background': 'ink',
        'brightness': .75,
        'warmth': .18,
        'toolbarDock': 'bottom',
        'chromeTimeout': 3,
      },
    ),
    ReadingProfile(
      id: 'commute',
      builtin: true,
      name: '通勤',
      values: {
        'mode': 'page',
        'doublePage': false,
        'hand': 'right',
        'toolbarDock': 'bottom',
        'chromeTimeout': 3,
      },
    ),
    ReadingProfile(
      id: 'long_strip',
      builtin: true,
      name: '条漫',
      values: {
        'mode': 'strip',
        'doublePage': false,
        'background': 'theme',
        'chromeTimeout': 5,
      },
    ),
  ];
  static List<ReadingProfile> fromOptions(Map<String, dynamic> options) {
    final raw = options['reader.profiles'];
    if (raw == null) return templates;
    if (raw is! List) return [];
    final profiles = <ReadingProfile>[];
    for (final item in raw.take(20)) {
      try {
        final p = ReadingProfile.fromJson(Map<String, dynamic>.from(item));
        if (!profiles.any((e) => e.id == p.id)) profiles.add(p);
      } catch (_) {
        /* Invalid restored profiles never affect startup. */
      }
    }
    return profiles;
  }

  static Map<String, dynamic> defaults(Map<String, dynamic> options) =>
      fromOptions(options)
          .where((p) => p.id == options['reader.profileDefault'])
          .firstOrNull
          ?.values ??
      {};
}
