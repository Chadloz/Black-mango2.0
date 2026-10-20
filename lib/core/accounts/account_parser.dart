/// Reads pasted account info in ANY format and pulls out what it can.
/// No required labels or layout: URLs, labeled values, MAC addresses, and bare words are all
/// handled, including fancy-font labels (𝑷𝒐𝒓𝒕𝒂𝒍), emoji decorations, and values run together.
class ParsedAccount {
  String type = 'xtream'; // xtream | stalker | m3u
  String server = '';
  String username = '';
  String password = '';
  String mac = '';
  String url = '';

  /// Every MAC address in the paste (Stalker); [mac] is the first.
  final List<String> macs = [];

  /// An Xtream / M3U login that came with a Stalker paste (same provider), offered as an option.
  String altServer = '';
  String altUsername = '';
  String altPassword = '';

  final List<String> found = []; // "portal", "2 MACs"...
  final List<String> ignored = []; // "expiry date", "2 other links"...
  final List<String> notes = [];

  bool get hasAltLogin => altServer.isNotEmpty && altUsername.isNotEmpty && altPassword.isNotEmpty;

  bool get isEmpty =>
      server.isEmpty && username.isEmpty && password.isEmpty && mac.isEmpty && url.isEmpty;

  String get suggestedName => hostOf(type == 'm3u' ? url : server);

  /// "Found: portal, 2 MACs. Ignored: expiry date, M3U link."
  String get summary {
    final parts = <String>[];
    if (found.isNotEmpty) parts.add('Found: ${found.join(', ')}.');
    if (ignored.isNotEmpty) parts.add('Ignored: ${ignored.join(', ')}.');
    return parts.join(' ');
  }
}

/// Fancy Unicode letters and digits (𝑷𝒐𝒓𝒕𝒂𝒍, 𝗣𝗼𝗿𝘁𝗮𝗹, 𝟴𝟬...) turned back into plain ones.
String plainText(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    if (r >= 0x1D400 && r <= 0x1D6A3) {
      final i = (r - 0x1D400) % 52;
      b.writeCharCode(i < 26 ? 0x41 + i : 0x61 + i - 26);
    } else if (r >= 0x1D7CE && r <= 0x1D7FF) {
      b.writeCharCode(0x30 + (r - 0x1D7CE) % 10);
    } else {
      b.writeCharCode(r);
    }
  }
  return b.toString();
}

/// The end of a MAC for account names: 00:1A:79:10:E0:67 -> E0:67.
String macTail(String mac) {
  final parts = mac.toUpperCase().split(RegExp(r'[:-]'));
  return parts.length >= 2 ? '${parts[parts.length - 2]}:${parts.last}' : mac;
}

String normalizeServer(String s) {
  var v = s.trim();
  if (v.isEmpty) return '';
  if (!v.contains('://')) v = 'http://$v';
  while (v.endsWith('/')) {
    v = v.substring(0, v.length - 1);
  }
  return v;
}

String hostOf(String s) {
  if (s.trim().isEmpty) return '';
  final u = Uri.tryParse(s.contains('://') ? s : 'http://$s');
  return u == null ? '' : u.host;
}

String _clean(String v) => v.trim().replaceAll(RegExp(r'''^["'<(\[]+|["'>)\].,;]+$'''), '');

const _labelWords = {
  'username', 'user', 'login', 'account', 'acct', 'password', 'passwd', 'pass', 'pwd', 'pin',
  'host', 'server', 'url', 'dns', 'portal', 'domain', 'address', 'mac',
};

// Links stop at anything that can't be in one (spaces, commas, emoji, box-drawing lines...).
final _urlRe = RegExp(r'''https?://[A-Za-z0-9\-._~:/?#@!$&'()*+;=%\[\]]+''', caseSensitive: false);
final _macRe = RegExp(r'\b([0-9A-Fa-f]{2}(?:[:-][0-9A-Fa-f]{2}){5})\b');
final _expiryRe = RegExp(r'\b(exp|expires?|expiry|expiration|valid|until|ablauf|end date)\b', caseSensitive: false);

/// One link in the paste and the words in front of it on its line ("panel", "real", "m3u"...).
class _Link {
  final String url;
  final String label;
  _Link(this.url, this.label);
}

/// An Xtream login carried inside a link (get.php?username=..., /live/user/pass/..., /user/pass/123).
(String, String, String)? _loginIn(String u) {
  final uri = Uri.tryParse(u);
  if (uri == null || uri.host.isEmpty) return null;
  final base = '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
  Map<String, String> q = {};
  try {
    q = uri.queryParameters;
  } catch (_) {}
  final qUser = q['username'] ?? q['user'] ?? q['login'];
  final qPass = q['password'] ?? q['pass'] ?? q['pwd'];
  if (qUser != null && qPass != null) return (base, qUser, qPass);
  final seg = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (seg.length >= 4 && const ['live', 'movie', 'series'].contains(seg[0].toLowerCase())) return (base, seg[1], seg[2]);
  if (seg.length == 3 && RegExp(r'^\d+(\.\w+)?$').hasMatch(seg[2])) return (base, seg[0], seg[1]);
  return null;
}

ParsedAccount parseAccountText(String raw) {
  final p = ParsedAccount();
  final text = plainText(raw).trim();
  if (text.isEmpty) return p;
  if (_expiryRe.hasMatch(text)) p.ignored.add('expiry date');

  // Every link, with the words in front of it on its line.
  final links = <_Link>[];
  for (final line in text.split(RegExp(r'[\r\n]+'))) {
    for (final m in _urlRe.allMatches(line)) {
      final label = line.substring(0, m.start).toLowerCase().replaceAll(RegExp(r'[^a-z ]+'), ' ').trim();
      links.add(_Link(_clean(m.group(0)!), label));
    }
  }

  // Every MAC address: one or more means Stalker.
  for (final m in _macRe.allMatches(text)) {
    final mac = m.group(1)!.replaceAll('-', ':').toUpperCase();
    if (!p.macs.contains(mac)) p.macs.add(mac);
  }
  if (p.macs.isNotEmpty) return _stalker(p, links);

  // 2. Pull apart every URL.
  final urls = links.map((l) => l.url).toList();
  for (final u in urls) {
    final uri = Uri.tryParse(u);
    if (uri == null || uri.host.isEmpty) continue;
    final base = '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
    Map<String, String> q = {};
    try {
      q = uri.queryParameters;
    } catch (_) {}
    final qUser = q['username'] ?? q['user'] ?? q['login'];
    final qPass = q['password'] ?? q['pass'] ?? q['pwd'];
    if (p.username.isEmpty && qUser != null && qPass != null) {
      p.server = base;
      p.username = qUser;
      p.password = qPass;
      p.notes.add('Found an Xtream login inside the link.');
      continue;
    }
    final seg = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (p.username.isEmpty && seg.length >= 4 && const ['live', 'movie', 'series'].contains(seg[0].toLowerCase())) {
      p.server = base;
      p.username = seg[1];
      p.password = seg[2];
      p.notes.add('Found an Xtream login inside a stream link.');
      continue;
    }
    if (p.username.isEmpty && seg.length == 3 && RegExp(r'^\d+(\.\w+)?$').hasMatch(seg[2])) {
      p.server = base;
      p.username = seg[0];
      p.password = seg[1];
      p.notes.add('Found an Xtream login inside a stream link.');
      continue;
    }
    if (p.url.isEmpty) p.url = u;
    if (p.server.isEmpty) p.server = p.mac.isNotEmpty ? u : base;
  }

  // 3. Labeled values in any wording ("User: x", "pass = y", "Host - z").
  String? labeled(String labels) {
    final m = RegExp(r'\b(?:' + labels + r')\b\s*[:=\-–]+\s*([^\s,;|]+)', caseSensitive: false).firstMatch(text);
    return m == null ? null : _clean(m.group(1)!);
  }

  bool ok(String? v) => v != null && v.isNotEmpty && !_labelWords.contains(v.toLowerCase());
  final lu = labeled(r'user\s*name|username|user|login|account|acct');
  final lp = labeled(r'pass\s*word|password|passwd|pass|pwd|pin');
  final lh = labeled(r'host|server|url|dns|portal|domain|address');
  final lm = labeled(r'mac\s*address|mac');
  if (p.username.isEmpty && ok(lu)) p.username = lu!;
  if (p.password.isEmpty && ok(lp)) p.password = lp!;
  if (p.server.isEmpty && ok(lh)) p.server = normalizeServer(lh!);
  if (p.mac.isEmpty && ok(lm) && RegExp(r'^[0-9A-Fa-f:]{17}$').hasMatch(lm!)) p.mac = lm!.toUpperCase();
  if (p.mac.isNotEmpty) {
    p.macs.add(p.mac);
    return _stalker(p, links);
  }

  // 4. No labels at all: find a bare host, then two leftover words become login + password.
  if (p.mac.isEmpty && p.username.isEmpty && p.password.isEmpty) {
    final tokens = text.split(RegExp(r'\s+')).map(_clean).where((t) => t.isNotEmpty).toList();
    if (p.server.isEmpty) {
      final hostRe = RegExp(r'^[\w\-]+(\.[\w\-]+)+(:\d+)?(/.*)?$');
      final hosts = tokens.where((t) => hostRe.hasMatch(t)).toList();
      if (hosts.isNotEmpty) p.server = normalizeServer(hosts.first);
    }
    if (p.server.isNotEmpty) {
      final serverHost = hostOf(p.server);
      final left = tokens
          .where((t) =>
              !t.contains('://') &&
              hostOf(t) != serverHost &&
              !t.endsWith(':') &&
              !_labelWords.contains(t.toLowerCase()))
          .toList();
      if (left.length == 2) {
        p.username = left[0];
        p.password = left[1];
        p.notes.add('Guessed the username and password from unlabeled text. Double-check them.');
      }
    }
  }

  // 5. Decide the account type.
  if (p.username.isNotEmpty && p.password.isNotEmpty && p.server.isNotEmpty) {
    p.type = 'xtream';
    p.found.add('Xtream login');
    p.notes.removeWhere((n) => n.startsWith('Found an Xtream login'));
  } else if (p.url.isNotEmpty) {
    p.type = 'm3u';
    p.found.add('playlist link');
    p.notes.remove('Looks like a playlist link.');
  }
  final extra = urls.length - 1;
  if (extra > 0) p.ignored.add(extra == 1 ? '1 other link' : '$extra other links');
  return p;
}

/// A paste with MAC addresses: a Stalker portal. The link labeled Portal or Panel wins,
/// then one that looks like a portal address (/c/, portal.php, load.php), then the first link.
/// An Xtream / M3U login in the same paste is kept aside as an option, never mixed in.
ParsedAccount _stalker(ParsedAccount p, List<_Link> links) {
  p.type = 'stalker';
  p.mac = p.macs.first;
  final plain = <_Link>[];
  var epg = 0;
  for (final l in links) {
    final login = _loginIn(l.url);
    if (login != null) {
      if (p.altServer.isEmpty) {
        p.altServer = login.$1;
        p.altUsername = login.$2;
        p.altPassword = login.$3;
      }
      continue;
    }
    if (l.url.toLowerCase().contains('xmltv') || RegExp(r'\bepg\b').hasMatch(l.label)) {
      epg++;
      continue;
    }
    plain.add(l);
  }
  _Link? pick;
  for (final l in plain) {
    if (RegExp(r'portal|panel').hasMatch(l.label)) {
      pick = l;
      break;
    }
  }
  if (pick == null) {
    for (final l in plain) {
      final path = Uri.tryParse(l.url)?.path.toLowerCase() ?? '';
      if (RegExp(r'/c/?$|portal\.php|load\.php|stalker_portal').hasMatch(path)) {
        pick = l;
        break;
      }
    }
  }
  pick ??= plain.isEmpty ? null : plain.first;
  if (pick != null) {
    p.server = pick.url;
  } else if (p.altServer.isNotEmpty) {
    p.server = p.altServer; // no portal link at all: the login's server is the same provider
  }
  if (p.server.isNotEmpty) p.found.add('portal');
  p.found.add(p.macs.length == 1 ? '1 MAC' : '${p.macs.length} MACs');
  if (p.hasAltLogin) p.found.add('an M3U login too');
  final others = plain.where((l) => l != pick).length;
  if (others > 0) p.ignored.add(others == 1 ? '1 other link' : '$others other links');
  if (epg > 0) p.ignored.add('guide link');
  return p;
}
