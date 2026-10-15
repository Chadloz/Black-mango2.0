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

@DriftDatabase(tables: [Accounts])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'black_mango'));

  @override
  int get schemaVersion => 1;
}
