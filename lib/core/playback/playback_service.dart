import 'dart:async';
import 'package:flutter/foundation.dart';
import '../history/history_service.dart';
import '../catalog/catalog_service.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../storage/database.dart';
import '../accounts/account_repository.dart';
import '../net/fetch.dart';
import '../catalog/details.dart';

/// One shared mpv player for the whole app.
class PlaybackService {
  final AccountRepository accounts;

  /// Set by Services at startup.
  HistoryService? history;
  CatalogService? catalog;
  final Set<String> _triedAccounts = {};
  /// The channel you actually picked, when failover switched to a backup (for highlighting).
  Item? failoverOrigin;

  PlaybackService(this.accounts) {
    // Save movie/episode progress every 10 seconds while playing.
    Timer.periodic(const Duration(seconds: 10), (_) {
      final cur = current.value;
      if (cur != null && cur.kind != 'live' && player.state.playing) _saveProgress();
    });
    // Print mpv's network events (reconnects, drops, timeouts) to the Terminal.
    player.stream.log.listen((l) {
      final t = l.text.toLowerCase();
      if (t.contains('http error 403')) _last403 = DateTime.now();
      if (t.contains('empty segment')) return; // normal for ad-spliced free channels
      if (t.contains('reconnect') || t.contains('http') || t.contains('end of file') || t.contains('timeout') || t.contains('eof')) {
        debugPrint('[mpv] ${l.prefix}: ${l.text.trim()}');
      }
    });
    // Live channels never truly end. If one does, the provider dropped it: reconnect.
    player.stream.completed.listen((done) {
      if (done) _onDropped('ended');
    });
    // Only real failures count. Decoding hiccups like "Error decoding audio" are normal in the
    // first moments of a live stream and mpv recovers on its own. Reopening for them restarts
    // the connection for nothing (and trips one-connection limits).
    player.stream.error.listen((e) {
      final t = e.toLowerCase();
      final fatal = t.contains('failed to open') ||
          t.contains('failed to recognize') ||
          t.contains('loading failed') ||
          t.contains('no video or audio');
      if (fatal) {
        _onDropped('error: $e');
      } else {
        debugPrint('[playback] ignored non-fatal: $e');
      }
    });
    // Once playback passes one second, the stream counts as started.
    player.stream.position.listen((p) {
      if (p > const Duration(seconds: 1)) _started = true;
    });
    // Clear the reconnect badge once video is flowing again.
    player.stream.buffering.listen((b) {
      if (!b && player.state.playing && !_reconnectPending) reconnecting.value = null;
    });
  }

  final Player player = Player(configuration: const PlayerConfiguration(logLevel: MPVLogLevel.warn));
  late final VideoController controller = VideoController(player);

  /// What's playing right now (null = nothing).
  final current = ValueNotifier<Item?>(null);

  /// Reconnect status for the UI (null = all good).
  final reconnecting = ValueNotifier<String?>(null);

  // Passwords cached in memory only, never written anywhere.
  final _passCache = <String, String>{};

  String? _lastUrl;
  bool _started = false; // true once the stream has actually played
  DateTime? _last403;
  bool _shuttingDown = false; // a server just refused us (often the one-connection limit)
  int _startRetries = 0;
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
      case 'episode':
        return '${acct.server}/series/$u/$p/${item.streamId}.${item.ext.isEmpty ? 'mkv' : item.ext}';
      case 'series':
        throw BMError('Pick an episode to play a show.');
      default:
        return '${acct.server}/live/$u/$p/${item.streamId}.ts';
    }
  }

  /// FFmpeg-level reconnect. Live streams also reconnect at "end of file",
  /// since a live channel only "ends" when the provider drops the connection.
  /// Network settings depend on how the stream arrives.
  Future<void> _configureFor(Item item, String url) async {
    final np = player.platform;
    if (np is! NativePlayer) return;
    final path = (Uri.tryParse(url)?.path ?? '').toLowerCase();
    final isEndlessTs = path.endsWith('.ts') || RegExp(r'/\d+$').hasMatch(path);
    final isFile = RegExp(r'\.(mkv|mp4|avi|mov|m4v|wmv|flv|webm)$').hasMatch(path);
    await np.setProperty('network-timeout', '15');
    if (isEndlessTs || isFile) {
      // One continuous download: let FFmpeg reconnect on drops.
      // Live .ts also reconnects at "end of file", since a live channel never truly ends.
      await np.setProperty(
        'stream-lavf-o',
        [
          'reconnect=1',
          'reconnect_streamed=1',
          'reconnect_on_network_error=1',
          'reconnect_delay_max=5',
          if (item.kind == 'live' && isEndlessTs) 'reconnect_at_eof=1',
        ].join(','),
      );
      await np.setProperty('demuxer-lavf-o', '');
    } else {
      // HLS and redirect links: FFmpeg's reused connections fail on many CDNs,
      // so use a fresh connection per segment and retry segments instead.
      await np.setProperty('stream-lavf-o', '');
      await np.setProperty('demuxer-lavf-o', 'http_persistent=0,seg_max_retry=3,max_reload=10');
    }
  }

  Future<void> play(Item item, {bool autoplay = true, bool isFailover = false}) async {
    if (!isFailover) {
      _triedAccounts.clear();
      failoverOrigin = null;
    }
    _triedAccounts.add(item.accountId);
    final url = await urlFor(item);
    await _saveProgress();
    final resumeAt = item.kind == 'live' ? null : await history?.resumePosition(item);
    _recentReconnects.clear();
    _reconnectPending = false;
    _started = false;
    _startRetries = 0;
    reconnecting.value = null;
    _lastUrl = url;
    current.value = item;
    await _configureFor(item, url);
    await player.open(Media(url, httpHeaders: {'User-Agent': bmUserAgent}), play: autoplay);
    if (item.kind == 'live') {
      history?.record(item);
    } else if (resumeAt != null) {
      _seekWhenReady(item, resumeAt);
    }
  }

  /// Plays one episode of a show.
  Future<void> playEpisode(Item show, EpisodeInfo ep) {
    final label = 'S${ep.season} E${ep.number}${ep.title.isEmpty ? '' : '  ${ep.title}'}';
    final item = Item(
      id: -(int.tryParse(ep.id) ?? ep.id.hashCode.abs()),
      accountId: show.accountId,
      kind: 'episode',
      name: '${show.name}   $label',
      nameLower: '',
      category: show.category,
      logo: ep.image.isNotEmpty ? ep.image : show.logo,
      streamId: ep.id,
      ext: ep.ext,
      url: '',
      position: 0,
      genre: show.genre,
      country: show.country,
      language: show.language,
    );
    return play(item);
  }

  /// App is quitting: save progress and hang up cleanly so the provider releases the connection.
  /// Keeps the session info, so the next launch can restore it.
  Future<void> shutdown() async {
    _shuttingDown = true;
    await _saveProgress();
    try {
      await player.stop();
    } catch (_) {}
  }

  Future<void> stop() async {
    await _saveProgress();
    failoverOrigin = null;
    current.value = null;
    reconnecting.value = null;
    _lastUrl = null;
    await player.stop();
  }

  /// Tries the same channel on another account before showing an error.
  Future<void> _failoverOrGiveUp(Item item, String giveUpMsg) async {
    final cat = catalog;
    if (item.kind != 'live' || cat == null || _triedAccounts.length >= 4) {
      reconnecting.value = giveUpMsg;
      return;
    }
    _reconnectPending = true;
    final alts = await cat.failoverCandidates(item, _triedAccounts);
    _reconnectPending = false;
    if (current.value?.id != item.id) return; // you already picked something else
    if (alts.isEmpty) {
      reconnecting.value = giveUpMsg;
      return;
    }
    final alt = alts.first;
    final acctName = (await accounts.get(alt.accountId))?.name ?? 'another account';
    debugPrint('[playback] failover: ${item.name} -> ${alt.name} on $acctName');
    failoverOrigin ??= item;
    try {
      await play(alt, isFailover: true);
      reconnecting.value = 'Trying ${alt.name} on $acctName...';
    } catch (_) {
      reconnecting.value = giveUpMsg;
    }
  }

  Future<void> _saveProgress() async {
    final cur = current.value;
    final h = history;
    if (cur == null || h == null || cur.kind == 'live') return;
    final pos = player.state.position;
    if (pos < const Duration(seconds: 5)) return;
    await h.record(cur, position: pos, duration: player.state.duration);
  }

  /// Jumps to the saved spot once the new file reports its length.
  Future<void> _seekWhenReady(Item item, Duration at) async {
    await Future.delayed(const Duration(milliseconds: 800));
    for (var i = 0; i < 60; i++) {
      if (current.value?.id != item.id) return;
      if (player.state.duration > Duration.zero) {
        await player.seek(at);
        debugPrint('[playback] resumed at ${at.inSeconds}s');
        return;
      }
      await Future.delayed(const Duration(milliseconds: 300));
    }
  }

  /// App-level backup reconnect for live streams, throttled like 1.x.
  void _onDropped(String why) {
    if (_shuttingDown) return;
    final item = current.value;
    final url = _lastUrl;
    if (item == null || url == null || item.kind != 'live' || _reconnectPending) return;
    // Never got going: one retry (covers one-connection-limit providers), then give up clearly.
    if (!_started) {
      // A 403 usually means our old connection is still open, so be patient before failing over.
      final just403 = _last403 != null && DateTime.now().difference(_last403!) < const Duration(seconds: 10);
      if (_startRetries >= (just403 ? 3 : 1)) {
        _failoverOrGiveUp(item, "This channel isn't working right now. Try another one.");
        return;
      }
      _startRetries++;
      _reconnectPending = true;
      reconnecting.value = 'Retrying...';
      debugPrint('[playback] stream did not start ($why), one retry in 2.5s');
      // After a 403, give the provider longer to release the old connection.
      final recent403 = _last403 != null && DateTime.now().difference(_last403!) < const Duration(seconds: 10);
      Future.delayed(Duration(milliseconds: recent403 ? 4000 * _startRetries : 2500), () async {
        _reconnectPending = false;
        if (current.value?.id != item.id) return;
        await player.open(Media(url, httpHeaders: {'User-Agent': bmUserAgent}));
        await player.play();
      });
      return;
    }
    final now = DateTime.now();
    _recentReconnects.removeWhere((t) => now.difference(t) > const Duration(minutes: 1));
    if (_recentReconnects.length >= _maxReconnects) {
      _failoverOrGiveUp(item, 'Stream unstable. Pick it again or try another channel.');
      return;
    }
    _recentReconnects.add(now);
    _reconnectPending = true;
    reconnecting.value = 'Reconnecting (${_recentReconnects.length}/$_maxReconnects)...';
    debugPrint('[playback] live stream $why, reconnecting');
    // Back off: 0.8s, 1.6s, 3.2s, 6.4s, then 8s, so the provider can release the old connection.
    final backoffMs = (800 * (1 << (_recentReconnects.length - 1))).clamp(800, 8000);
    Future.delayed(Duration(milliseconds: backoffMs), () async {
      _reconnectPending = false;
      if (current.value?.id != item.id) return;
      await player.open(Media(url, httpHeaders: {'User-Agent': bmUserAgent}));
      // A reopened stream can come back paused; make sure it plays.
      await player.play();
    });
  }
}
