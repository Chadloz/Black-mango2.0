import 'storage/database.dart';
import 'storage/secret_store.dart';
import 'accounts/account_repository.dart';
import 'catalog/catalog_service.dart';
import 'playback/playback_service.dart';
import 'favorites/favorites_service.dart';

/// App-wide services, created once at startup.
class Services {
  static late final AppDatabase db;
  static late final AccountRepository accounts;
  static late final CatalogService catalog;
  static late final PlaybackService playback;
  static late final FavoritesService favorites;

  static void init() {
    db = AppDatabase();
    accounts = AccountRepository(db, SecretStore());
    catalog = CatalogService(db, accounts);
    playback = PlaybackService(accounts);
    favorites = FavoritesService(db);
  }
}
