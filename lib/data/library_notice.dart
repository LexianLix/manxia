enum LibraryNoticeKind { favoriteAdded, updatesFound }

/// Transient host events. They are never serialized into backups or history.
class LibraryNotice {
  LibraryNotice(this.kind, {this.title = '', DateTime? at})
    : at = at ?? DateTime.now();
  final LibraryNoticeKind kind;
  final String title;
  final DateTime at;
}
