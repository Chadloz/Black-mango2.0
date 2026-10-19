// Stalker (Ministra / MAG middleware) portal client for Black Mango.
//
// Protocol handling is informed by, and partly adapted from, stalkerhek
// (github.com/erkexzcx/stalkerhek and github.com/kidpoleon/stalkerhek),
// both licensed under the GNU GPL v3. Black Mango is GPL-3.0 as well.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import '../net/fetch.dart' show BMError;
import '../prefs.dart';
import '../storage/database.dart';

/// What a MAG250 box sends. Same identity the probe used on real portals.
const stalkerUserAgent =
    'Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG200 stbapp ver: 2 rev: 250 Safari/533.3';

/// The Mac's own timezone name (America/Denver style), so guide times line up.
String macTimezone() {
  try {
    final p = File('/etc/localtime').resolveSymbolicLinksSync();
    final i = p.indexOf('zoneinfo/');
    if (i >= 0) return p.substring(i + 9);
  } catch (_) {}
  const us = {
    'EST': 'America/New_York', 'EDT': 'America/New_York',
    'CST': 'America/Chicago', 'CDT': 'America/Chicago',
    'MST': 'America/Denver', 'MDT': 'America/Denver',
    'PST': 'America/Los_Angeles', 'PDT': 'America/Los_Angeles',
  };
  return us[DateTime.now().timeZoneName] ?? 'UTC';
}

/// The box a portal sees. Serial and device ID come from the MAC (the way
/// open-source MAG clients make them) unless the account overrides them.
class StalkerIdentity {
  final String mac;
  final String serial;
  final String deviceId;
  final String signature;
  final String hwVersion2;
  StalkerIdentity._(this.mac, this.serial, this.deviceId, this.signature, this.hwVersion2);

  /// 00-1a-79-… and 00:1A:79:… are the same box.
  static String normMac(String mac) => mac.trim().toUpperCase().replaceAll('-', ':');

  static String autoSerial(String mac) => md5.convert(utf8.encode(normMac(mac))).toString().toUpperCase().substring(0, 13);
  static String autoDeviceId(String mac) => sha256.convert(utf8.encode(normMac(mac))).toString().toUpperCase();

  factory StalkerIdentity(String mac, {String serial = '', String deviceId = ''}) {
    final m = normMac(mac);
    final sn = serial.trim().isNotEmpty ? serial.trim() : autoSerial(m);
    final dev = deviceId.trim().isNotEmpty ? deviceId.trim() : autoDeviceId(m);
    final sig = sha256.convert(utf8.encode(sn + m)).toString().toUpperCase();
    final hw2 = sha1.convert(utf8.encode(m)).toString();
    return StalkerIdentity._(m, sn, dev, sig, hw2);
  }
}

/// Per-account Stalker settings, kept in Prefs (so backups include them):
/// the API address that answered, plus optional serial / device ID overrides.
class StalkerSettings {
  static String _key(String accountId) => 'acct.$accountId.stalker';

  static Map<String, String> read(String accountId) {
    final raw = Prefs.getStr(_key(accountId));
    if (raw == null) return {};
    try {
      final m = jsonDecode(raw);
      if (m is Map) return {for (final e in m.entries) '${e.key}': '${e.value}'};
    } catch (_) {}
    return {};
  }

  static Future<void> write(String accountId, Map<String, String> m) =>
      Prefs.setStr(_key(accountId), m.isEmpty ? null : jsonEncode(m));

  static Future<void> update(String accountId, String k, String v) => write(accountId, read(accountId)..[k] = v);
}

/// The portal's command for a channel, saved in the item's extra info.
String stalkerCmd(String? extra) {
  try {
    final m = jsonDecode(extra ?? '');
    return m is Map ? '${m['cmd'] ?? ''}' : '';
  } catch (_) {
    return '';
  }
}

/// Channel logos can be full links, server paths, or bare file names.
String stalkerLogo(String logo, String api) {
  final l = logo.trim();
  if (l.isEmpty) return '';
  if (l.startsWith('http://') || l.startsWith('https://')) return l;
  final u = Uri.tryParse(api);
  if (u == null || u.host.isEmpty) return '';
  final base = '${u.scheme}://${u.host}${u.hasPort ? ':${u.port}' : ''}';
  if (l.startsWith('/')) return '$base$l';
  final dir = u.path.contains('/stalker_portal/') ? '$base/stalker_portal' : base;
  return '$dir/misc/logos/320/$l';
}

/// Big answers (10,000+ channels) are decoded off the UI thread. Top-level so the
/// closure carries only the text, never the client.
Future<dynamic> _jsInBackground(String body) => Isolate.run(() => _js(body));

dynamic _js(String body) {
  try {
    final j = jsonDecode(body);
    return j is Map ? j['js'] : null;
  } catch (_) {
    return null;
  }
}

const _months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];

/// Expiry dates arrive in many shapes: unix time, "2028-02-02 19:52:00",
/// "February 2, 2028, 7:52 pm", or "02.02.2028". Returns unix seconds.
int? parseStalkerDate(String raw) {
  final s = raw.trim();
  if (s.isEmpty || s == '0' || s.toLowerCase() == 'null') return null;
  final n = int.tryParse(s);
  if (n != null) {
    if (n > 100000000000) return n ~/ 1000;
    return n > 1000000000 ? n : null;
  }
  final iso = DateTime.tryParse(s);
  if (iso != null) return iso.millisecondsSinceEpoch ~/ 1000;
  final w = RegExp(r'([A-Za-z]{3,})\.?\s+(\d{1,2}),?\s+(\d{4})(?:,?\s+(\d{1,2}):(\d{2})\s*([AaPp][Mm])?)?').firstMatch(s);
  if (w != null) {
    final mon = _months.indexOf(w[1]!.substring(0, 3).toLowerCase());
    if (mon < 0) return null;
    var h = int.tryParse(w[4] ?? '') ?? 0;
    final ap = (w[6] ?? '').toLowerCase();
    if (ap == 'pm' && h < 12) h += 12;
    if (ap == 'am' && h == 12) h = 0;
    final d = DateTime(int.parse(w[3]!), mon + 1, int.parse(w[2]!), h, int.tryParse(w[5] ?? '') ?? 0);
    return d.millisecondsSinceEpoch ~/ 1000;
  }
  final e = RegExp(r'^(\d{1,2})[./](\d{1,2})[./](\d{4})').firstMatch(s);
  if (e != null) {
    final d = DateTime(int.parse(e[3]!), int.parse(e[2]!), int.parse(e[1]!));
    return d.millisecondsSinceEpoch ~/ 1000;
  }
  return null;
}

/// Talks to one Stalker portal as one MAG box.
class StalkerClient {
  final String portal; // as entered: http://host:port/c/ or similar
  final StalkerIdentity id;
  final String timezone;

  /// Called when a different API address answers, so it can be remembered.
  final void Function(String api)? onApi;

  /// The address that answered (…/portal.php or …/server/load.php).
  String? api;
  String _token = '';
  Future<void>? _login;
  Map<String, dynamic> profile = {};

  StalkerClient(this.portal, this.id, {this.api, this.onApi}) : timezone = macTimezone();

  Uri get _portalUri => Uri.parse(portal.contains('://') ? portal : 'http://$portal');

  String get _base {
    final u = _portalUri;
    return '${u.scheme}://${u.host}${u.hasPort ? ':${u.port}' : ''}';
  }

  String get _referer => _portalUri.path.contains('stalker_portal') ? '$_base/stalker_portal/c/' : '$_base/c/';

  /// Where the API might live, most likely first (portal.php, then load.php).
  List<String> get candidates {
    var path = _portalUri.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    final out = <String>[];
    void add(String s) {
      if (!out.contains(s)) out.add(s);
    }

    if (path.endsWith('.php')) add('$_base$path');
    if (path.contains('stalker_portal')) add('$_base/stalker_portal/server/load.php');
    add('$_base/portal.php');
    add('$_base/server/load.php');
    add('$_base/stalker_portal/server/load.php');
    add('$_base/c/portal.php');
    if (path.isNotEmpty && !path.endsWith('.php')) add('$_base$path/portal.php');
    add('$_base/load.php');
    return out;
  }

  Future<(int, String)> _get(Uri uri, {bool tokenCookie = true, Duration timeout = const Duration(seconds: 20)}) async {
    final client = HttpClient()
      ..userAgent = null
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final req = await client.getUrl(uri);
      var cookie = 'mac=${Uri.encodeComponent(id.mac)}; stb_lang=en; timezone=${Uri.encodeComponent(timezone)}';
      if (_token.isNotEmpty && tokenCookie) cookie += '; token=$_token';
      req.headers
        ..set('user-agent', stalkerUserAgent)
        ..set('x-user-agent', 'Model: MAG250; Link: WiFi')
        ..set('accept', '*/*')
        ..set('referer', _referer)
        ..set('cookie', cookie);
      if (_token.isNotEmpty) req.headers.set('authorization', 'Bearer $_token');
      final res = await req.close().timeout(timeout);
      final body = await res.transform(const Utf8Decoder(allowMalformed: true)).join().timeout(timeout);
      return (res.statusCode, body);
    } on SocketException catch (e) {
      throw BMError('Could not reach the portal (${e.osError?.message ?? e.message})');
    } on TimeoutException {
      throw BMError('The portal took too long to answer.');
    } on HandshakeException {
      throw BMError('Secure connection failed (SSL)');
    } finally {
      client.close(force: true);
    }
  }

  // ---------- Session ----------

  /// Logs in if needed. Several callers at once share one login.
  Future<void> ensure() {
    if (_token.isNotEmpty && api != null) return Future.value();
    return _login ??= _doLogin().whenComplete(() => _login = null);
  }

  Future<void> _doLogin() async {
    final saved = api;
    final tries = [if (saved != null) saved, ...candidates.where((c) => c != saved)];
    BMError? lastErr;
    for (final a in tries) {
      try {
        final t = await _handshake(a);
        if (t == null) continue;
        api = a;
        _token = t;
        await _profile();
        if (a != saved) onApi?.call(a);
        debugPrint('[stalker] logged in at ${Uri.parse(a).path} (timezone $timezone)');
        return;
      } on BMError catch (e) {
        lastErr = e;
        if (e.message.contains('blocked')) rethrow;
        // The whole server is unreachable: the other paths won't do better.
        if (e.message.startsWith('Could not reach') || e.message.contains('too long')) break;
      }
    }
    _token = '';
    throw lastErr ?? BMError('No Stalker portal answered at that address. Check the portal URL.');
  }

  String? _tokenOf(int st, String body) {
    if (st != 200) return null;
    final j = _js(body);
    final t = j is Map ? '${j['token'] ?? ''}' : '';
    return t.isEmpty ? null : t;
  }

  Future<String?> _handshake(String a) async {
    _token = '';
    final (st, body) = await _get(Uri.parse('$a?type=stb&action=handshake&token=&JsHttpRequest=1-xml'));
    var t = _tokenOf(st, body);
    if (t == null && st == 404) {
      // Some portals want a made-up token plus its SHA-1 "prehash" first.
      final r = Random.secure();
      final gen = List.generate(32, (_) => '0123456789ABCDEF'[r.nextInt(16)]).join();
      final pre = sha1.convert(utf8.encode(gen)).toString();
      final (st2, body2) = await _get(Uri.parse('$a?type=stb&action=handshake&token=$gen&prehash=$pre&JsHttpRequest=1-xml'));
      t = _tokenOf(st2, body2);
    }
    return t;
  }

  Future<void> _profile() async {
    final r = Random.secure();
    final rnd = List.generate(40, (_) => '0123456789abcdef'[r.nextInt(16)]).join();
    final metrics = jsonEncode({'mac': id.mac, 'sn': id.serial, 'type': 'STB', 'model': 'MAG250', 'uid': id.deviceId, 'random': rnd});
    final q = {
      'type': 'stb',
      'action': 'get_profile',
      'hd': '1',
      'ver': 'ImageDescription: 0.2.18-r23-250; PORTAL version: 5.6.2; API Version: JS API version: 343',
      'num_banks': '2',
      'sn': id.serial,
      'stb_type': 'MAG250',
      'client_type': 'STB',
      'image_version': '218',
      'video_out': 'hdmi',
      'device_id': id.deviceId,
      'device_id2': id.deviceId,
      'signature': id.signature,
      'auth_second_step': '1',
      'hw_version': '1.7-BD-00',
      'not_valid_token': '0',
      'metrics': metrics,
      'hw_version_2': id.hwVersion2,
      'timestamp': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
      'api_signature': '262',
      'prehash': '',
      'JsHttpRequest': '1-xml',
    };
    final (st, body) = await _get(Uri.parse(api!).replace(queryParameters: q), tokenCookie: false);
    final p = _js(body);
    if (p is Map) {
      profile = Map<String, dynamic>.from(p);
      final t = '${p['token'] ?? ''}';
      if (t.isNotEmpty) _token = t;
      if ('${p['blocked'] ?? '0'}' == '1') {
        final msg = '${p['block_msg'] ?? p['msg'] ?? ''}'.trim();
        throw BMError('The portal says this MAC is blocked${msg.isEmpty ? '' : ': $msg'}.');
      }
    } else if (st >= 400) {
      throw BMError('The portal refused the login (HTTP $st).');
    }
  }

  static bool _authFailed(int st, String body) =>
      st == 401 || (body.length < 400 && body.toLowerCase().contains('authorization failed'));

  /// One API call. If the session expired, logs in again quietly and retries once.
  Future<dynamic> request(Map<String, String> q, {Duration timeout = const Duration(seconds: 20), bool retry = true}) async {
    await ensure();
    final used = _token;
    final uri = Uri.parse(api!).replace(queryParameters: {...q, 'JsHttpRequest': '1-xml'});
    final (st, body) = await _get(uri, timeout: timeout);
    if (retry && _authFailed(st, body)) {
      debugPrint('[stalker] session expired; logging in again');
      if (_token == used) _token = '';
      return request(q, timeout: timeout, retry: false);
    }
    if (st >= 400) throw BMError('Server answered $st');
    return body.length > 200000 ? _jsInBackground(body) : _js(body);
  }

  // ---------- Account ----------

  /// Account expiry as unix seconds, or null when the portal doesn't say.
  Future<int?> expiry() async {
    try {
      final j = await request({'type': 'account_info', 'action': 'get_main_info'});
      if (j is! Map) return null;
      for (final k in const ['end_date', 'expire_billing_date', 'phone', 'expire_date', 'tariff_expired_date']) {
        final t = parseStalkerDate('${j[k] ?? ''}');
        if (t != null) return t;
      }
    } catch (e) {
      debugPrint('[stalker] no account info: $e');
    }
    return null;
  }

  // ---------- Live TV ----------

  /// genre id -> genre name
  Future<Map<String, String>> liveGenres() async {
    final j = await request({'type': 'itv', 'action': 'get_genres'});
    final out = <String, String>{};
    if (j is List) {
      for (final g in j) {
        if (g is Map) out['${g['id']}'] = '${g['title'] ?? ''}'.trim();
      }
    }
    return out;
  }

  /// Every live channel: one request where the portal allows it,
  /// otherwise the page-by-page list, 4 pages at a time.
  Future<List<Map>> liveChannels({void Function(int done, int total)? progress}) async {
    try {
      final j = await request({'type': 'itv', 'action': 'get_all_channels', 'force_ch_link_check': ''},
          timeout: const Duration(seconds: 60));
      final data = j is Map ? j['data'] : null;
      if (data is List && data.isNotEmpty) {
        debugPrint('[stalker] channel list: all at once (${data.length})');
        return data.whereType<Map>().toList();
      }
    } catch (e) {
      debugPrint('[stalker] all-at-once list not available ($e); loading page by page');
    }

    Map<String, String> q(int p) =>
        {'type': 'itv', 'action': 'get_ordered_list', 'genre': '*', 'fav': '0', 'sortby': 'number', 'p': '$p'};
    List<Map> rowsOf(dynamic j) => j is Map && j['data'] is List ? (j['data'] as List).whereType<Map>().toList() : <Map>[];

    final first = await request(q(1));
    if (first is! Map) throw BMError('The portal did not return a channel list.');
    final firstRows = rowsOf(first);
    final total = int.tryParse('${first['total_items'] ?? ''}') ?? firstRows.length;
    var per = int.tryParse('${first['max_page_items'] ?? ''}') ?? firstRows.length;
    if (per <= 0) per = 14;
    final pages = total <= 0 ? 1 : (total + per - 1) ~/ per;
    final byPage = <int, List<Map>>{1: firstRows};
    var next = 2;
    var done = 1;
    progress?.call(done, pages);

    Future<void> worker() async {
      while (true) {
        final p = next++;
        if (p > pages) return;
        var rows = <Map>[];
        for (var attempt = 0; attempt < 3; attempt++) {
          try {
            rows = rowsOf(await request(q(p)));
            break;
          } catch (e) {
            if (attempt == 2) debugPrint('[stalker] channel page $p failed: $e');
            await Future.delayed(Duration(milliseconds: 800 * (attempt + 1)));
          }
        }
        byPage[p] = rows;
        progress?.call(++done, pages);
      }
    }

    await Future.wait(List.generate(4, (_) => worker()));
    final out = <Map>[];
    final seen = <String>{};
    for (var p = 1; p <= pages; p++) {
      for (final m in byPage[p] ?? const <Map>[]) {
        if (seen.add('${m['id'] ?? m['cmd']}')) out.add(m);
      }
    }
    debugPrint('[stalker] channel list: $pages pages, ${out.length} channels');
    return out;
  }

  /// A fresh playable link. Portal links expire within minutes, so ask every time.
  Future<String> liveLink(String cmd) async {
    final j = await request({
      'type': 'itv',
      'action': 'create_link',
      'cmd': cmd,
      'series': '',
      'forced_storage': 'undefined',
      'disable_ad': '0',
      'download': '0',
    });
    var raw = '';
    if (j is Map) {
      raw = '${j['url'] ?? ''}'.trim();
      if (raw.isEmpty) raw = '${j['cmd'] ?? ''}'.trim();
    }
    final link = streamUrlOf(raw);
    final u = link == null ? null : Uri.tryParse(link);
    if (link == null || u == null || u.host == 'localhost') {
      debugPrint('[stalker] create_link gave no usable link (answer: ${j is Map ? j.keys.join(',') : j.runtimeType})');
      throw BMError('The portal did not give a playable link for this channel.');
    }
    // Shape only, never the query (it carries the MAC and the play token).
    debugPrint('[stalker] new link: ${u.scheme}://${u.host}${u.hasPort ? ':${u.port}' : ''}${u.path} '
        '(${u.queryParameters.keys.join(',')})');
    return link;
  }

  /// "ffmpeg http://…" and similar: the link is the last http(s) word.
  static String? streamUrlOf(String raw) {
    for (final part in raw.trim().split(RegExp(r'\s+')).reversed) {
      if (part.startsWith('http://') || part.startsWith('https://')) return part;
    }
    return null;
  }

  /// Keep-alive: what a MAG box sends so the portal doesn't drop the session.
  Future<void> watchdog() async {
    try {
      await request({'type': 'watchdog', 'action': 'get_events', 'event_active_id': '0', 'init': '0', 'cur_play_type': '1'});
    } catch (e) {
      debugPrint('[stalker] keep-alive failed: $e');
    }
  }

  /// Now / next for one channel.
  Future<List<Map>> shortEpg(String chId) async {
    final j = await request({'type': 'itv', 'action': 'get_short_epg', 'ch_id': chId, 'size': '3'},
        timeout: const Duration(seconds: 15));
    if (j is List) return j.whereType<Map>().toList();
    if (j is Map && j['data'] is List) return (j['data'] as List).whereType<Map>().toList();
    return const <Map>[];
  }
}

/// One client per account, shared by loading, playback, and the guide,
/// so they all ride the same portal session.
class StalkerHub {
  static final _clients = <String, StalkerClient>{};
  static final _sigs = <String, String>{};

  static StalkerClient of(Account a) {
    final s = StalkerSettings.read(a.id);
    final sig = [a.server, a.mac, s['serial'] ?? '', s['deviceId'] ?? ''].join('|');
    final have = _clients[a.id];
    if (have != null && _sigs[a.id] == sig) return have;
    final savedApi = s['api'] ?? '';
    final c = StalkerClient(
      a.server,
      StalkerIdentity(a.mac, serial: s['serial'] ?? '', deviceId: s['deviceId'] ?? ''),
      api: savedApi.isEmpty ? null : savedApi,
      onApi: (api) => StalkerSettings.update(a.id, 'api', api),
    );
    _clients[a.id] = c;
    _sigs[a.id] = sig;
    return c;
  }
}
