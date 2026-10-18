import 'dart:convert';
import 'track_memory.dart';
import 'vod_failover.dart';
import 'ts_relay.dart';
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
      final hm = RegExp(r'http error (\d{3})').firstMatch(t);
      if (hm != null) {
        _lastHttpCode = int.tryParse(hm.group(1)!);
        _lastHttpAt = DateTime.now();
      }
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
        reconnecting.value = null; // a working stream never keeps an old warning
        _logTracks();
        _vodRetries = 0;
        _afterVodStart();
        _ensureWatchers();
        _startFreezeWatch();
        _refreshActiveTracks();
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
  int? _lastHttpCode; // last HTTP error status seen (404, 502...)

  /// Logs the stream's tracks once it starts, e.g. to diagnose a silent channel.
  Future<void> _logTracks() async {
    try {
      final np = player.platform as NativePlayer;
      final n = int.tryParse(await np.getProperty('track-list/count')) ?? 0;
      final parts = <String>[];
      for (var i = 0; i < n && i < 12; i++) {
        final type = await np.getProperty('track-list/$i/type');
        if (type == 'sub') continue;
        final codec = await np.getProperty('track-list/$i/codec');
        final lang = await np.getProperty('track-list/$i/lang');
        final sel = await np.getProperty('track-list/$i/selected');
        final ch = type == 'audio' ? await np.getProperty('track-list/$i/demux-channel-count') : '';
        parts.add('$type $codec${lang.isNotEmpty ? ' [$lang]' : ''}${ch.isNotEmpty ? ' ${ch}ch' : ''}${sel == 'yes' ? ' *' : ''}');
      }
      final vol = await np.getProperty('volume');
      final mute = await np.getProperty('mute');
      debugPrint('[tracks] ${parts.join(' | ')}  (volume $vol, mute $mute)');
    } catch (e) {
      debugPrint('[tracks] could not read: $e');
    }
  }
  DateTime? _lastHttpAt;
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
      // Live .ts: look longer before deciding which tracks exist, so audio that is
      // announced late isn't missed (VLC is more patient here). Stops early when done.
      const deep = false; // tried for a silent channel; didn't help and slowed some starts
      await np.setProperty('demuxer-lavf-probesize', deep ? '20000000' : '5000000');
      await np.setProperty('demuxer-lavf-analyzeduration', deep ? '10' : '0');
    } else {
      // HLS and redirect links: FFmpeg's reused connections fail on many CDNs,
      // so use a fresh connection per segment and retry segments instead.
      await np.setProperty('stream-lavf-o', '');
      await np.setProperty('demuxer-lavf-o', 'http_persistent=0,seg_max_retry=3,max_reload=10');
    }
  }

  Future<void> play(Item item, {bool autoplay = true, bool isFailover = false}) async {
    if (!isFailover) {
      VodFailover.lastSwitch.value = null;
      _vodRetries = 0;
      cancelUpNext(); // a new pick ends any Up next countdown
      if (VodFailover.undoing) {
        VodFailover.undoing = false;
      } else {
        VodFailover.undone.clear();
        if (item.kind == 'movie' || item.kind == 'episode') {
          final pref = await VodFailover.preferred(item);
          if (pref != null) item = pref;
        }
      }
    }
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
      final alts = await catalog!.failoverCandidates(item, _triedAccounts, excludeHosts: {..._triedHosts, ...?health?.downHosts});
      if (alts.isNotEmpty) {
        current.value = item;
        reconnecting.value = 'Server down, finding a backup...';
        _failoverOrGiveUp(item, 'This server is down right now. Try again later or pick another channel.');
        return;
      }
      // No backup anywhere: try this server anyway instead of refusing.
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
    // Begin right at your saved spot (no jump after loading, so no race).
    await _setStart(item.kind == 'live' ? null : resumeAt);
    await _applyTrackPrefs(item);
    await player.open(Media(TsRelay.wrap(url), httpHeaders: {'User-Agent': bmUserAgent}), play: autoplay);
    if (item.kind == 'live') {
      history?.record(item);
    } else if (resumeAt != null) {
      debugPrint('[playback] resuming at ${resumeAt.inSeconds}s');
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
  int _vodRetries = 0;

  /// A movie or episode hit a fatal error: one quiet retry at the same spot, then other accounts.
  void _vodError(Item item, String url, String why) {
    if (_vodRetries < 1) {
      _vodRetries++;
      _reconnectPending = true;
      final pos = player.state.position;
      reconnecting.value = 'Retrying...';
      debugPrint('[playback] ${item.kind} failed ($why), one retry');
      Future.delayed(const Duration(milliseconds: 2500), () async {
        _reconnectPending = false;
        if (current.value?.id != item.id) return;
        if (pos.inSeconds >= 5) {
          await (player.platform as NativePlayer).setProperty('start', '${pos.inSeconds}');
        }
        await player.open(Media(TsRelay.wrap(url), httpHeaders: {'User-Agent': bmUserAgent}));
        await player.play();
      });
      return;
    }
    _vodRetries = 0;
    _vodFailover(item, "This ${item.kind == 'movie' ? 'movie' : 'episode'} won't play on any of your accounts right now.");
  }

  /// Same movie or episode on another account, at the same spot.
  Future<void> _vodFailover(Item item, String giveUpMsg, {bool countFailure = true}) async {
    if (VodFailover.undone.contains(item.id)) {
      // You chose this account with Undo, so don't switch on your behalf.
      final name = (await accounts.get(item.accountId))?.name ?? 'this account';
      reconnecting.value = "This won't play on $name right now. Pick it again to let Black Mango switch accounts.";
      return;
    }
    if (_triedAccounts.length >= 4) {
      reconnecting.value = giveUpMsg;
      return;
    }
    final pos = player.state.position;
    final dur = player.state.duration;
    if (countFailure) VodFailover.recordFailure(item.accountId);
    _reconnectPending = true;
    reconnecting.value = 'Looking for it on your other accounts...';
    final alts = await VodFailover.candidates(item, _triedAccounts,
        excludeHosts: {..._triedHosts, ...?health?.downHosts});
    _reconnectPending = false;
    if (current.value?.id != item.id) return; // you already picked something else
    if (alts.isEmpty) {
      debugPrint('[playback] ${item.kind} failover: no match for ${item.name}');
      reconnecting.value = giveUpMsg;
      return;
    }
    final alt = alts.first;
    final prev = VodFailover.lastSwitch.value;
    final chained = prev != null && prev.now.id == item.id;
    final s = VodSwitch(
      original: chained ? prev.original : item,
      now: alt.item,
      originalAccount: chained ? prev.originalAccount : ((await accounts.get(item.accountId))?.name ?? 'the first account'),
      nowAccount: (await accounts.get(alt.item.accountId))?.name ?? 'another account',
      needsSubs: alt.needsSubs,
    );
    if (chained) {
      s.originalEntry = prev.originalEntry;
      s.writtenKeys.addAll(prev.writtenKeys);
    }
    await VodFailover.carry(s, item, alt.item, pos, dur);
    VodFailover.lastSwitch.value = s;
    debugPrint('[playback] ${item.kind} failover: ${item.name} -> ${alt.item.name} on ${s.nowAccount}'
        '${alt.needsSubs ? ' (other language, checking for English subtitles)' : ''}');
    try {
      await play(alt.item, isFailover: true);
      reconnecting.value = 'Trying it on ${s.nowAccount}...';
    } catch (_) {
      reconnecting.value = giveUpMsg;
    }
  }

  /// A switched movie or episode started: merge Continue Watching, remember the account,
  /// and for another-language versions, make sure English subtitles exist.
  void _afterVodStart() {
    final s = VodFailover.lastSwitch.value;
    final cur = current.value;
    if (s == null || cur == null || s.settled || cur.id != s.now.id) return;
    VodFailover.settle(s);
    if (!s.needsSubs) return;
    Future.delayed(const Duration(seconds: 6), () async {
      if (current.value?.id != cur.id) return;
      if (await _hasEnglishSubs()) return;
      debugPrint('[playback] ${cur.name} is another language without English subtitles; trying the next account');
      _vodFailover(cur, "Couldn't find it in your language on your other accounts.", countFailure: false);
    });
  }

  Future<String> _prop(NativePlayer np, String name) async {
    try {
      return await np.getProperty(name);
    } catch (_) {
      return '';
    }
  }

  Future<bool> _hasEnglishSubs() async {
    final np = player.platform as NativePlayer;
    final n = int.tryParse(await _prop(np, 'track-list/count')) ?? 0;
    for (var i = 0; i < n; i++) {
      if (await _prop(np, 'track-list/$i/type') != 'sub') continue;
      final lang = (await _prop(np, 'track-list/$i/lang')).toLowerCase();
      final title = (await _prop(np, 'track-list/$i/title')).toLowerCase();
      if (lang == 'en' || lang == 'eng' || title.contains('english')) return true;
    }
    return false;
  }

  /// Undo an automatic switch: back to the account you picked, at the current spot.
  Future<void> undoVodSwitch() async {
    final s = VodFailover.lastSwitch.value;
    if (s == null) return;
    final pos = player.state.position;
    await VodFailover.restore(s, pos);
    debugPrint('[playback] undo: back to ${s.originalAccount}');
    VodFailover.undoing = true;
    await play(s.original);
  }

  /// Track defaults for this video: your choice for this show if you made one,
  /// otherwise Settings, otherwise your Mac's language.
  Future<void> _applyTrackPrefs(Item item) async {
    final np = player.platform;
    if (np is! NativePlayer) return;
    final mem = TrackMemory.load(item);
    final mac = TrackMemory.macLang();
    String pick(Object? remembered, String? setting) {
      if (remembered is String && remembered.isNotEmpty) return remembered;
      if (setting != null && setting.isNotEmpty) return setting;
      return mac;
    }
    await np.setProperty('alang', TrackMemory.expand(pick(mem['a'], Prefs.getStr('audio.lang'))));
    await np.setProperty('slang', TrackMemory.expand(pick(mem['s'], Prefs.getStr('subs.lang'))));
    final on = mem['on'] is bool ? mem['on'] as bool : Prefs.getBool('subs.on');
    subsVisible.value = on;
    await np.setProperty('sub-visibility', on ? 'yes' : 'no');
    if (mem.isNotEmpty) debugPrint('[tracks] using your saved choice for this show: $mem');
    // Live buffer: hold a few seconds in reserve before starting a channel, so short
    // provider stalls are absorbed instead of becoming skips. Movies don't need it.
    final buf = item.kind == 'live' ? (Prefs.getInt('live.buffer') ?? 3) : 0;
    await np.setProperty('cache-pause-initial', buf > 0 ? 'yes' : 'no');
    await np.setProperty('cache-pause-wait', '${buf > 0 ? buf : 1}');
  }

  /// Track menu: pick an audio track (remembered for this show).
  Future<void> chooseAudio(AudioTrack t) async {
    await player.setAudioTrack(t);
    TrackMemory.save(current.value, audio: t.language ?? '');
  }

  /// Track menu: subtitles off (remembered for this show).
  Future<void> subsOff() async {
    subsVisible.value = false;
    final np = player.platform;
    if (np is NativePlayer) await np.setProperty('sub-visibility', 'no');
    TrackMemory.save(current.value, subsOn: false);
  }

  // ---------- Remote-style controls ----------

  /// Skip within a movie or episode (negative = back).
  Future<void> skip(int secs) async {
    final s = player.state;
    var t = s.position + Duration(seconds: secs);
    if (t < Duration.zero) t = Duration.zero;
    if (s.duration > Duration.zero && t > s.duration) t = s.duration - const Duration(seconds: 1);
    await player.seek(t);
  }

  Future<void> restartCurrent() => player.seek(Duration.zero);

  Future<void> nextEpisode() => _stepEpisode(1);
  Future<void> prevEpisode() => _stepEpisode(-1);

  Future<void> _stepEpisode(int step) async {
    final cur = current.value;
    if (cur == null || cur.kind != 'episode') return;
    final n = await VodFailover.neighborEpisode(cur, step);
    if (current.value?.id != cur.id) return;
    if (n == null) {
      final msg = step > 0 ? 'That was the last episode.' : 'This is the first episode.';
      reconnecting.value = msg;
      Future.delayed(const Duration(seconds: 3), () {
        if (reconnecting.value == msg) reconnecting.value = null;
      });
      return;
    }
    cancelUpNext();
    await play(n);
  }

  /// "Up next" after an episode ends: 10-second countdown, then the next episode.
  final upNext = ValueNotifier<Item?>(null);
  final upNextIn = ValueNotifier<int>(0);
  Timer? _upNextTimer;

  void cancelUpNext() {
    _upNextTimer?.cancel();
    _upNextTimer = null;
    if (upNext.value != null) upNext.value = null;
  }

  Future<void> playUpNext() async {
    final n = upNext.value;
    cancelUpNext();
    if (n != null) await play(n);
  }

  Future<void> _onEnded() async {
    final cur = current.value;
    if (cur == null || cur.kind != 'episode' || upNext.value != null) return;
    final next = await VodFailover.neighborEpisode(cur, 1);
    if (next == null || current.value?.id != cur.id) return;
    debugPrint('[playback] episode ended, up next: ${next.name}');
    upNextIn.value = 10;
    upNext.value = next;
    _upNextTimer?.cancel();
    _upNextTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (current.value?.id != cur.id) {
        cancelUpNext();
        return;
      }
      upNextIn.value = upNextIn.value - 1;
      if (upNextIn.value <= 0) playUpNext();
    });
  }

  // ---------- Which tracks are actually playing (Track menu checkmarks) ----------

  String activeAudioId = '';
  String activeSubId = '';
  final trackTick = ValueNotifier<int>(0);
  bool _watching = false;

  void _ensureWatchers() {
    if (_watching) return;
    _watching = true;
    player.stream.completed.listen((done) {
      if (done) _onEnded();
    });
    player.stream.track.listen((_) => _refreshActiveTracks());
    player.stream.tracks.listen((_) => _refreshActiveTracks());
  }

  Future<void> _refreshActiveTracks() async {
    final np = player.platform;
    if (np is! NativePlayer) return;
    activeAudioId = await _prop(np, 'current-tracks/audio/id');
    activeSubId = await _prop(np, 'current-tracks/sub/id');
    trackTick.value++;
  }

  // ---------- Frozen-picture watchdog ----------
  // Ad-supported channels splice in ads on different track IDs. If the player stays on a
  // video track that stopped receiving data, the picture freezes while audio continues.
  // Signal: mpv recalculates video-bitrate and audio-bitrate from the data arriving for the
  // selected tracks (at keyframes). Video's number frozen 12s while audio's keeps changing
  // = starved video track.
  // Prefs 'watchdog.act' = true lets it recover (newest video track, then reopen).
  // Off by default: it only logs, so we can prove it before it acts.

  Timer? _freezeTimer;
  String? _wdVbr;
  String? _wdAbr;
  DateTime _wdVideoMoved = DateTime.now();
  DateTime _wdAudioMoved = DateTime.now();
  int _wdStage = 0;
  int? _wdItemId;
  bool _wdNoticed = false;
  final List<DateTime> _wdRecoveries = [];

  void _startFreezeWatch() {
    _freezeTimer ??= Timer.periodic(const Duration(seconds: 1), (_) => _freezeTick());
  }

  void _wdReset() {
    _wdVbr = null;
    _wdAbr = null;
    _wdVideoMoved = DateTime.now();
    _wdAudioMoved = DateTime.now();
    _wdNoticed = false;
  }

  Future<void> _freezeTick() async {
    final cur = current.value;
    final st = player.state;
    final np = player.platform;
    if (cur == null || np is! NativePlayer || !st.playing || st.buffering || _reconnectPending) {
      _wdReset();
      return;
    }
    if (_wdItemId != cur.id) {
      _wdItemId = cur.id;
      _wdStage = 0;
      _wdReset();
      return;
    }
    if ((await _prop(np, 'current-tracks/video/id')).isEmpty) return; // radio / audio-only
    if (await _prop(np, 'current-tracks/video/albumart') == 'yes') return; // still cover image
    final vbr = await _prop(np, 'video-bitrate');
    final abr = await _prop(np, 'audio-bitrate');
    final now = DateTime.now();
    if (vbr != _wdVbr) {
      if (_wdVbr != null) _wdStage = 0;
      _wdVbr = vbr;
      _wdVideoMoved = now;
      _wdNoticed = false;
    }
    if (abr != _wdAbr) {
      _wdAbr = abr;
      _wdAudioMoved = now;
    }
    final videoStale = now.difference(_wdVideoMoved) >= const Duration(seconds: 12);
    final audioFresh = now.difference(_wdAudioMoved) < const Duration(seconds: 4);
    if (!videoStale || !audioFresh || abr.isEmpty) return;

    if (!Prefs.getBool('watchdog.act')) {
      if (!_wdNoticed) {
        _wdNoticed = true;
        debugPrint('[playback] watchdog (watching only): picture may be frozen on ${cur.name} '
            '(video data unchanged 12s while audio flows). If the picture really froze, tell Claude.');
      }
      return;
    }

    // Acting mode. Don't loop forever on a channel that's simply broken.
    _wdRecoveries.removeWhere((t) => now.difference(t) > const Duration(minutes: 1));
    if (_wdRecoveries.length >= 3) return;
    if (_wdStage == 0) {
      _wdStage = 1;
      _wdRecoveries.add(now);
      final n = int.tryParse(await _prop(np, 'track-list/count')) ?? 0;
      var newest = -1;
      for (var i = 0; i < n; i++) {
        if (await _prop(np, 'track-list/$i/type') != 'video') continue;
        if (await _prop(np, 'track-list/$i/albumart') == 'yes') continue;
        final id = int.tryParse(await _prop(np, 'track-list/$i/id')) ?? -1;
        if (id > newest) newest = id;
      }
      final curId = int.tryParse(await _prop(np, 'current-tracks/video/id')) ?? -1;
      if (newest > 0 && newest != curId) {
        debugPrint('[playback] picture froze while audio continued; switching to the newest video track ($curId -> $newest)');
        await np.setProperty('vid', '$newest');
        _wdReset();
        return;
      }
    }
    if (_wdStage == 1) {
      _wdStage = 2;
      _wdRecoveries.add(now);
      _wdReset();
      final url = _lastUrl;
      if (url == null) return;
      debugPrint('[playback] picture still frozen; reopening the stream');
      final tpos = double.tryParse(await _prop(np, 'time-pos'));
      if (cur.kind != 'live' && tpos != null && tpos > 5) {
        await np.setProperty('start', '${tpos.floor()}');
      }
      await player.open(Media(TsRelay.wrap(url), httpHeaders: {'User-Agent': bmUserAgent}));
      await player.play();
    }
  }

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
        final alang = Prefs.getStr('audio.lang');
        if (alang != null && alang.isNotEmpty) await np.setProperty('alang', alang);
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
    subsVisible.value = true;
    final np = player.platform;
    if (np is NativePlayer) await np.setProperty('sub-visibility', 'yes');
    // Remembered for this show; Settings stays your everyday default.
    TrackMemory.save(current.value, sub: t.language ?? '', subsOn: true);
  }

  Future<void> setAudioLang(String codes) async {
    Prefs.setStr('audio.lang', codes.isEmpty ? null : codes);
    final np = player.platform;
    if (np is NativePlayer) await np.setProperty('alang', codes);
  }

  Future<void> setSubLang(String codes) async {
    Prefs.setStr('subs.lang', codes);
    final np = player.platform;
    if (np is NativePlayer) await np.setProperty('slang', codes);
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
    // Hang up completely, movies included: a paused stream still holds the connection,
    // and many providers refuse a second one. Your spot is saved, so Resume picks back up.
    if (cur.kind != 'live') await _saveProgress();
    handedOff.value = true;
    try {
      await player.stop();
    } catch (_) {}
  }

  /// mpv's start position for the next file (null = from the top).
  Future<void> _setStart(Duration? at) async {
    final np = player.platform;
    if (np is! NativePlayer) return;
    try {
      await np.setProperty('start', at == null ? 'none' : '${at.inSeconds}');
    } catch (e) {
      debugPrint('[playback] start position: $e');
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
    // A 4xx answer (404 missing channel, 403 busy) proves the server is up: don't count it as down.
    final code = _lastHttpCode ?? 0;
    final was4xx = _lastHttpAt != null &&
        DateTime.now().difference(_lastHttpAt!) < const Duration(seconds: 10) &&
        code >= 400 &&
        code < 500;
    if (why.contains('Failed to open') && !was403 && !was4xx) {
      final h = Uri.tryParse(_lastUrl ?? '')?.host ?? '';
      if (h.isNotEmpty) health?.fail(h, _lastUrl ?? '');
      _openFailsInRow++;
    }
    final item = current.value;
    final url = _lastUrl;
    if (item == null || url == null || _reconnectPending) return;
    if (item.kind == 'movie' || item.kind == 'episode') {
      _vodError(item, url, why);
      return;
    }
    if (item.kind != 'live') return;
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
        await player.open(Media(TsRelay.wrap(url), httpHeaders: {'User-Agent': bmUserAgent}));
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
      await player.open(Media(TsRelay.wrap(url), httpHeaders: {'User-Agent': bmUserAgent}));
      // A reopened stream can come back paused; make sure it plays.
      await player.play();
    });
  }
}
