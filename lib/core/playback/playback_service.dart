import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../storage/database.dart';
import '../accounts/account_repository.dart';
import '../net/fetch.dart';

/// One shared mpv player for the whole app.
class PlaybackService {
  final AccountRepository accounts;
  PlaybackService(this.accounts);

  final Player player = Player();
  late final VideoController controller = VideoController(player);

  /// What's playing right now (null = nothing).
  final current = ValueNotifier<Item?>(null);

  // Passwords cached in memory only, never written anywhere.
  final _passCache = <String, String>{};

  /// Builds the play link at play time, so Xtream passwords stay in the Keychain.
  Future<String> urlFor(Item item) async {
    if (item.url.isNotEmpty) return item.url;
    final acct = await accounts.get(item.accountId);
    if (acct == null) throw BMError('That account no longer exists.');
    final pass = _passCache[acct.id] ??= (await accounts.password(acct.id) ?? '');
    final u = Uri.encodeComponent(acct.username);
    final p = Uri.encodeComponent(pass);
    switch (item.kind) {
      case 'movie':
        return '${acct.server}/movie/$u/$p/${item.streamId}.${item.ext.isEmpty ? 'mp4' : item.ext}';
      case 'series':
        throw BMError('Pick an episode to play a show.');
      default:
        return '${acct.server}/live/$u/$p/${item.streamId}.ts';
    }
  }

  Future<void> play(Item item) async {
    final url = await urlFor(item);
    current.value = item;
    await player.open(Media(url, httpHeaders: {'User-Agent': bmUserAgent}));
  }
}
