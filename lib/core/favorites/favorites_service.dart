import 'package:drift/drift.dart';
import '../storage/database.dart';

/// A stable identity for a title across account reloads.
String favKey(Item i) => '${i.accountId}|${i.kind}|${i.streamId.isNotEmpty ? i.streamId : i.url}';

class FavoritesService {
  final AppDatabase db;
  FavoritesService(this.db);

  /// Live set of favorite keys, for drawing stars.
  Stream<Set<String>> watchKeys() => db.select(db.favorites).watch().map(
        (rows) => {for (final f in rows) '${f.accountId}|${f.kind}|${f.itemKey}'},
      );

  Future<void> toggle(Item item) async {
    final k = item.streamId.isNotEmpty ? item.streamId : item.url;
    Expression<bool> match(Favorites f) =>
        f.accountId.equals(item.accountId) & f.kind.equals(item.kind) & f.itemKey.equals(k);
    final existing = await (db.select(db.favorites)..where(match)).get();
    if (existing.isNotEmpty) {
      await (db.delete(db.favorites)..where(match)).go();
    } else {
      await db.into(db.favorites).insert(FavoritesCompanion.insert(
            accountId: item.accountId,
            kind: item.kind,
            itemKey: k,
            name: item.name,
            logo: Value(item.logo),
            addedAt: DateTime.now(),
          ));
    }
  }

  /// Favorites matched to current catalog items, newest first.
  Future<List<Item>> items() async {
    final favs = await (db.select(db.favorites)..orderBy([(f) => OrderingTerm.desc(f.addedAt)])).get();
    if (favs.isEmpty) return [];
    final keys = favs.map((f) => f.itemKey).toSet();
    final rows = await (db.select(db.items)..where((t) => t.streamId.isIn(keys) | t.url.isIn(keys))).get();
    final byKey = {for (final r in rows) favKey(r): r};
    final out = <Item>[];
    for (final f in favs) {
      final it = byKey['${f.accountId}|${f.kind}|${f.itemKey}'];
      if (it != null) out.add(it);
    }
    return out;
  }
}
