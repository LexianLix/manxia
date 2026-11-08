import 'comic.dart';
import 'library_features.dart';

extension PersonalReviews on LibraryFeatures {
  List<Comic> get reviewedComics {
    final books = <Comic>[];
    for (final meta in metadata.values) {
      try {
        final value = meta['personalReview'];
        if (value is! Map || value['comic'] is! Map) continue;
        final comic = Comic.fromJson(Map<String, dynamic>.from(value['comic']));
        if (rating(comic) != null || reviewText(comic).isNotEmpty) {
          books.add(comic);
        }
      } catch (_) {
        /* Ignore malformed optional notes in imported metadata. */
      }
    }
    books.sort(
      (a, b) => ((review(b)['updatedAt'] as num?)?.toInt() ?? 0).compareTo(
        (review(a)['updatedAt'] as num?)?.toInt() ?? 0,
      ),
    );
    return books;
  }

  Map<String, dynamic> review(Comic comic) {
    final value = meta(comic)['personalReview'];
    return value is Map ? Map<String, dynamic>.from(value) : {};
  }

  int? rating(Comic comic) {
    final value = review(comic)['rating'];
    return value is int && value >= 1 && value <= 5 ? value : null;
  }

  String reviewText(Comic comic) =>
      review(comic)['text'] is String ? review(comic)['text'] as String : '';
  Future<void> setReview(Comic comic, int? stars, String text) {
    if (stars != null && (stars < 1 || stars > 5)) {
      throw ArgumentError('rating');
    }
    if (text.length > 500) throw ArgumentError('review length');
    return setMeta(comic, {
      'personalReview': {
        'rating': stars,
        'text': text.trim(),
        'comic': comic.toJson(),
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
    });
  }
}
