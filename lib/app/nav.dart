import 'package:flutter/foundation.dart';
import '../core/storage/database.dart';

/// App-wide navigation: which sidebar section is showing, and "open this title" requests.
class AppNav {
  static const home = 0, live = 1, movies = 2, shows = 3, favorites = 4, accounts = 5, settings = 6;
  static final index = ValueNotifier<int>(0);
  static final select = ValueNotifier<Item?>(null);
}
