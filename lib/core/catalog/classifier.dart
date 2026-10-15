/// Turns messy provider categories into broad genre, country, and language.
/// Example: "PL | DZIECI" -> Kids, Poland, Polish.

class Classified {
  final String genre;
  final String country;
  final String language;
  const Classified(this.genre, this.country, this.language);
}

const genreOrder = [
  'Sports', 'Movies', 'Entertainment', 'Kids', 'News', 'Documentary', 'Music', 'Religious', 'Adult', 'Other',
];

const _codes = {
  'US': 'United States', 'USA': 'United States', 'UK': 'United Kingdom', 'GB': 'United Kingdom',
  'CA': 'Canada', 'CAN': 'Canada', 'MX': 'Mexico', 'MEX': 'Mexico', 'ES': 'Spain', 'SPA': 'Spain',
  'PT': 'Portugal', 'BR': 'Brazil', 'BRA': 'Brazil', 'ARG': 'Argentina', 'CO': 'Colombia', 'COL': 'Colombia',
  'CL': 'Chile', 'PE': 'Peru', 'LAT': 'Latin America', 'LATAM': 'Latin America', 'LAME': 'Latin America',
  'FR': 'France', 'FRA': 'France', 'BE': 'Belgium', 'NL': 'Netherlands', 'DE': 'Germany', 'GER': 'Germany',
  'AT': 'Austria', 'CH': 'Switzerland', 'IT': 'Italy', 'ITA': 'Italy', 'PL': 'Poland', 'RO': 'Romania',
  'HU': 'Hungary', 'GR': 'Greece', 'TR': 'Turkey', 'RU': 'Russia', 'UA': 'Ukraine', 'EX-YU': 'Balkans',
  'EXYU': 'Balkans', 'AR': 'Arabic', 'ARA': 'Arabic', 'IN': 'India', 'IND': 'India', 'PK': 'Pakistan',
  'AF': 'Africa', 'AU': 'Australia', 'NZ': 'New Zealand', 'IE': 'Ireland', 'SE': 'Sweden', 'NO': 'Norway',
  'DK': 'Denmark', 'FI': 'Finland', 'CZ': 'Czechia', 'SK': 'Slovakia', 'PH': 'Philippines', 'CN': 'China',
  'JP': 'Japan', 'KR': 'Korea', 'IR': 'Iran', 'IL': 'Israel', 'AL': 'Albania',
};

const _words = {
  'united states': 'United States', 'usa': 'United States', 'canada': 'Canada', 'mexico': 'Mexico',
  'spain': 'Spain', 'españa': 'Spain', 'portugal': 'Portugal', 'brazil': 'Brazil', 'brasil': 'Brazil',
  'argentina': 'Argentina', 'colombia': 'Colombia', 'latino': 'Latin America', 'latin': 'Latin America',
  'france': 'France', 'germany': 'Germany', 'deutsch': 'Germany', 'italy': 'Italy', 'italia': 'Italy',
  'poland': 'Poland', 'polska': 'Poland', 'turkey': 'Turkey', 'türk': 'Turkey', 'arabic': 'Arabic',
  'arab': 'Arabic', 'india': 'India', 'pakistan': 'Pakistan', 'russia': 'Russia', 'greece': 'Greece',
  'netherlands': 'Netherlands', 'romania': 'Romania', 'africa': 'Africa', 'philippines': 'Philippines',
};

const _lang = {
  'United States': 'English', 'United Kingdom': 'English', 'Canada': 'English', 'Australia': 'English',
  'Ireland': 'English', 'New Zealand': 'English', 'Spain': 'Spanish', 'Mexico': 'Spanish',
  'Argentina': 'Spanish', 'Colombia': 'Spanish', 'Chile': 'Spanish', 'Peru': 'Spanish',
  'Latin America': 'Spanish', 'Brazil': 'Portuguese', 'Portugal': 'Portuguese', 'France': 'French',
  'Belgium': 'French', 'Germany': 'German', 'Austria': 'German', 'Switzerland': 'German', 'Italy': 'Italian',
  'Poland': 'Polish', 'Romania': 'Romanian', 'Hungary': 'Hungarian', 'Greece': 'Greek', 'Turkey': 'Turkish',
  'Russia': 'Russian', 'Ukraine': 'Ukrainian', 'Arabic': 'Arabic', 'India': 'Hindi', 'Pakistan': 'Urdu',
  'Netherlands': 'Dutch', 'Sweden': 'Swedish', 'Norway': 'Norwegian', 'Denmark': 'Danish',
  'Finland': 'Finnish', 'Czechia': 'Czech', 'Slovakia': 'Slovak', 'Japan': 'Japanese', 'Korea': 'Korean',
  'China': 'Chinese', 'Iran': 'Persian', 'Israel': 'Hebrew', 'Albania': 'Albanian', 'Balkans': 'Serbo-Croatian',
  'Philippines': 'Filipino',
};

final _genres = <(String, RegExp)>[
  ('Adult', RegExp(r'\badult(?!\s*swim)|xxx|18\+|porn', caseSensitive: false)),
  ('Sports', RegExp(r'sport|football|soccer|f[uú]tbol|\bnba\b|\bnfl\b|\bnhl\b|\bmlb\b|\bufc\b|\bppv\b|\bf1\b|golf|tennis|espn|dazn|laliga|\bliga\b|premier league|bein|wrestl|boxing|cricket|racing|nascar', caseSensitive: false)),
  ('Kids', RegExp(r'\bkids?\b|child|cartoon|dzieci|infantil|enfant|disney|nick|junior|baby|boomerang|adult\s*swim', caseSensitive: false)),
  ('News', RegExp(r'news|noticias|nachrichten|\bcnn\b|msnbc|bloomberg|cnbc|jazeera', caseSensitive: false)),
  ('Documentary', RegExp(r'\bdoc|dokument|discovery|history|nat\s*geo|national geographic|animal planet|science', caseSensitive: false)),
  ('Music', RegExp(r'music|muzyk|m[uú]sica|\bmtv\b|\bvh1\b|radio', caseSensitive: false)),
  ('Movies', RegExp(r'movie|film|cinema|\bcine|\bhbo\b|cinemax|showtime|starz|epix|\bmgm\b|\btcm\b', caseSensitive: false)),
  ('Religious', RegExp(r'relig|church|gospel|islam|quran|christian|catholic|\bgod\b', caseSensitive: false)),
  ('Entertainment', RegExp(r'entertain|general|og[oó]ln|variety|comedy|series|drama|reality|lifestyle', caseSensitive: false)),
];

final _prefixRe = RegExp(r'^\s*[\[\(|]?\s*([A-Za-z]{2,5}(?:-[A-Za-z]{2})?)\s*[\]\)]?\s*[|:\-]');

String _country(String s) {
  final m = _prefixRe.firstMatch(s);
  if (m != null) {
    final c = _codes[m.group(1)!.toUpperCase()];
    if (c != null) return c;
  }
  final l = s.toLowerCase();
  for (final e in _words.entries) {
    if (RegExp(r'\b' + RegExp.escape(e.key) + r'\b').hasMatch(l)) return e.value;
  }
  return '';
}

String _genre(String s) {
  for (final g in _genres) {
    if (g.$2.hasMatch(s)) return g.$1;
  }
  return '';
}

Classified classify(String category, String name) {
  var genre = _genre(category);
  if (genre.isEmpty) genre = _genre(name);
  if (genre.isEmpty) genre = 'Other';
  var country = _country(category);
  if (country.isEmpty) country = _country(name);
  return Classified(genre, country, _lang[country] ?? '');
}
