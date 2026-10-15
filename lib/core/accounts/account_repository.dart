import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../storage/database.dart';
import '../storage/secret_store.dart';

/// Saves, lists, renames, and deletes accounts.
class AccountRepository {
  final AppDatabase db;
  final SecretStore secrets;
  AccountRepository(this.db, this.secrets);

  Stream<List<Account>> watchAll() =>
      (db.select(db.accounts)..orderBy([(a) => OrderingTerm.asc(a.createdAt)])).watch();

  Future<Account?> get(String id) =>
      (db.select(db.accounts)..where((a) => a.id.equals(id))).getSingleOrNull();

  Future<String> add({
    required String type,
    required String name,
    String server = '',
    String username = '',
    String password = '',
    String mac = '',
    String url = '',
  }) async {
    final id = const Uuid().v4();
    if (password.isNotEmpty) await secrets.write(_passKey(id), password);
    if (url.isNotEmpty) await secrets.write(_urlKey(id), url);
    await db.into(db.accounts).insert(AccountsCompanion.insert(
      id: id,
      name: name,
      type: type,
      server: Value(server),
      username: Value(username),
      mac: Value(mac),
      createdAt: DateTime.now(),
    ));
    return id;
  }

  Future<void> rename(String id, String name) async {
    await (db.update(db.accounts)..where((a) => a.id.equals(id))).write(AccountsCompanion(name: Value(name)));
  }

  Future<void> updateCounts(String id, int live, int movies, int series) async {
    await (db.update(db.accounts)..where((a) => a.id.equals(id))).write(AccountsCompanion(
      liveCount: Value(live),
      movieCount: Value(movies),
      seriesCount: Value(series),
    ));
  }

  Future<void> delete(String id) async {
    await (db.delete(db.items)..where((t) => t.accountId.equals(id))).go();
    await (db.delete(db.accounts)..where((a) => a.id.equals(id))).go();
    await secrets.delete(_passKey(id));
    await secrets.delete(_urlKey(id));
  }

  Future<String?> password(String id) => secrets.read(_passKey(id));
  Future<String?> playlistUrl(String id) => secrets.read(_urlKey(id));

  static String _passKey(String id) => 'account.$id.password';
  static String _urlKey(String id) => 'account.$id.url';
}
