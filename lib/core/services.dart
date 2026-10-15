import 'storage/database.dart';
import 'storage/secret_store.dart';
import 'accounts/account_repository.dart';

/// App-wide services, created once at startup.
class Services {
  static late final AppDatabase db;
  static late final AccountRepository accounts;

  static void init() {
    db = AppDatabase();
    accounts = AccountRepository(db, SecretStore());
  }
}
