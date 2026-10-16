import 'dart:async';
import 'package:flutter/foundation.dart';
import '../history/history_service.dart';
import '../catalog/catalog_service.dart';
import '../prefs.dart';
import 'server_health.dart';
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
  ServerHealth? health;
  int _openFailsInRow = 0; // reconnects that failed to open at all
  int _busyInRow = 0; // reconnects refused with 403 (account already in use)
  final Set<String> _triedAccounts = {};
  final Set<String> _triedHosts = {}; // servers that already failed for this pick
  final handedOff = ValueNotifier<bool>(false); // playing in VLC instead
  final subsVisible = ValueNotifier<bool>(false);
  double _lastVolume = 100;
  /// The channel you actually picked, when failover switched to a backup (for highlighting).
  Item? failoverOrigin;

  PlaybackService(this.accounts) {
    _applyStartupPrefs();
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
      if (p > const Duration(seconds: 1) && !_started) {
        _started = true;
        _openFailsInRow = 0;
        final h = Uri.tryParse(_lastUrl ?? '')?.host ?? '';
        if (h.isNotEmpty) health?.ok(h);
      }
    });
    // Clear the reconnect badge once video is flowing again.
    player.stream.buffering.listen((b) {
      if (!b && player.state.playing && !_reconnectPending) {
        reconnecting.value = null;
        _openFailsInRow = 0;
        _busyInRow = 0;
      }
    });
  }

  final Player player = Player(configuration: const PlayerConfiguration(logLevel: MPVLogLevel.warn, libass: true));
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
      _triedHosts.clear();
      failoverOrigin = null;
    }
    handedOff.value = false;
    _triedAccounts.add(item.accountId);
    final url = await urlFor(item);
    final host = Uri.tryParse(url)?.host ?? '';
    if (host.isNotEmpty) _triedHosts.add(host);
    // Known-down server: go straight to a backup instead of waiting on it.
    if (!isFailover && item.kind == 'live' && host.isNotEmpty && (health?.isDown(host) ?? false) && catalog != null) {
      current.value = item;
      reconnecting.value = 'Server down, finding a backup...';
      _failoverOrGiveUp(item, 'This server is down right now. Try again later or pick another channel.');
      return;
    }
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
    handedOff.value = false;
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
    final alts = await cat.failoverCandidates(item, _triedAccounts, excludeHosts: {..._triedHosts, ...?health?.downHosts});
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

  Future<void> _applyStartupPrefs() async {
    final np = player.platform;
    if (np is NativePlayer) {
      try {
        await np.setProperty('volume-max', '150');
        // Keep a subtitle track loaded but hidden, so turning subs on is instant.
        // (Switching tracks mid-stream forces a re-read that stalls live streams.)
        await np.setProperty('subs-fallback', 'yes');
        await np.setProperty('slang', Prefs.getStr('subs.lang') ?? 'en,eng');
        subsVisible.value = Prefs.getBool('subs.on');
        await np.setProperty('sub-visibility', subsVisible.value ? 'yes' : 'no');
      } catch (e) {
        debugPrint('[playback] startup settings: $e');
      }
    }
    await player.setVolume(Prefs.getDouble('player.volume') ?? 100);
  }

  /// Show or hide subtitles without switching tracks (no stall).
  Future<void> setSubsVisible(bool on) async {
    subsVisible.value = on;
    Prefs.setBool('subs.on', on);
    final np = player.platform;
    if (np is NativePlayer) await np.setProperty('sub-visibility', on ? 'yes' : 'no');
  }

  /// Pick a subtitle language. Only switches tracks if it's a different one.
  Future<void> chooseSubtitle(SubtitleTrack t) async {
    if (player.state.track.subtitle.id != t.id) await player.setSubtitleTrack(t);
    final lang = t.language;
    if (lang != null && lang.isNotEmpty) {
      Prefs.setStr('subs.lang', lang);
      final np = player.platform;
      if (np is NativePlayer) await np.setProperty('slang', lang);
    }
    await setSubsVisible(true);
  }

  Future<void> setVolume(double v) async {
    await player.setVolume(v);
    if (v > 0) Prefs.setDouble('player.volume', v);
  }

  Future<void> toggleMute() async {
    final v = player.state.volume;
    if (v > 0) {
      _lastVolume = v;
      await player.setVolume(0);
    } else {
      await player.setVolume(_lastVolume <= 0 ? 100 : _lastVolume);
    }
  }

  /// Opening in VLC: movies pause; live hangs up (one-connection accounts) but the panel stays.
  Future<void> handOff() async {
    final cur = current.value;
    if (cur == null) return;
    if (cur.kind == 'live') {
      handedOff.value = true;
      try {
        await player.stop();
      } catch (_) {}
    } else {
      await _saveProgress();
      await player.pause();
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
    if (_shuttingDown || handedOff.value) return;
    final was403 = _last403 != null && DateTime.now().difference(_last403!) < const Duration(seconds: 10);
    if (was403) _busyInRow++;
    // A 403 means the server is up but still holding our old connection: not a dead server.
    if (why.contains('Failed to open') && !was403) {
      final h = Uri.tryParse(_lastUrl ?? '')?.host ?? '';
      if (h.isNotEmpty) health?.fail(h, _lastUrl ?? '');
      _openFailsInRow++;
    }
    final item = current.value;
    final url = _lastUrl;
    if (item == null || url == null || item.kind != 'live' || _reconnectPending) return;
    // Never got going: one retry (covers one-connection-limit providers), then give up clearly.
    if (!_started) {
      // A 403 usually means our old connection is still open, so be patient before failing over.
      final just403 = _last403 != null && DateTime.now().difference(_last403!) < const Duration(seconds: 10);
      if (_startRetries >= (just403 ? 3 : 1)) {
        _failoverOrGiveUp(
            item,
            just403
                ? 'This account is already in use (one connection at a time). Close VLC or other devices using it, then try again.'
                : "This channel isn't working right now. Try another one.");
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
    // Mid-show: if reopening keeps failing outright, the server is gone. Fail over now.
    // Still refused after ~50s of patient retries: something else is using the account.
    if (_busyInRow >= 6) {
      _busyInRow = 0;
      reconnecting.value = 'This account is already in use (one connection at a time). Close VLC or other devices using it, then try again.';
      return;
    }
    if (_openFailsInRow >= 3) {
      _openFailsInRow = 0;
      _failoverOrGiveUp(item, 'Stream unstable. Pick it again or try another channel.');
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
    final waitMs = was403 ? 8000 : backoffMs; // give the provider time to release the old connection
    Future.delayed(Duration(milliseconds: waitMs), () async {
      _reconnectPending = false;
      if (current.value?.id != item.id) return;
      await player.open(Media(url, httpHeaders: {'User-Agent': bmUserAgent}));
      // A reopened stream can come back paused; make sure it plays.
      await player.play();
    });
  }
}
