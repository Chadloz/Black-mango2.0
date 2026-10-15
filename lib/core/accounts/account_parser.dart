/// Reads pasted account info in ANY format and pulls out what it can.
/// No required labels or layout: URLs, labeled values, MAC addresses,
/// and bare words are all handled.
class ParsedAccount {
  String type = 'xtream'; // xtream | stalker | m3u
  String server = '';
  String username = '';
  String password = '';
  String mac = '';
  String url = '';
  final List<String> notes = [];

  bool get isEmpty =>
      server.isEmpty && username.isEmpty && password.isEmpty && mac.isEmpty && url.isEmpty;

  String get suggestedName => hostOf(type == 'm3u' ? url : server);
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

ParsedAccount parseAccountText(String raw) {
  final p = ParsedAccount();
  final text = raw.trim();
  if (text.isEmpty) return p;

  // 1. A MAC address anywhere means Stalker.
  final macMatch = RegExp(r'\b([0-9A-Fa-f]{2}(?:[:-][0-9A-Fa-f]{2}){5})\b').firstMatch(text);
  if (macMatch != null) p.mac = macMatch.group(1)!.replaceAll('-', ':').toUpperCase();

  // 2. Pull apart every URL.
  final urls = RegExp(r'https?://[^\s"<>]+', caseSensitive: false)
      .allMatches(text)
      .map((m) => _clean(m.group(0)!))
      .toList();
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
  if (p.mac.isNotEmpty) {
    p.type = 'stalker';
    if (p.server.isEmpty && p.url.isNotEmpty) p.server = p.url;
    p.notes.add('MAC address found, so this looks like a Stalker portal.');
  } else if (p.username.isNotEmpty && p.password.isNotEmpty && p.server.isNotEmpty) {
    p.type = 'xtream';
    if (p.notes.isEmpty) p.notes.add('Found an Xtream login.');
  } else if (p.url.isNotEmpty) {
    p.type = 'm3u';
    p.notes.add('Looks like a playlist link.');
  }
  return p;
}
