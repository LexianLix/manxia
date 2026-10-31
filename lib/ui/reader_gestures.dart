enum ReaderTap { previous, controls, next }

double tapAreaWidth(Map<String, dynamic> options, String key) {
  final value = options[key];
  return value is num && value.isFinite ? value.toDouble().clamp(.12, .4) : .24;
}

ReaderTap readerTap(double fraction, Map<String, dynamic> options, bool rtl) {
  double width(String key) => tapAreaWidth(options, key);
  final left = fraction < width('leftTapWidth');
  final right = fraction > 1 - width('rightTapWidth');
  if (!left && !right) return ReaderTap.controls;
  final leftNext = switch (options['hand']) {
    'left' => true,
    'right' => false,
    _ => rtl,
  };
  return (left ? leftNext : !leftNext) ? ReaderTap.next : ReaderTap.previous;
}
