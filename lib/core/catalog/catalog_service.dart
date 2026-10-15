import 'dart:isolate';
import 'dart:math';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import '../storage/database.dart';
import '../accounts/account_repository.dart';
import '../net/fetch.dart';
import '../providers/xtream.dart';
import '../providers/m3u.dart';
import 'classifier.dart';

/// Builds database rows from an Xtream list. Top-level so it can run on a background worker.
List<ItemsCompanion> buildXtreamRows(String accountId, String kind, List<Map> list, Map<String, String> cats,
    String idKey, String logoKey, String? extKey) {
  final rows = <ItemsCompanion>[];
  for (var i = 0; i < list.length; i++) {
    final m = list[i];
    final name = '${m['name'] ?? ''}'.trim();
    if (name.isEmpty) continue;
    final category = cats['${m['category_id']}'] ?? '';
    final c = classify(category, name);
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

/// Parses an M3U playlist into database rows. Top-level for the background worker.
List<ItemsCompanion> buildM3uRows(String accountId, String text) {
  final entries = parseM3u(text);
  final rows = <ItemsCompanion>[];
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    final c = classify(e.group, e.name);
    rows.add(ItemsCompanion.insert(
      accountId: accountId,
      kind: kindFromUrl(e.url),
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
    return [for (final g in genreOrder) if (found.contains(g)) g];
  }

  Future<List<Item>> items(String kind,
      {Set<String>? accountIds, String? genre, Set<String>? countries, Set<String>? languages, String query = ''}) {
    final where = _filter(kind,
        accountIds: accountIds, genre: genre, countries: countries, languages: languages, query: query);
    return (db.select(db.items)
          ..where((_) => where)
          ..orderBy([(x) => OrderingTerm.asc(x.accountId), (x) => OrderingTerm.asc(x.position)]))
        .get();
  }

  // ---------- Test and load ----------

  /// Checks a login before saving. Returns a message, throws on failure.
  Future<String> testInputs({
    required String type,
    String server = '',
    String username = '',
    String password = '',
    String url = '',
  }) async {
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
    throw BMError('Testing Stalker portals is coming in a later step.');
  }

  /// Downloads everything for an account and replaces what was stored.
  Future<String> load(Account a) async {
    if (status.value.containsKey(a.id)) return 'Already loading.';
    try {
      _set(a.id, 'Starting...');
      final rows = <ItemsCompanion>[];
      final id = a.id;
      if (a.type == 'xtream') {
        final pass = await accounts.password(a.id) ?? '';
        final x = XtreamClient(a.server, a.username, pass);

        _set(id, 'Loading live channels...');
        final live = await x.list('get_live_streams');
        final liveCats = await x.categories('get_live_categories');
        _set(id, 'Sorting live channels...');
        rows.addAll(await Isolate.run(() => buildXtreamRows(id, 'live', live, liveCats, 'stream_id', 'stream_icon', null)));

        _set(id, 'Loading movies...');
        final vod = await x.list('get_vod_streams');
        final vodCats = await x.categories('get_vod_categories');
        _set(id, 'Sorting movies...');
        rows.addAll(await Isolate.run(
            () => buildXtreamRows(id, 'movie', vod, vodCats, 'stream_id', 'stream_icon', 'container_extension')));

        _set(id, 'Loading shows...');
        final series = await x.list('get_series');
        final seriesCats = await x.categories('get_series_categories');
        _set(id, 'Sorting shows...');
        rows.addAll(await Isolate.run(() => buildXtreamRows(id, 'series', series, seriesCats, 'series_id', 'cover', null)));
      } else if (a.type == 'm3u') {
        final url = await accounts.playlistUrl(a.id) ?? '';
        if (url.isEmpty) throw BMError('No playlist link saved for this account.');
        _set(id, 'Downloading playlist...');
        final text = await fetchText(Uri.parse(url), timeout: const Duration(minutes: 3));
        _set(id, 'Reading playlist...');
        rows.addAll(await Isolate.run(() => buildM3uRows(id, text)));
      } else {
        throw BMError('Loading Stalker portals is coming in a later step.');
      }
      _set(id, 'Saving ${rows.length} items...');
      await _replace(id, rows);
      final live = rows.where((r) => r.kind.value == 'live').length;
      final movies = rows.where((r) => r.kind.value == 'movie').length;
      final shows = rows.where((r) => r.kind.value == 'series').length;
      await accounts.updateCounts(id, live, movies, shows);
      return 'Loaded $live live, $movies movies, $shows shows.';
    } finally {
      _set(a.id, null);
    }
  }

  Future<void> _replace(String accountId, List<ItemsCompanion> rows) async {
    await db.transaction(() async {
      await (db.delete(db.items)..where((t) => t.accountId.equals(accountId))).go();
      for (var i = 0; i < rows.length; i += 5000) {
        final chunk = rows.sublist(i, min(i + 5000, rows.length));
        await db.batch((b) => b.insertAll(db.items, chunk));
      }
    });
  }
}
