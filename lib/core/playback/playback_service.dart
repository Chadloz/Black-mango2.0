import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../storage/database.dart';
import '../accounts/account_repository.dart';
import '../net/fetch.dart';

/// One shared mpv player for the whole app.
class PlaybackService {
  final AccountRepository accounts;

  PlaybackService(this.accounts) {
    // Live channels never truly end. If one does, the provider dropped it: reconnect.
    player.stream.completed.listen((done) {
      if (done) _onDropped('ended');
    });
    player.stream.error.listen((e) => _onDropped('error: $e'));
    // Clear the reconnect badge once video is flowing again.
    player.stream.buffering.listen((b) {
      if (!b && player.state.playing && !_reconnectPending) reconnecting.value = null;
    });
  }

  final Player player = Player();
  late final VideoController controller = VideoController(player);

  /// What's playing right now (null = nothing).
  final current = ValueNotifier<Item?>(null);

  /// Reconnect status for the UI (null = all good).
  final reconnecting = ValueNotifier<String?>(null);

  // Passwords cached in memory only, never written anywhere.
  final _passCache = <String, String>{};

  String? _lastUrl;
  bool _reconnectPending = false;
  final List<DateTime> _recentReconnects = [];
  static const _maxReconnects = 8;

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

  /// FFmpeg-level reconnect. Live streams also reconnect at "end of file",
  /// since a live channel only "ends" when the provider drops the connection.
  Future<void> _configureFor(Item item) async {
    final np = player.platform;
    if (np is! NativePlayer) return;
    final live = item.kind == 'live';
    await np.setProperty('network-timeout', '15');
    await np.setProperty(
      'stream-lavf-o',
      [
        'reconnect=1',
        'reconnect_streamed=1',
        'reconnect_on_network_error=1',
        'reconnect_delay_max=5',
        if (live) 'reconnect_at_eof=1',
      ].join(','),
    );
  }

  Future<void> play(Item item) async {
    final url = await urlFor(item);
    _recentReconnects.clear();
    _reconnectPending = false;
    reconnecting.value = null;
    _lastUrl = url;
    current.value = item;
    await _configureFor(item);
    await player.open(Media(url, httpHeaders: {'User-Agent': bmUserAgent}));
  }

  /// App-level backup reconnect for live streams, throttled like 1.x.
  void _onDropped(String why) {
    final item = current.value;
    final url = _lastUrl;
    if (item == null || url == null || item.kind != 'live' || _reconnectPending) return;
    final now = DateTime.now();
    _recentReconnects.removeWhere((t) => now.difference(t) > const Duration(minutes: 1));
    if (_recentReconnects.length >= _maxReconnects) {
      reconnecting.value = 'Stream unstable. Pick it again or try another channel.';
      return;
    }
    _recentReconnects.add(now);
    _reconnectPending = true;
    reconnecting.value = 'Reconnecting (${_recentReconnects.length}/$_maxReconnects)...';
    debugPrint('[playback] live stream $why, reconnecting');
    Future.delayed(const Duration(milliseconds: 800), () async {
      _reconnectPending = false;
      if (current.value?.id != item.id) return;
      await player.open(Media(url, httpHeaders: {'User-Agent': bmUserAgent}));
      // A reopened stream can come back paused; make sure it plays.
      await player.play();
    });
  }
}
