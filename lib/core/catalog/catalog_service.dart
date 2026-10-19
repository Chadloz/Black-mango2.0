import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import '../storage/database.dart';
import '../accounts/account_repository.dart';
import '../net/fetch.dart';
import '../providers/xtream.dart';
import '../providers/m3u.dart';
import '../providers/stalker.dart';
import 'classifier.dart';
import 'details.dart';
import 'name_match.dart';
import '../prefs.dart';

/// Builds database rows from an Xtream list. Top-level so it can run on a background worker.
List<ItemsCompanion> buildXtreamRows(String accountId, String kind, List<Map> list, Map<String, String> cats,
    String idKey, String logoKey, String? extKey) {
  final rows = <ItemsCompanion>[];
  for (var i = 0; i < list.length; i++) {
    final m = list[i];
    final name = '${m['name'] ?? ''}'.trim();
    if (name.isEmpty) continue;
    final category = cats['${m['category_id']}'] ?? '';
    final c = kind == 'live' ? classify(category, name) : classifyVod(category, name);
    rows.add(ItemsCompanion.insert(
      accountId: accountId,
      kind: kind,
      name: name,
      nameLower: name.toLowerCase(),
      category: Value(category),
      logo: Value('${m[logoKey] ?? ''}'),
      streamId: Value('${m[idKey] ?? ''}'),
      ext: Value(extKey == null ? '' : '${m[extKey] ?? ''}'),
      position: Value(i),
      genre: Value(c.genre),
      country: Value(c.country),
      language: Value(c.language),
    ));
  }
  return rows;
}

/// Builds live channel rows from a Stalker channel list. Top-level for the background worker.
/// The portal's command for each channel is kept in extra; play links are made at play time.
List<ItemsCompanion> buildStalkerLiveRows(String accountId, String api, List<Map> list, Map<String, String> genres) {
  final rows = <ItemsCompanion>[];
  for (var i = 0; i < list.length; i++) {
    final m = list[i];
    final name = '${m['name'] ?? ''}'.trim();
    final cmd = '${m['cmd'] ?? ''}'.trim();
    if (name.isEmpty || cmd.isEmpty) continue;
    final category = genres['${m['tv_genre_id'] ?? ''}'] ?? '';
    final c = classify(category, name);
    rows.add(ItemsCompanion.insert(
      accountId: accountId,
      kind: 'live',
      name: name,
      nameLower: name.toLowerCase(),
      category: Value(category),
      logo: Value(stalkerLogo('${m['logo'] ?? ''}', api)),
      streamId: Value('${m['id'] ?? ''}'),
      position: Value(i),
      genre: Value(c.genre),
      country: Value(c.country),
      language: Value(c.language),
      extra: Value(jsonEncode({'cmd': cmd})),
    ));
  }
  return rows;
}

/// Parses an M3U playlist into database rows. Top-level for the background worker.
List<ItemsCompanion> buildM3uRows(String accountId, String text) {
  final entries = parseM3u(text);
  final rows = <ItemsCompanion>[];
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    final kind = kindFromUrl(e.url);
    final c = kind == 'live' ? classify(e.group, e.name) : classifyVod(e.group, e.name);
    rows.add(ItemsCompanion.insert(
      accountId: accountId,
      kind: kind,
      name: e.name,
      nameLower: e.name.toLowerCase(),
      category: Value(e.group),
      logo: Value(e.logo),
      url: Value(e.url),
      position: Value(i),
      genre: Value(c.genre),
      country: Value(c.country),
      language: Value(c.language),
    ));
  }
  return rows;
}

// Background workers. Top-level on purpose: a closure made inside a CatalogService method
// can carry the whole service (and its open database) along with it, and that can't be
// sent to another isolate ("object is unsendable"). Here the closure holds only its inputs.
Future<List<ItemsCompanion>> _xtreamRowsInBackground(String id, String kind, List<Map> list, Map<String, String> cats,
        String idKey, String logoKey, String? extKey) =>
    Isolate.run(() => buildXtreamRows(id, kind, list, cats, idKey, logoKey, extKey));

Future<List<ItemsCompanion>> _m3uRowsInBackground(String id, String text) => Isolate.run(() => buildM3uRows(id, text));

Future<List<ItemsCompanion>> _stalkerRowsInBackground(String id, String api, List<Map> list, Map<String, String> genres) =>
    Isolate.run(() => buildStalkerLiveRows(id, api, list, genres));

/// Loads an account's channels, movies, and shows, and answers list queries.
class CatalogService {
  final AppDatabase db;
  final AccountRepository accounts;
  CatalogService(this.db, this.accounts);

  /// accountId -> progress message, only while that account is loading.
  final status = ValueNotifier<Map<String, String>>({});

  void _set(String id, String? msg) {
    final m = Map<String, String>.from(status.value);
    if (msg == null) {
      m.remove(id);
    } else {
      m[id] = msg;
    }
    status.value = m;
  }

  // ---------- Queries ----------

  Expression<bool> _filter(String kind,
      {Set<String>? accountIds, String? genre, Set<String>? countries, Set<String>? languages, String query = ''}) {
    final t = db.items;
    Expression<bool> p = t.kind.equals(kind);
    if (accountIds != null && accountIds.isNotEmpty) p = p & t.accountId.isIn(accountIds);
    if (genre != null) p = p & t.genre.equals(genre);
    if (countries != null && countries.isNotEmpty) p = p & t.country.isIn(countries);
    if (languages != null && languages.isNotEmpty) p = p & t.language.isIn(languages);
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty) p = p & t.nameLower.like('%$q%');
    return p;
  }

  Future<List<String>> _distinct(GeneratedColumn<String> col, Expression<bool> where) async {
    final q = db.selectOnly(db.items, distinct: true)
      ..addColumns([col])
      ..where(where & col.isNotValue(''))
      ..orderBy([OrderingTerm.asc(col)]);
    final rows = await q.get();
    return rows.map((r) => r.read(col) ?? '').where((s) => s.isNotEmpty).toList();
  }

  Future<List<String>> countries(String kind, {Set<String>? accountIds}) =>
      _distinct(db.items.country, _filter(kind, accountIds: accountIds));

  Future<List<String>> languages(String kind, {Set<String>? accountIds}) =>
      _distinct(db.items.language, _filter(kind, accountIds: accountIds));

  /// Genres that exist under the current account/country/language filters, in a fixed order.
  Future<List<String>> genres(String kind, {Set<String>? accountIds, Set<String>? countries, Set<String>? languages}) async {
    final found = await _distinct(
        db.items.genre, _filter(kind, accountIds: accountIds, countries: countries, languages: languages));
    final order = kind == 'live' ? genreOrder : movieGenreOrder;
    return [for (final g in order) if (found.contains(g)) g];
  }

  Future<List<Item>> items(String kind,
      {Set<String>? accountIds, String? genre, Set<String>? countries, Set<String>? languages, String query = '', bool byName = false}) {
    final where = _filter(kind,
        accountIds: accountIds, genre: genre, countries: countries, languages: languages, query: query);
    return (db.select(db.items)
          ..where((_) => where)
          ..orderBy(byName
              ? [(x) => OrderingTerm.asc(x.nameLower)]
              : [(x) => OrderingTerm.asc(x.accountId), (x) => OrderingTerm.asc(x.position)]))
        .get();
  }

  /// Movie or show info (plot, cast, episodes...). Xtream only; M3U has no extra info.
  Future<Details> details(Item item) async {
    final d = Details()..poster = item.logo;
    if (item.url.isNotEmpty) return d;
    final acct = await accounts.get(item.accountId);
    if (acct == null || acct.type != 'xtream') return d;
    final pass = await accounts.password(acct.id) ?? '';
    final x = XtreamClient(acct.server, acct.username, pass);
    final series = item.kind == 'series';
    final j = series ? await x.seriesInfo(item.streamId) : await x.vodInfo(item.streamId);
    return parseDetails(j, d, series: series);
  }

  /// The same live channel on other accounts, same country first, one per account.
  Future<List<Item>> failoverCandidates(Item item, Set<String> exclude, {Set<String> excludeHosts = const {}}) async {
    final target = normName(item.name);
    if (target.isEmpty) return [];
    final words = target.split(' ')..sort((a, b) => b.length.compareTo(a.length));
    final token = words.first;
    if (token.length < 2) return [];
    final rows = await (db.select(db.items)
          ..where((x) => x.kind.equals('live') & x.accountId.isNotIn(exclude) & x.nameLower.like('%$token%'))
          ..limit(500))
        .get();
    final matches = rows.where((r) => normName(r.name) == target).toList();
    // Same country, or at least the same language: a Spanish feed shouldn't switch to an English one.
    if (item.language.isNotEmpty) {
      matches.removeWhere((r) => r.country != item.country && r.language != item.language);
    }
    matches.sort((a, b) => (a.country == item.country ? 0 : 1).compareTo(b.country == item.country ? 0 : 1));
    // Accounts on a server that already failed share its outage, so skip them.
    if (excludeHosts.isNotEmpty) {
      final accts = await db.select(db.accounts).get();
      final hostOf = {for (final a in accts) a.id: Uri.tryParse(a.server)?.host ?? ''};
      matches.removeWhere((m) => excludeHosts.contains(hostOf[m.accountId]));
    }
    final seen = <String>{};
    return [for (final m in matches) if (seen.add(m.accountId)) m];
  }

  // ---------- Test and load ----------

  /// Checks a login before saving. Returns a message, throws on failure.
  Future<String> testInputs({
    required String type,
    String server = '',
    String username = '',
    String password = '',
    String url = '',
    String mac = '',
    String serial = '',
    String deviceId = '',
  }) async {
    if (type == 'stalker') {
      if (server.isEmpty || mac.trim().isEmpty) throw BMError('Enter the portal URL and MAC address.');
      final c = StalkerClient(server, StalkerIdentity(mac, serial: serial, deviceId: deviceId));
      await c.ensure();
      final exp = await c.expiry();
      final where = Uri.parse(c.api!).path;
      final expText = exp == null
          ? 'no expiration listed'
          : 'expires ${DateTime.fromMillisecondsSinceEpoch(exp * 1000).toLocal().toString().split(' ').first}';
      return 'Connected through $where, $expText.';
    }
    if (type == 'xtream') {
      final r = await XtreamClient(server, username, password).test();
      if (!r.ok) throw BMError(r.message);
      return 'Connected. ${r.message}';
    }
    if (type == 'm3u') {
      final text = await fetchText(Uri.parse(url), timeout: const Duration(minutes: 2));
      final n = RegExp(r'#EXTINF', caseSensitive: false).allMatches(text).length;
      if (n == 0) throw BMError('Downloaded, but it does not look like an M3U playlist.');
      return 'Playlist OK: $n entries.';
    }
    throw BMError('Unknown account type.');
  }

  /// Downloads everything for an account and replaces what was stored.
  Future<String> load(Account a) async {
    if (status.value.containsKey(a.id)) return 'Already loading.';
    try {
      _set(a.id, 'Starting...');
      final rows = <ItemsCompanion>[];
      final id = a.id;
      Set<String>? onlyKinds; // Stalker: reload live channels only; cached movies and shows stay
      if (a.type == 'xtream') {
        final pass = await accounts.password(a.id) ?? '';
        final x = XtreamClient(a.server, a.username, pass);
        final exp = await x.expiry();
        if (exp != null && exp > 0) Prefs.setInt('acct.${a.id}.exp', exp);

        _set(id, 'Loading live channels...');
        final live = await x.list('get_live_streams');
        final liveCats = await x.categories('get_live_categories');
        _set(id, 'Sorting live channels...');
        rows.addAll(await _xtreamRowsInBackground(id, 'live', live, liveCats, 'stream_id', 'stream_icon', null));

        _set(id, 'Loading movies...');
        final vod = await x.list('get_vod_streams');
        final vodCats = await x.categories('get_vod_categories');
        _set(id, 'Sorting movies...');
        rows.addAll(await _xtreamRowsInBackground(id, 'movie', vod, vodCats, 'stream_id', 'stream_icon', 'container_extension'));

        _set(id, 'Loading shows...');
        final series = await x.list('get_series');
        final seriesCats = await x.categories('get_series_categories');
        _set(id, 'Sorting shows...');
        rows.addAll(await _xtreamRowsInBackground(id, 'series', series, seriesCats, 'series_id', 'cover', null));
      } else if (a.type == 'm3u') {
        final url = await accounts.playlistUrl(a.id) ?? '';
        if (url.isEmpty) throw BMError('No playlist link saved for this account.');
        _set(id, 'Downloading playlist...');
        final text = await fetchText(Uri.parse(url), timeout: const Duration(minutes: 3));
        _set(id, 'Reading playlist...');
        rows.addAll(await _m3uRowsInBackground(id, text));
      } else if (a.type == 'stalker') {
        final s = StalkerHub.of(a);
        _set(id, 'Connecting to the portal...');
        await s.ensure();
        final exp = await s.expiry();
        if (exp != null && exp > 0) Prefs.setInt('acct.${a.id}.exp', exp);
        _set(id, 'Loading live channels...');
        final genres = await s.liveGenres();
        final list = await s.liveChannels(progress: (done, total) => _set(id, 'Loading live channels ($done/$total)...'));
        _set(id, 'Sorting live channels...');
        final api = s.api ?? '';
        rows.addAll(await _stalkerRowsInBackground(id, api, list, genres));
        onlyKinds = {'live'};
      } else {
        throw BMError('Unknown account type.');
      }
      _set(id, 'Saving ${rows.length} items...');
      await _replace(id, rows, kinds: onlyKinds);
      if (onlyKinds != null) {
        final liveN = await _count(id, 'live');
        await accounts.updateCounts(id, liveN, await _count(id, 'movie'), await _count(id, 'series'));
        return 'Loaded $liveN live channels. Movies and shows load by category when you open them.';
      }
      final live = rows.where((r) => r.kind.value == 'live').length;
      final movies = rows.where((r) => r.kind.value == 'movie').length;
      final shows = rows.where((r) => r.kind.value == 'series').length;
      await accounts.updateCounts(id, live, movies, shows);
      return 'Loaded $live live, $movies movies, $shows shows.';
    } finally {
      _set(a.id, null);
    }
  }

  Future<int> _count(String accountId, String kind) async {
    final n = db.items.id.count();
    final q = db.selectOnly(db.items)
      ..addColumns([n])
      ..where(db.items.accountId.equals(accountId) & db.items.kind.equals(kind));
    return (await q.getSingle()).read(n) ?? 0;
  }

  /// Replaces an account's stored items (only the given kinds, if set).
  Future<void> _replace(String accountId, List<ItemsCompanion> rows, {Set<String>? kinds}) async {
    final only = kinds;
    await db.transaction(() async {
      await (db.delete(db.items)
            ..where((t) => only == null ? t.accountId.equals(accountId) : (t.accountId.equals(accountId) & t.kind.isIn(only))))
          .go();
      for (var i = 0; i < rows.length; i += 5000) {
        final chunk = rows.sublist(i, min(i + 5000, rows.length));
        await db.batch((b) => b.insertAll(db.items, chunk));
      }
    });
  }
}
