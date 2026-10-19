import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'prefs.dart';
import 'services.dart';
import 'storage/database.dart';

/// One-file backup: accounts (with logins), favorites, watch history, settings.
/// Channel lists aren't included; imported accounts reload from the provider.
class Backup {
  static const _type = XTypeGroup(
    label: 'Black Mango backup',
    extensions: ['json'],
    uniformTypeIdentifiers: ['public.json'],
  );

  static bool _skipKey(String k) => k.startsWith('secret.') || k.startsWith('session.');

  /// Saves a backup where the user picks. Returns the path, or null if cancelled.
  static Future<String?> export() async {
    final d = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final name = 'black-mango-backup-${d.year}-${two(d.month)}-${two(d.day)}.json';
    final loc = await getSaveLocation(suggestedName: name, acceptedTypeGroups: const [_type]);
    if (loc == null) return null;

    final db = Services.db;
    final accounts = <Map<String, dynamic>>[];
    for (final a in await db.select(db.accounts).get()) {
      final m = a.toJson();
      final p = await Services.accounts.password(a.id);
      final u = await Services.accounts.playlistUrl(a.id);
      if (p != null && p.isNotEmpty) m['password'] = p;
      if (u != null && u.isNotEmpty) m['playlistUrl'] = u;
      accounts.add(m);
    }
    final favorites = [
      for (final f in await db.select(db.favorites).get()) (f.toJson()..remove('id')),
    ];
    final history = [for (final h in await db.select(db.history).get()) h.toJson()];
    final settings = <String, Object?>{
      for (final k in Prefs.keys())
        if (!_skipKey(k)) k: Prefs.raw(k),
    };

    final data = {
      'app': 'Black Mango',
      'format': 1,
      'exported': d.toIso8601String(),
      'accounts': accounts,
      'favorites': favorites,
      'history': history,
      'settings': settings,
    };
    var path = loc.path;
    if (!path.toLowerCase().endsWith('.json')) path = '$path.json';
    await File(path).writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    debugPrint('[backup] exported ${accounts.length} accounts, ${favorites.length} favorites, ${history.length} history');
    return path;
  }

  /// Opens and checks a backup file. Null if cancelled; throws on a bad file.
  static Future<Map<String, dynamic>?> pick() async {
    final f = await openFile(acceptedTypeGroups: const [_type]);
    if (f == null) return null;
    final j = jsonDecode(await f.readAsString());
    if (j is! Map<String, dynamic> || j['app'] != 'Black Mango') {
      throw const FormatException("That file isn't a Black Mango backup.");
    }
    return j;
  }

  static int _n(Map<String, dynamic> j, String k) => (j[k] as List?)?.length ?? 0;

  static String describe(Map<String, dynamic> j) =>
      '${_n(j, 'accounts')} accounts, ${_n(j, 'favorites')} favorites, '
      '${_n(j, 'history')} watch history entries, and your settings';

  /// Adds and updates from a backup. Nothing that exists now is deleted.
  /// Returns the imported accounts so they can be reloaded.
  static Future<List<Account>> apply(Map<String, dynamic> j) async {
    final db = Services.db;
    final imported = <Account>[];
    final logins = <(String, String)>[];

    await db.transaction(() async {
      for (final raw in (j['accounts'] as List? ?? const [])) {
        final m = Map<String, dynamic>.from(raw as Map);
        final pass = m.remove('password') as String?;
        final url = m.remove('playlistUrl') as String?;
        final a = Account.fromJson(m);
        await db.into(db.accounts).insertOnConflictUpdate(a);
        if (pass != null) logins.add(('account.${a.id}.password', pass));
        if (url != null) logins.add(('account.${a.id}.url', url));
        imported.add(a);
      }

      final have = {
        for (final f in await db.select(db.favorites).get()) '${f.accountId}|${f.kind}|${f.itemKey}',
      };
      for (final raw in (j['favorites'] as List? ?? const [])) {
        final m = Map<String, dynamic>.from(raw as Map)..['id'] = 0;
        final f = Favorite.fromJson(m);
        if (!have.add('${f.accountId}|${f.kind}|${f.itemKey}')) continue;
        await db.into(db.favorites).insert(FavoritesCompanion.insert(
              accountId: f.accountId,
              kind: f.kind,
              itemKey: f.itemKey,
              name: f.name,
              logo: Value(f.logo),
              addedAt: f.addedAt,
            ));
      }

      for (final raw in (j['history'] as List? ?? const [])) {
        await db.into(db.history).insertOnConflictUpdate(WatchEntry.fromJson(Map<String, dynamic>.from(raw as Map)));
      }
    });

    for (final (k, v) in logins) {
      await Services.accounts.secrets.write(k, v);
    }

    final s = j['settings'];
    if (s is Map) {
      for (final e in s.entries) {
        final k = '${e.key}';
        final v = e.value;
        if (_skipKey(k)) continue;
        if (v is bool) {
          await Prefs.setBool(k, v);
        } else if (v is int) {
          await Prefs.setInt(k, v);
        } else if (v is double) {
          await Prefs.setDouble(k, v);
        } else if (v is String) {
          await Prefs.setStr(k, v);
        } else if (v is List) {
          await Prefs.setSet(k, v.map((x) => '$x').toSet());
        }
      }
    }
    debugPrint('[backup] imported ${imported.length} accounts');
    return imported;
  }

  /// Reloads channel lists for imported accounts, one at a time, in the background.
  static Future<void> reloadAll(List<Account> accts) async {
    for (final a in accts) {
      final fresh = await Services.accounts.get(a.id);
      if (fresh == null) continue;
      try {
        await Services.catalog.load(fresh);
      } catch (e) {
        debugPrint('[backup] reload ${a.name} failed: $e');
      }
    }
  }
}
