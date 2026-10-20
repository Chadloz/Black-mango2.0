// General groups for a Stalker portal's movie and show categories. Portals list dozens of
// very specific ones ("DE ✨ KINO 2025 ✨ 2026", "DE ✨ NETFLIX FILME"...); the menu shows a
// short set of general groups instead, and picking one loads every category in it.

/// One menu entry: a group and the portal categories (id, title) in it.
class StalkerGroup {
  final String id;
  final String label;
  final List<(String, String)> cats;
  const StalkerGroup(this.id, this.label, this.cats);
}

/// The first entry: every title already cached for the account (no loading).
const stalkerEverythingId = 'all';
const stalkerEverythingLabel = 'Everything loaded so far';

// Matching order: the most specific idea wins ("NETFLIX HORROR" is Horror, "IMDB TOP 250" is Top rated).
final _rules = <(String, RegExp)>[
  ('top', RegExp(r'imdb|top\s*\d|best of|oscar|award', caseSensitive: false)),
  ('kids', RegExp(r'kinder|\bkids?\b|anim|zeichentrick|cartoon|famil|pixar', caseSensitive: false)),
  ('docs', RegExp(r'doku|documentar|natur', caseSensitive: false)),
  ('horror', RegExp(r'horror|thriller|krimi|crime|myster', caseSensitive: false)),
  ('scifi', RegExp(r'sci.?fi|science|fantasy|superhel|marvel', caseSensitive: false)),
  ('comedy', RegExp(r'kom(o|ö)die|comed|humor|lustig', caseSensitive: false)),
  ('action', RegExp(r'action|abenteuer|adventure|krieg|\bwar\b|western|martial', caseSensitive: false)),
  ('drama', RegExp(r'drama|roman|liebe|\blove\b', caseSensitive: false)),
  ('streaming',
      RegExp(r'netflix|prime|amazon|disney|apple|hbo|\bsky\b|paramount|hulu|peacock|starz|showtime|joyn|\bwow\b|\bmax\b',
          caseSensitive: false)),
  ('new', RegExp(r'kino|cinema|\bneu|\bnew\b|latest|aktuell|20(2[4-9]|3\d)', caseSensitive: false)),
];

// Menu order and names.
const _menu = <(String, String)>[
  ('new', 'New & in cinemas'),
  ('top', 'Top rated'),
  ('streaming', 'Netflix, Prime, Disney & co'),
  ('action', 'Action & Adventure'),
  ('comedy', 'Comedy'),
  ('horror', 'Horror & Thriller'),
  ('drama', 'Drama'),
  ('kids', 'Kids & Animation'),
  ('docs', 'Documentary'),
  ('scifi', 'Sci-Fi & Fantasy'),
  ('other', 'Other'),
];

/// Which group a portal category belongs to.
String stalkerGroupOf(String title) {
  for (final r in _rules) {
    if (r.$2.hasMatch(title)) return r.$1;
  }
  return 'other';
}

/// The groups that have at least one of [cats], in menu order.
List<StalkerGroup> stalkerGroups(List<(String, String)> cats) {
  final by = <String, List<(String, String)>>{};
  for (final c in cats) {
    by.putIfAbsent(stalkerGroupOf(c.$2), () => []).add(c);
  }
  return [
    for (final m in _menu)
      if (by[m.$1] != null) StalkerGroup(m.$1, m.$2, by[m.$1]!),
  ];
}

/// A group's name for the count line, or the "Everything" label.
String stalkerGroupLabel(String id) {
  if (id == stalkerEverythingId) return stalkerEverythingLabel;
  for (final m in _menu) {
    if (m.$1 == id) return m.$2;
  }
  return 'Other';
}
