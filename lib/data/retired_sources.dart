/// These bundled packages were withdrawn after device connectivity reports.
/// Book identities and offline files remain intact so readers can switch source.
const retiredSourcePlugins = {
  'manxia.source-kanman',
  'manxia.source-manhuagui',
  'manxia.source-peppercarrot',
};
const retiredSourceIds = {'kanman', 'manhuagui', 'peppercarrot'};

bool retireSourcePlugins(Map<String, dynamic> options) {
  var changed = false;
  final raw = options['plugins.installed'];
  if (raw is List) {
    final retained = raw
        .where(
          (entry) =>
              entry is! Map ||
              entry['manifest'] is! Map ||
              !retiredSourcePlugins.contains(entry['manifest']['id']),
        )
        .toList();
    if (retained.length != raw.length) {
      options['plugins.installed'] = retained;
      changed = true;
    }
  }
  if (retiredSourceIds.contains(options['source'])) {
    options['source'] = 'mangabz';
    changed = true;
  }
  return changed;
}
