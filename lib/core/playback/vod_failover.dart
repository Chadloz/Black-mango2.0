import 'dart:async';
import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../prefs.dart';
import '../providers/xtream.dart';
import '../services.dart';
import '../storage/database.dart';

typedef TitleKey = ({String title, int? year, String? lang});

/// A match on another account. [needsSubs]: different language, so it only counts
/// if English subtitles show up once it starts.
class VodCandidate {
  final Item item;
  final bool needsSubs;
  const VodCandidate(this.item, this.needsSubs);
}

/// One automatic switch (possibly chained across several accounts).
class VodSwitch {
  VodSwitch({
    required this.original,
    required this.now,
    required this.originalAccount,
    required this.nowAccount,
    required this.needsSubs,
  });
  final Item original; // what you picked
  final Item now; // what's playing instead
  final String originalAccount;
  final String nowAccount;
  final bool needsSubs;
  WatchEntry? originalEntry; // your Continue Watching entry before the switch, for Undo
  final writtenKeys = <String>{};
  bool settled = false;
  DateTime settledAt = DateTime.now();
}

/// Finds the same movie or episode on another account, remembers which account works,
/// keeps Continue Watching to one entry, and supports Undo.
class VodFailover {
  static final lastSwitch = ValueNotifier<VodSwitch?>(null);
  static final changes = ValueNotifier<int>(0);
  static final undone = <int>{}; // items you sent back with Undo (no auto-switch again this time)
  static bool undoing = false;

  static String hkey(Item i) => '${i.accountId}|${i.kind}|${i.streamId.isNotEmpty ? i.streamId : i.url}';

  // ---------- Title matching ----------

  static final _bar = RegExp(r'^\s*\|([^|]{1,12})\|\s*');
  static final _brk = RegExp(r'^\s*[\[(]([^\])]{1,12})[\])]\s*[|:\-–]?\s*');
  static final _code = RegExp(r'^\s*((?:[a-z]{2,4}|4k|8k)(?:-[a-z]{2,3})?)\s*[|:\-–]\s+');
  static final _yParen = RegExp(r'[\(\[]\s*((?:19|20)\d\d)\s*[\)\]]');
  static final _yEnd = RegExp(r'[\s\-–]((?:19|20)\d\d)\s*$');
  static final _anyTag = RegExp(r'[\[(|]\s*([a-z]{2,8}(?:[-_ ][a-z]{2,3})?)\s*[\])|]');
  static final _tags = RegExp(
      r'\b(4k|8k|uhd|fhd|hd|sd|hdr|hdr10|dv|1080p|720p|2160p|480p|hevc|x265|x264|h264|h265|multi|sub|subs|subbed|subtitled|dubbed|dub|vose|vost|vostfr|imax|extended|remastered|uncut|web|webrip|webdl|bluray|bdrip|cam)\b');
  static const _langMap = {
    'en': 'en', 'eng': 'en', 'english': 'en', 'us': 'en', 'usa': 'en', 'uk': 'en', 'gb': 'en', 'au': 'en',
    'es': 'es', 'spa': 'es', 'esp': 'es', 'spanish': 'es', 'lat': 'es', 'latino': 'es', 'latam': 'es',
    'mx': 'es', 'castellano': 'es', 'cast': 'es',
    'fr': 'fr', 'fre': 'fr', 'fra': 'fr', 'french': 'fr', 'vf': 'fr', 'vff': 'fr',
    'de': 'de', 'ger': 'de', 'deu': 'de', 'german': 'de',
    'it': 'it', 'ita': 'it', 'italian': 'it',
    'pt': 'pt', 'por': 'pt', 'br': 'pt', 'portuguese': 'pt',
    'ar': 'ar', 'ara': 'ar', 'arabic': 'ar',
    'tr': 'tr', 'tur': 'tr', 'turkish': 'tr',
    'nl': 'nl', 'dut': 'nl', 'dutch': 'nl',
    'pl': 'pl', 'pol': 'pl', 'polish': 'pl',
    'ru': 'ru', 'rus': 'ru', 'russian': 'ru',
    'hi': 'hi', 'hin': 'hi', 'hindi': 'hi',
  };

  /// "EN - Inception (2010) [4K]" -> title "inception", year 2010, lang "en".
  static TitleKey parse(String name) {
    var s = name.toLowerCase().trim();
    s = s.replaceFirst(RegExp(r'^[^a-z0-9\[(|]+'), ''); // stray leading punctuation ("'EN - Allo 'Allo!")
    final tags = <String>[];
    for (var i = 0; i < 3; i++) {
      final m = _bar.firstMatch(s) ?? _brk.firstMatch(s) ?? _code.firstMatch(s);
      if (m == null) break;
      final rest = s.substring(m.end);
      if (rest.trim().length < 2) break;
      tags.add(m.group(1)!.trim());
      s = rest;
    }
    tags.addAll(_anyTag.allMatches(s).map((m) => m.group(1)!));
    int? year;
    final maxYear = DateTime.now().year + 1;
    final yp = _yParen.firstMatch(s);
    if (yp != null) {
      year = int.parse(yp.group(1)!);
      s = s.replaceRange(yp.start, yp.end, ' ');
    } else {
      final ye = _yEnd.firstMatch(s);
      if (ye != null && int.parse(ye.group(1)!) <= maxYear) {
        year = int.parse(ye.group(1)!);
        s = s.replaceRange(ye.start, ye.end, ' ');
      }
    }
    if (year != null && year > maxYear) year = null;
    s = s.replaceAll(RegExp(r'\[[^\]]*\]|\([^)]*\)|\{[^}]*\}'), ' ');
    s = s.replaceAll('&', ' and ').replaceAll(RegExp(r"['’`]"), '');
    s = s.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
    s = s.replaceAll(_tags, ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.startsWith('the ')) s = s.substring(4);
    String? lang;
    for (final t in tags) {
      for (final part in t.split(RegExp(r'[-_ ]'))) {
        lang ??= _langMap[part];
      }
      if (lang != null) break;
    }
    return (title: s, year: year, lang: lang);
  }

  /// A word to pre-filter the database with (apostrophes kept as gaps so "ocean's" still matches).
  static String _probe(String name) {
    final words = name
        .toLowerCase()
        .replaceAll(RegExp(r'\[[^\]]*\]|\([^)]*\)'), ' ')
        .split(RegExp(r'[^a-z0-9]+'))
        .where((w) => w.length >= 2 && !_tags.hasMatch(w) && !_langMap.containsKey(w))
        .toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    if (words.isNotEmpty) return words.first;
    // Titles made of short or language-like words ("It"): search by the title itself.
    final t = parse(name).title.split(' ')..sort((a, b) => b.length.compareTo(a.length));
    return t.first;
  }

  static int _quality(String name) {
    final n = name.toLowerCase();
    if (RegExp(r'\b(4k|uhd|2160p?)\b').hasMatch(n)) return 4;
    if (RegExp(r'\b(fhd|1080p?)\b').hasMatch(n)) return 3;
    if (RegExp(r'\b(sd|480p?)\b').hasMatch(n)) return 1;
    return 2;
  }

  // ---------- Reliability (fewest recent failures wins) ----------

  static int _cutoff() => DateTime.now().subtract(const Duration(days: 14)).millisecondsSinceEpoch ~/ 1000;

  static int failures(String accountId) {
    final c = _cutoff();
    return (Prefs.getStr('vodfail.$accountId') ?? '').split(',').where((x) => (int.tryParse(x) ?? 0) > c).length;
  }

  static void recordFailure(String accountId) {
    final c = _cutoff();
    final list = (Prefs.getStr('vodfail.$accountId') ?? '').split(',').where((x) => (int.tryParse(x) ?? 0) > c).toList()
      ..add('${DateTime.now().millisecondsSinceEpoch ~/ 1000}');
    while (list.length > 30) {
      list.removeAt(0);
    }
    Prefs.setStr('vodfail.$accountId', list.join(','));
  }

  // ---------- Searching ----------

  static Future<List<({Item item, bool needsSubs, bool exactYear})>> _titleMatches(
    String kind,
    String name,
    Set<String> excludeAccounts,
    Set<String> excludeHosts, {
    String? onlyAccount,
  }) async {
    final want = parse(name);
    final probe = _probe(name);
    if (want.title.isEmpty || probe.isEmpty) return [];
    final db = Services.db;
    final q = db.select(db.items)..where((t) => t.kind.equals(kind) & t.nameLower.like('%$probe%'));
    if (onlyAccount != null) {
      q.where((t) => t.accountId.equals(onlyAccount));
    } else if (excludeAccounts.isNotEmpty) {
      q.where((t) => t.accountId.isNotIn(excludeAccounts.toList()));
    }
    final rows = await q.get();
    final accts = await db.select(db.accounts).get();
    final hostOf = {for (final a in accts) a.id: Uri.tryParse(a.server)?.host ?? ''};
    final out = <({Item item, bool needsSubs, bool exactYear})>[];
    for (final r in rows) {
      if (excludeHosts.contains(hostOf[r.accountId])) continue;
      final k = parse(r.name);
      if (k.title != want.title) continue;
      if (want.year != null && k.year != null && (want.year! - k.year!).abs() > 1) continue;
      out.add((
        item: r,
        needsSubs: want.lang != null && k.lang != null && k.lang != want.lang,
        exactYear: want.year != null && k.year == want.year,
      ));
    }
    // Same language first, then exact year, then the most reliable account, then quality.
    out.sort((a, b) {
      if (a.needsSubs != b.needsSubs) return a.needsSubs ? 1 : -1;
      if (a.exactYear != b.exactYear) return a.exactYear ? -1 : 1;
      final f = failures(a.item.accountId).compareTo(failures(b.item.accountId));
      if (f != 0) return f;
      return _quality(b.item.name).compareTo(_quality(a.item.name));
    });
    return out;
  }

  static final _epRe = RegExp(r'^(.*?)\s{3}S(\d+) E(\d+)(?:\s{2}(.*))?$');

  static ({String show, int season, int number, String title})? _episodeOf(Item item) {
    final m = _epRe.firstMatch(item.name);
    if (m == null) return null;
    return (show: m.group(1)!, season: int.parse(m.group(2)!), number: int.parse(m.group(3)!), title: m.group(4) ?? '');
  }

  static Future<Item?> _findEpisode(Item show, int season, int number, String title) async {
    try {
      final a = await Services.accounts.get(show.accountId);
      if (a == null || a.type != 'xtream') return null;
      final x = XtreamClient(a.server, a.username, await Services.accounts.password(a.id) ?? '');
      final j = await x.seriesInfo(show.streamId);
      final eps = j is Map ? j['episodes'] : null;
      final lists = eps is Map ? eps.values : (eps is List ? [eps] : const []);
      for (final l in lists) {
        if (l is! List) continue;
        for (final e in l.whereType<Map>()) {
          if ((int.tryParse('${e['season'] ?? ''}') ?? -1) != season) continue;
          if ((int.tryParse('${e['episode_num'] ?? ''}') ?? -1) != number) continue;
          final id = '${e['id'] ?? ''}';
          if (id.isEmpty) return null;
          final info = e['info'];
          final img = info is Map ? '${info['movie_image'] ?? ''}' : '';
          final label = 'S$season E$number${title.isEmpty ? '' : '  $title'}';
          return Item(
            id: -(int.tryParse(id) ?? id.hashCode.abs()),
            accountId: show.accountId,
            kind: 'episode',
            name: '${show.name}   $label',
            nameLower: '',
            category: show.category,
            logo: img.isNotEmpty ? img : show.logo,
            streamId: id,
            ext: '${e['container_extension'] ?? 'mp4'}',
            url: '',
            position: 0,
            genre: show.genre,
            country: show.country,
            language: show.language,
          );
        }
      }
    } catch (e) {
      debugPrint('[playback] episode lookup on another account failed: $e');
    }
    return null;
  }

  /// Other accounts that have this movie or episode, best first.
  static Future<List<VodCandidate>> candidates(Item item, Set<String> exclude,
      {Set<String> excludeHosts = const {}}) async {
    final skip = {...exclude, item.accountId};
    if (item.kind == 'movie') {
      final m = await _titleMatches('movie', item.name, skip, excludeHosts);
      final seen = <String>{};
      return [for (final c in m) if (seen.add(c.item.accountId)) VodCandidate(c.item, c.needsSubs)];
    }
    if (item.kind == 'episode') {
      final ep = _episodeOf(item);
      if (ep == null) return [];
      final shows = await _titleMatches('series', ep.show, skip, excludeHosts);
      final out = <VodCandidate>[];
      final seen = <String>{};
      for (final s in shows) {
        if (!seen.add(s.item.accountId)) continue;
        if (seen.length > 4) break; // each check asks the provider for the season list
        final e = await _findEpisode(s.item, ep.season, ep.number, ep.title);
        if (e != null) out.add(VodCandidate(e, s.needsSubs));
      }
      return out;
    }
    return [];
  }

  // ---------- Remembering the account that worked ----------

  static String? _prefKey(Item item) {
    if (item.kind == 'movie') {
      final k = parse(item.name);
      return k.title.isEmpty ? null : 'vodpref.m.${k.title}.${k.year ?? ''}';
    }
    if (item.kind == 'episode') {
      final e = _episodeOf(item);
      if (e == null) return null;
      final k = parse(e.show);
      return k.title.isEmpty ? null : 'vodpref.s.${k.title}.${k.year ?? ''}';
    }
    return null;
  }

  /// If this title worked on a different account last time, the same title there.
  static Future<Item?> preferred(Item item) async {
    final key = _prefKey(item);
    if (key == null) return null;
    final acct = Prefs.getStr(key);
    if (acct == null || acct == item.accountId) return null;
    if (await Services.accounts.get(acct) == null) {
      Prefs.setStr(key, null);
      return null;
    }
    Item? found;
    if (item.kind == 'movie') {
      final m = await _titleMatches('movie', item.name, const {}, const {}, onlyAccount: acct);
      if (m.isNotEmpty) found = m.first.item;
    } else {
      final ep = _episodeOf(item);
      if (ep == null) return null;
      final shows = await _titleMatches('series', ep.show, const {}, const {}, onlyAccount: acct);
      if (shows.isNotEmpty) found = await _findEpisode(shows.first.item, ep.season, ep.number, ep.title);
    }
    if (found != null) debugPrint('[playback] opening ${item.name} on the account that worked last time');
    return found;
  }

  // ---------- Continue Watching: carry, merge, undo ----------

  static Future<WatchEntry?> _entry(String key) {
    final db = Services.db;
    return (db.select(db.history)..where((h) => h.entryKey.equals(key))).getSingleOrNull();
  }

  static Future<void> _write(Item i, int posMs, int durMs) {
    final db = Services.db;
    return db.into(db.history).insertOnConflictUpdate(WatchEntry(
          entryKey: hkey(i),
          accountId: i.accountId,
          kind: i.kind,
          name: i.name,
          logo: i.logo,
          streamId: i.streamId,
          ext: i.ext,
          url: i.url,
          positionMs: posMs,
          durationMs: durMs,
          updatedAt: DateTime.now(),
        ));
  }

  /// Gives the new account your spot (where it failed, or your saved spot).
  static Future<void> carry(VodSwitch s, Item from, Item to, Duration pos, Duration dur) async {
    s.originalEntry ??= await _entry(hkey(s.original));
    var ms = pos.inMilliseconds;
    var durMs = dur.inMilliseconds;
    if (ms < 30000) {
      final e = await _entry(hkey(from));
      if (e != null) {
        ms = e.positionMs;
        durMs = e.durationMs;
      }
    }
    if (ms < 30000) return;
    s.writtenKeys.add(hkey(to));
    await _write(to, ms, durMs);
  }

  /// It's playing: one Continue Watching entry (the working account), and remember it.
  static Future<void> settle(VodSwitch s) async {
    final db = Services.db;
    final keep = hkey(s.now);
    final drop = {hkey(s.original), ...s.writtenKeys}..remove(keep);
    for (final k in drop) {
      await (db.delete(db.history)..where((h) => h.entryKey.equals(k))).go();
    }
    final pk = _prefKey(s.original);
    if (pk != null) Prefs.setStr(pk, s.now.accountId);
    s.settled = true;
    s.settledAt = DateTime.now();
    changes.value++;
    debugPrint('[playback] now on ${s.nowAccount}: Continue Watching follows it, and it opens there next time');
  }

  /// Undo: your original entry back at the current spot, and forget the switch.
  static Future<void> restore(VodSwitch s, Duration pos) async {
    final db = Services.db;
    await (db.delete(db.history)..where((h) => h.entryKey.equals(hkey(s.now)))).go();
    final base = s.originalEntry;
    final ms = pos.inMilliseconds >= 30000 ? pos.inMilliseconds : (base?.positionMs ?? 0);
    if (ms >= 30000 || base != null) await _write(s.original, ms, base?.durationMs ?? 0);
    final pk = _prefKey(s.original);
    if (pk != null) Prefs.setStr(pk, null);
    undone.add(s.original.id);
    lastSwitch.value = null;
    changes.value++;
  }
}

/// "Now playing on Hallo · Undo", shown for 10 seconds after a switch starts playing.
class VodSwitchBanner extends StatefulWidget {
  const VodSwitchBanner({super.key});

  @override
  State<VodSwitchBanner> createState() => _VodSwitchBannerState();
}

class _VodSwitchBannerState extends State<VodSwitchBanner> {
  Timer? _hide;
  late final Listenable _l = Listenable.merge([VodFailover.lastSwitch, VodFailover.changes, Services.playback.current]);

  @override
  void initState() {
    super.initState();
    _l.addListener(_update);
    _update();
  }

  void _update() {
    _hide?.cancel();
    final s = VodFailover.lastSwitch.value;
    if (s != null && s.settled) {
      final left = const Duration(seconds: 10) - DateTime.now().difference(s.settledAt);
      if (left > Duration.zero) _hide = Timer(left, () => mounted ? setState(() {}) : null);
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _l.removeListener(_update);
    _hide?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = VodFailover.lastSwitch.value;
    final cur = Services.playback.current.value;
    if (s == null || !s.settled || cur == null || cur.id != s.now.id) return const SizedBox.shrink();
    if (DateTime.now().difference(s.settledAt) > const Duration(seconds: 10)) return const SizedBox.shrink();
    return Material(
      color: Colors.black87,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Now playing on ${s.nowAccount}', style: const TextStyle(color: Colors.white, fontSize: 13)),
            const SizedBox(width: 6),
            TextButton(
              onPressed: () => Services.playback.undoVodSwitch(),
              child: const Text('Undo', style: TextStyle(color: BMColors.mango, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
