/// Normalizes channel names so the same channel matches across providers.
/// "US: CNN HD", "USA | CNN", and "CNN (FHD)" all become "cnn".
/// Words that make it a different channel (east, west, 2...) are kept.

final _prefixRe = RegExp(r'^\s*[\[\(]?[a-z]{2,5}(-[a-z]{2})?[\]\)]?\s*[|:\-]\s*', caseSensitive: false);
final _tagRe = RegExp(
  r'\b(uhd|fhd|hd|sd|4k|8k|hevc|h\.?265|h\.?264|hq|lq|vip|backup|repuesto\d*|raw|50fps|60fps|1080p|720p|multi|local)\b',
  caseSensitive: false,
);

String normName(String name) {
  var s = name.toLowerCase();
  for (var i = 0; i < 3; i++) {
    final n = s.replaceFirst(_prefixRe, '');
    if (n == s) break;
    s = n;
  }
  s = s.replaceAll(RegExp(r'[\[\]\(\)\{\}]'), ' ');
  s = s.replaceAll(_tagRe, ' ');
  s = s.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
  return s.trim().replaceAll(RegExp(r'\s+'), ' ');
}
