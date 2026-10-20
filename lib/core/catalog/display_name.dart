import '../accounts/account_parser.dart' show plainText;

/// A provider's raw title or channel name, split into a clean name and small tags:
///   "Batman & Robin (1997)  DE 4K HDR" -> "Batman & Robin (1997)"  + DE, 4K, HDR
///   "US| HBO COMEDY HD ◉"             -> "HBO COMEDY"             + US, HD
///   "PRIME| HBO ZONE ᴿᴬᵂ"             -> "HBO ZONE"               + PRIME, RAW
/// Capitalization stays as the provider wrote it. Search and sorting still use the raw name.
class DisplayName {
  final String title;
  final List<String> tags;
  const DisplayName(this.title, this.tags);
}

const _quality = {
  '4K', '8K', 'UHD', 'HDR', 'HDR10', 'HDR10+', 'DV', 'FHD', 'HD', 'SD', 'HQ', 'LQ', 'HEVC', 'H265', 'H.265',
  '1080P', '720P', '2160P', '50FPS', '60FPS', 'RAW', '3D', 'ATMOS',
};
const _language = {
  'MULTI', 'DE', 'EN', 'FR', 'ES', 'IT', 'NL', 'PT', 'TR', 'AR', 'PL', 'RU', 'GER', 'ENG', 'FRA', 'SPA', 'ITA',
  'US', 'USA', 'UK', 'CA', 'AU', 'IN', 'PK', 'BR', 'MX', 'SE', 'NO', 'DK', 'FI', 'GR', 'RO', 'HU', 'CZ', 'SK',
  'AL', 'EX-YU', 'LAT', 'LATINO', 'DUB', 'SUB', 'VOSTFR',
};

bool _isTag(String t) {
  final u = t.toUpperCase();
  if (!_quality.contains(u) && !_language.contains(u)) return false;
  // Codes count only in capitals ("IT" yes, the film "It" no); "1080p" style is fine either way.
  return t == u || RegExp(r'\d').hasMatch(t);
}

// Small capitals and superscript letters (ᴿᴬᵂ, ʜᴅ) back to plain capitals.
const _small = {
  'ᴬ': 'A', 'ᴮ': 'B', 'ᴰ': 'D', 'ᴱ': 'E', 'ᴳ': 'G', 'ᴴ': 'H', 'ᴵ': 'I', 'ᴶ': 'J', 'ᴷ': 'K', 'ᴸ': 'L', 'ᴹ': 'M',
  'ᴺ': 'N', 'ᴼ': 'O', 'ᴾ': 'P', 'ᴿ': 'R', 'ᵀ': 'T', 'ᵁ': 'U', 'ⱽ': 'V', 'ᵂ': 'W',
  'ᴀ': 'A', 'ʙ': 'B', 'ᴄ': 'C', 'ᴅ': 'D', 'ᴇ': 'E', 'ꜰ': 'F', 'ɢ': 'G', 'ʜ': 'H', 'ɪ': 'I', 'ᴊ': 'J', 'ᴋ': 'K',
  'ʟ': 'L', 'ᴍ': 'M', 'ɴ': 'N', 'ᴏ': 'O', 'ᴘ': 'P', 'ʀ': 'R', 'ꜱ': 'S', 'ᴛ': 'T', 'ᴜ': 'U', 'ᴠ': 'V', 'ᴡ': 'W',
  'ʏ': 'Y', 'ᴢ': 'Z',
};

String _smallCaps(String s) {
  if (!s.runes.any((r) => r >= 0x0250)) return s; // plain text: nothing to do
  final b = StringBuffer();
  var inRun = false;
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    final mapped = _small[ch];
    if (mapped != null && !inRun && b.isNotEmpty && !b.toString().endsWith(' ')) {
      b.write(' '); // a run that touches the word before it ("ZONEᴿᴬᵂ") becomes its own word
    }
    inRun = mapped != null;
    b.write(mapped ?? ch);
  }
  return b.toString();
}

final _prefixRe = RegExp(r'^\s*[\[(|]?\s*([\p{L}\p{N}+]{2,8}(?:-[\p{L}\p{N}]{2,5})?)\s*([\])|:]|\s[-–]\s)\s*', unicode: true);
final _symbolsRe = RegExp(r"[^\p{L}\p{N}\s&'’.,:!?\-+()#/]", unicode: true);
final _edgesRe = RegExp(r'^[\s\-–|:]+|[\s\-–|:]+$');

final _cache = <String, DisplayName>{};

/// Clean name and tags for a raw provider name (cached; called for every row on screen).
DisplayName displayName(String raw) {
  final hit = _cache[raw];
  if (hit != null) return hit;
  final d = _parse(raw);
  if (_cache.length > 20000) _cache.clear();
  _cache[raw] = d;
  return d;
}

DisplayName _parse(String raw) {
  var s = _smallCaps(plainText(raw)).trim();
  final tags = <String>[];
  void tag(String t) {
    final u = t.toUpperCase();
    if (!tags.contains(u)) tags.add(u);
  }

  // Leading codes: "US| ", "|EN| ", "[DE] ", "US - ", "PRIME| " (up to two of them).
  for (var i = 0; i < 2; i++) {
    final m = _prefixRe.firstMatch(s);
    if (m == null || m.end >= s.length) break;
    final code = m.group(1)!;
    final sep = m.group(2)!;
    final boxed = sep.contains('|') || sep.contains(']') || sep.contains(')');
    // "|"-style prefixes are always tags; " - " and ":" only for known codes (so "TNT - East" stays).
    if (code != code.toUpperCase() || !(boxed || _isTag(code))) break;
    tag(code);
    s = s.substring(m.end);
  }

  // Symbols and emoji go; letters and digits of every language stay.
  s = s.replaceAll(_symbolsRe, ' ');

  // Trailing tags, from the end: "DE 4K HDR", "(4K)", "[HD]". The name always keeps one word.
  final words = s.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  final trailing = <String>[];
  while (words.length > 1) {
    final w = words.last.replaceAll(RegExp(r'^[\[(]+|[\])]+$'), '');
    if (w.isEmpty || !_isTag(w)) break;
    trailing.insert(0, w);
    words.removeLast();
  }
  for (final t in trailing) {
    tag(t);
  }

  var title = words.join(' ').replaceAll(_edgesRe, '').trim();
  if (title.isEmpty) title = raw.trim();
  return DisplayName(title, tags);
}
