import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

/// Accounts. Passwords and private playlist links are NOT stored here;
/// they live in the system keychain (see secret_store.dart).
class Accounts extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get type => text()(); // xtream | stalker | m3u
  TextColumn get server => text().withDefault(const Constant(''))();
  TextColumn get username => text().withDefault(const Constant(''))();
  TextColumn get mac => text().withDefault(const Constant(''))();
  IntColumn get liveCount => integer().withDefault(const Constant(0))();
  IntColumn get movieCount => integer().withDefault(const Constant(0))();
  IntColumn get seriesCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Everything an account provides: live channels, movies, and shows.
/// Xtream items store only the stream ID; play links are built at play time
/// so the password never lands in this file.
@TableIndex(name: 'items_account_kind', columns: {#accountId, #kind})
@TableIndex(name: 'items_kind_name', columns: {#kind, #nameLower})
class Items extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get accountId => text()();
  TextColumn get kind => text()(); // live | movie | series
  TextColumn get name => text()();
  TextColumn get nameLower => text()();
  TextColumn get category => text().withDefault(const Constant(''))();
  TextColumn get logo => text().withDefault(const Constant(''))();
  TextColumn get streamId => text().withDefault(const Constant(''))();
  TextColumn get ext => text().withDefault(const Constant(''))();
  TextColumn get url => text().withDefault(const Constant(''))(); // M3U only
  IntColumn get position => integer().withDefault(const Constant(0))();
  TextColumn get genre => text().withDefault(const Constant(''))();
  TextColumn get country => text().withDefault(const Constant(''))();
  TextColumn get language => text().withDefault(const Constant(''))();
}

/// Starred channels, movies, and shows. Keyed by the provider's stream ID
/// (or link for M3U), so favorites survive account reloads.
class Favorites extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get accountId => text()();
  TextColumn get kind => text()(); // live | movie | series
  TextColumn get itemKey => text()();
  TextColumn get name => text()();
  TextColumn get logo => text().withDefault(const Constant(''))();
  DateTimeColumn get addedAt => dateTime()();
}

/// Watch history: recent channels, plus resume positions for movies and episodes.
/// Stores enough to replay a title directly (episodes have no catalog row).
@DataClassName('WatchEntry')
class History extends Table {
  TextColumn get entryKey => text()(); // accountId|kind|streamId-or-url
  TextColumn get accountId => text()();
  TextColumn get kind => text()(); // live | movie | episode | series
  TextColumn get name => text()();
  TextColumn get logo => text().withDefault(const Constant(''))();
  TextColumn get streamId => text().withDefault(const Constant(''))();
  TextColumn get ext => text().withDefault(const Constant(''))();
  TextColumn get url => text().withDefault(const Constant(''))();
  IntColumn get positionMs => integer().withDefault(const Constant(0))();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {entryKey};
}

@DriftDatabase(tables: [Accounts, Items, Favorites, History])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'black_mango'));

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          // Very old database: create everything at once.
          if (from < 2) {
            await m.createAll();
            return;
          }
          // v3 adds genre, country, language. Only adds what's missing.
          if (from < 3) {
            final rows = await customSelect("PRAGMA table_info('items')").get();
            final cols = rows.map((r) => r.read<String>('name')).toSet();
            if (!cols.contains('genre')) await m.addColumn(items, items.genre);
            if (!cols.contains('country')) await m.addColumn(items, items.country);
            if (!cols.contains('language')) await m.addColumn(items, items.language);
          }
          // v4 adds Favorites. Only creates it if it isn't there yet.
          if (from < 4) {
            final t = await customSelect("SELECT name FROM sqlite_master WHERE type='table' AND name='favorites'").get();
            if (t.isEmpty) await m.createTable(favorites);
          }
          // v5 adds History. Only creates it if it isn't there yet.
          if (from < 5) {
            final t = await customSelect("SELECT name FROM sqlite_master WHERE type='table' AND name='history'").get();
            if (t.isEmpty) await m.createTable(history);
          }
        },
      );
}
