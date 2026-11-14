import 'dart:async';
import 'package:flutter/foundation.dart';
import '../accounts/account_parser.dart';
import '../prefs.dart';
import '../services.dart';
import '../storage/database.dart';
import 'free_packs.dart';

/// Keeps free channel packs fresh. Their links change often (the services rotate them), and a
/// pack used to load once, when you added it, and never again: that's how a months-old link
/// ended up failing. Now a pack more than a day old reloads quietly in the background, a minute
/// after Black Mango opens and every 6 hours while it stays open. One pack at a time, with a
/// pause between them: each reload makes Live TV re-read its list, and seven in a row made the
/// app feel slow (test build 8). Your own accounts are never touched by this.
class PackRefresh {
  static const _every = Duration(hours: 24);
  static bool _running = false;

  static void start() {
    // Well after launch, so it never competes with the app opening or the channel you resumed.
    Timer(const Duration(seconds: 60), run);
    Timer.periodic(const Duration(hours: 6), (_) => run());
  }

  static String _key(String accountId) => 'pack.$accountId.at';

  /// Marks a pack as loaded just now (when you add it, and after each refresh).
  static void stamp(String accountId) => Prefs.setInt(_key(accountId), DateTime.now().millisecondsSinceEpoch);

  static Future<void> run() async {
    if (_running) return;
    _running = true;
    try {
      final accts = await Services.db.select(Services.db.accounts).get();
      for (final a in accts) {
        if (a.type != 'm3u' || !a.username.startsWith('pack:')) continue;
        final at = Prefs.getInt(_key(a.id));
        if (at != null && DateTime.now().millisecondsSinceEpoch - at < _every.inMilliseconds) continue;
        // Never reload the pack you're watching: its channel list would change under the player.
        if (Services.playback.current.value?.accountId == a.id) continue;
        await _refresh(a);
        await Future.delayed(const Duration(seconds: 20)); // let the app breathe before the next one
      }
    } catch (e) {
      debugPrint('[packs] refresh stopped: $e');
    } finally {
      _running = false;
    }
  }

  static Future<void> _refresh(Account a) async {
    final pack = freePackById(a.username.substring(5));
    if (pack == null) {
      debugPrint("[packs] ${a.name}: this pack's list has closed, so it can't refresh. Remove it in Accounts.");
      stamp(a.id); // once a day is enough for that reminder
      return;
    }
    try {
      // A pack whose list moved gets the new address.
      if (await Services.accounts.playlistUrl(a.id) != pack.url) {
        await Services.accounts.setPlaylist(a.id, pack.url, normalizeServer(hostOf(pack.url)));
        debugPrint('[packs] ${a.name}: its list has a new address');
      }
      final fresh = await Services.accounts.get(a.id) ?? a;
      // A list that suddenly has under a quarter of its channels has probably closed: keep yours.
      final had = a.liveCount + a.movieCount + a.seriesCount;
      final msg = await Services.catalog.load(fresh, minRows: had ~/ 4);
      stamp(a.id);
      debugPrint('[packs] ${a.name} refreshed: $msg');
    } catch (e) {
      // Not stamped: it tries again at the next check (6 hours, or the next time the app opens).
      debugPrint('[packs] ${a.name}: refresh failed ($e); keeping the channels you have');
    }
  }
}
