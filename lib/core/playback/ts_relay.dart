import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../prefs.dart';

/// A tiny relay on 127.0.0.1 for live .ts channels. It does three things:
///
/// 1. Dolby fix: some channels label Dolby Digital Plus audio with the ATSC stream type
///    0x87, which the bundled FFmpeg skips (silent channel). The relay relabels it 0x81
///    in the track table and re-signs the table's checksum.
/// 2. Seamless reconnects: when the provider hangs up mid-stream, the relay reconnects
///    to the provider itself and keeps the player's connection open, so the player sees
///    one continuous stream instead of a break.
/// 3. No repeats: after a reconnect, providers often re-send footage already delivered.
///    The relay drops anything at or before the last timestamp it passed along, and
///    stitches the stream's packet counters back into an unbroken sequence.
///
/// Provider status codes pass through unchanged (403 busy, 404, 5xx), and the provider
/// connection closes the moment the player hangs up (one-connection accounts).
///
/// Stalker links expire within minutes, so a Stalker stream comes with a [refresh]
/// function and every reconnect asks the portal for a fresh link instead of reusing one.
class TsRelay {
  /// Called each time a live stream loses footage at a reconnect (the picture jumps), with how
  /// many jumps there have been in the last 2 minutes. Playback decides what to do: try the
  /// channel as HLS, switch accounts, or just say so.
  static void Function(int jumps)? onJumps;

  /// Called each time a live stream's provider drops the connection and the relay reconnects.
  static void Function()? onDrop;

  /// Providers that never take us back on the same server after a drop (every try "busy"):
  /// skip that step for them, since waiting on it only makes each reconnect slower.
  static final _noSameServer = <String>{};

  static HttpServer? _server;
  static final _urls = <String, _Target>{};
  static int _next = 0;
  static final _pending = <Object, void Function()>{}; // requests still waiting on the provider's answer
  static final _owners = <String, (Object, void Function())>{}; // Stalker account -> its one request

  /// Cancels every request still waiting on a provider's answer. Called when you pick something
  /// else, so a request you walked away from can't hold a one-connection account's slot.
  static void cancelPending() {
    for (final stop in List.of(_pending.values)) {
      stop();
    }
  }

  static Future<void> start() async {
    if (_server != null) return;
    try {
      final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      s.listen(_handle, onError: (e) => debugPrint('[relay] server error: $e'));
      _server = s;
      debugPrint('[relay] ready');
    } catch (e) {
      debugPrint('[relay] could not start, playing channels directly: $e');
    }
  }

  static bool _isLiveTs(String url) {
    final u = Uri.tryParse(url);
    if (u == null || !u.scheme.startsWith('http')) return false;
    final p = u.path.toLowerCase();
    if (p.contains('/movie/') || p.contains('/series/')) return false;
    return p.endsWith('.ts') || (p.contains('/live/') && RegExp(r'/\d+$').hasMatch(p));
  }

  /// The URL the player should open. Live .ts goes through the relay; everything else is untouched.
  /// [live] marks a stream known to be live MPEG-TS even when its link doesn't look like one (Stalker).
  /// [group] (a Stalker account) allows one request at a time: a new one closes the previous.
  static String wrap(String url, {bool live = false, Future<String> Function()? refresh, String? group}) {
    final s = _server;
    if (s == null || Prefs.getBool('relay.off') || !(live || _isLiveTs(url))) return url;
    final id = '${_next++}';
    _urls[id] = _Target(url, refresh, group);
    if (_urls.length > 40) _urls.remove(_urls.keys.first);
    return 'http://127.0.0.1:${s.port}/r/$id.ts';
  }

  static Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    final seg = req.uri.pathSegments;
    final id = seg.length == 2 && seg[0] == 'r' ? seg[1].replaceAll('.ts', '') : '';
    final t = _urls[id];
    if (t == null) {
      res.statusCode = HttpStatus.notFound;
      await res.close();
      return;
    }
    final stalker = t.refresh != null;
    final name = _label(t.url);
    if (t.dead) {
      // Already proved dead here: don't ask its server again (that only extends a lockout).
      // 410 tells the player it's gone, so playback switches to a backup.
      res.statusCode = 410;
      await res.close();
      return;
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12)
      ..autoUncompress = false;
    Socket? socket;
    var closed = false;
    final key = Object();
    final group = t.group;
    // Closes both sides. Called the moment the player hangs up, we give up, or a newer request
    // for the same Stalker account takes over, so the provider's connection slot is freed right away.
    void shutdown() {
      if (closed) return;
      closed = true;
      client.close(force: true);
      socket?.destroy();
      _pending.remove(key);
      if (group != null && _owners[group]?.$1 == key) _owners.remove(group);
    }

    _pending[key] = shutdown;
    // One connection per Stalker account: a new request (another channel, or the player's own
    // retry) closes the previous one instead of queueing behind it at the provider.
    if (group != null) {
      final prev = _owners[group];
      if (prev != null) {
        debugPrint('[relay] $name: closing this account\'s previous request first (one connection at a time)');
        prev.$2();
      }
      _owners[group] = (key, shutdown);
    }

    // Stalker links are good for one connection. When the player asks for the same stream
    // again (it reconnects on its own sometimes), get a fresh link instead of the spent one.
    if (stalker && t.used) {
      try {
        t.url = await t.refresh!();
      } catch (e) {
        debugPrint('[relay] could not get a fresh link: ${_why(e)}');
      }
    }
    t.used = true;
    if (closed) {
      // A newer request took over while we were getting the link.
      try {
        await res.close();
      } catch (_) {}
      return;
    }
    var target = t.url;
    debugPrint('[relay] stream $name via relay');
    final asked = DateTime.now();
    var sentTotal = 0;
    // The stream server the provider sent us to (after its redirect). Providers run a pool of
    // servers whose clocks don't match; asking the provider's address again on a reconnect can
    // land on a different one, and the picture jumps. So reconnect to the same server first.
    Uri? sticky;
    String? stickyHost;
    var moved = false; // the last reconnect landed on a different server than before

    final providerHost = Uri.tryParse(t.url)?.host ?? '';

    Future<HttpClientResponse?> sameServer() async {
      final u = sticky;
      if (u == null) return null;
      if (_noSameServer.contains(providerHost)) {
        sticky = null;
        return null;
      }
      var busyTries = 0;
      // Right after a drop the server often still counts our old connection and says "busy"
      // (509, 407, 403) for a moment: give it a few tries before going back to the provider.
      for (var attempt = 0; attempt < 3 && !closed; attempt++) {
        if (attempt > 0) await Future.delayed(const Duration(milliseconds: 1500));
        if (closed) return null;
        try {
          final up = await client.getUrl(u);
          for (final h in const ['user-agent', 'accept']) {
            final v = req.headers.value(h);
            if (v != null) up.headers.set(h, v);
          }
          final r = await up.close().timeout(const Duration(seconds: 6));
          if (r.statusCode < 400) {
            if (attempt > 0) debugPrint('[relay] $name: back on the same server');
            return r;
          }
          r.listen((_) {}).cancel();
          final busy = r.statusCode == 509 || r.statusCode == 407 || r.statusCode == 403;
          if (!busy) {
            debugPrint('[relay] $name: the same server said ${r.statusCode}; asking the provider again');
            break;
          }
          busyTries++;
          debugPrint('[relay] $name: the same server is still busy (${r.statusCode})');
        } catch (e) {
          debugPrint('[relay] $name: the same server didn\'t answer (${_why(e)}); asking the provider again');
          break;
        }
      }
      if (busyTries >= 3 && providerHost.isNotEmpty) {
        _noSameServer.add(providerHost);
        debugPrint('[relay] $name: this provider never takes us back on the same server; '
            'going straight to it from now on');
      }
      sticky = null; // its link has probably expired: start over from the provider
      return null;
    }

    void remember(HttpClientResponse r, String asked) {
      if (r.statusCode >= 400 || r.redirects.isEmpty) return;
      var u = Uri.parse(asked);
      for (final hop in r.redirects) {
        u = u.resolveUri(hop.location);
      }
      if (stickyHost != null && stickyHost != u.host) {
        moved = true;
        debugPrint('[relay] $name: the provider moved us to another server (${u.host})');
      }
      sticky = u;
      stickyHost = u.host;
    }

    Future<HttpClientResponse> open({bool fresh = false}) async {
      if (fresh && t.refresh == null) {
        final same = await sameServer();
        if (same != null) return same;
      }
      final refresh = t.refresh;
      if (fresh && refresh != null) {
        try {
          target = await refresh();
        } catch (e) {
          debugPrint('[relay] $name could not get a fresh link: ${_why(e)}');
        }
      }
      final up = await client.getUrl(Uri.parse(target));
      for (final h in const ['user-agent', 'accept']) {
        final v = req.headers.value(h);
        if (v != null) up.headers.set(h, v);
      }
      // Live Stalker streams can't seek, and their servers want a plain request: no Range.
      if (!fresh && !stalker) {
        final range = req.headers.value('range');
        if (range != null) up.headers.set('range', range);
      }
      final began = DateTime.now();
      // A busy Stalker server can sit on a request for ~45 s before saying no (509): stop at 55.
      // A Stalker channel that hasn't answered within 12 s counts as down on this account.
      final r = stalker ? await up.close().timeout(_stalkerStart) : await up.close();
      if (!stalker) remember(r, target);
      if (stalker) {
        // Diagnostics for Stalker: what the stream server answered (never the link itself).
        final hops = r.redirects.isEmpty ? '' : ', redirected to ${r.redirects.last.location.host}';
        debugPrint('[relay] $name: server answered ${r.statusCode} '
            '${r.headers.value('content-type') ?? '-'}, length ${r.contentLength}, '
            'in ${DateTime.now().difference(began).inMilliseconds} ms$hops');
      }
      return r;
    }

    try {
      var r = await open();
      if (stalker && r.statusCode == 407) {
        t.dead = true;
        debugPrint('[relay] $name: locked out (HTTP 407); treating this channel as down on this account');
        r.listen((_) {}).cancel();
        res.statusCode = 410;
        await res.close();
        shutdown();
        return;
      }
      res.statusCode = r.statusCode;
      res.reasonPhrase = r.reasonPhrase;
      // Live only: no range headers, so the player never tries to jump around in a channel.
      for (final h in const ['content-type']) {
        final v = r.headers.value(h);
        if (v != null) res.headers.set(h, v);
      }
      if (r.statusCode >= 400) {
        // Pass the provider's answer (403 busy, 404, 5xx...) straight to the player.
        debugPrint('[relay] $name: provider refused (HTTP ${r.statusCode})');
        await res.close();
        shutdown();
        return;
      }
      // Stalker: some channels answer and then send nothing at all. Wait for the first video
      // before telling the player the stream is good, so a dead channel fails fast and cleanly.
      Stream<List<int>> src = r;
      if (stalker) {
        final it = StreamIterator<List<int>>(r);
        // Whatever is left of the 12 s start window (at least a second) for the first video.
        var left = _stalkerStart - DateTime.now().difference(asked);
        if (left < const Duration(seconds: 1)) left = const Duration(seconds: 1);
        final got = await it.moveNext().timeout(left, onTimeout: () => false);
        if (!got || closed) {
          if (!closed) {
            t.dead = true;
            debugPrint('[relay] $name: server answered but sent no video; treating this channel as down on this account');
            res.statusCode = 410;
            await res.close();
          }
          await it.cancel();
          shutdown();
          return;
        }
        src = _startingWith(it.current, it);
      }
      res.persistentConnection = false;
      final seamless = r.contentLength < 0; // live streams have no fixed length
      // Always hand the player an open-ended stream. Some channels are really a looping video file
      // with a fixed size; given that size, the player tries to jump to the end and loops on reconnects.
      res.headers.chunkedTransferEncoding = false; // plain stream until either side closes
      final s = await res.detachSocket(writeHeaders: true);
      socket = s;
      // Write errors (the player hung up mid-write) surface here; handled by the loop below.
      s.done.then((_) {}, onError: (_) {});
      _pending.remove(key); // answered: no longer waiting on the provider
      // The player hanging up (channel change, stop, close) shows up as its socket closing.
      s.listen((_) {}, onDone: () {
        if (stalker && !closed) {
          debugPrint('[relay] $name: player hung up after ${(sentTotal / 1000).toStringAsFixed(0)} KB, '
              '${DateTime.now().difference(asked).inMilliseconds} ms');
        }
        shutdown();
      }, onError: (_) => shutdown(), cancelOnError: true);

      final jumps = <DateTime>[];
      final filter = _TsFilter(
        onDolby: () => debugPrint('[relay] Dolby Digital Plus audio relabeled so it plays'),
        onResume: (m) => debugPrint('[relay] $name reconnected: $m'),
        onJump: () {
          final now = DateTime.now();
          jumps
            ..add(now)
            ..removeWhere((t) => now.difference(t) > const Duration(minutes: 2));
          TsRelay.onJumps?.call(jumps.length);
        },
      );
      var quickEnds = 0;
      var silentRuns = 0; // reconnects in a row where the server answered but sent nothing
      while (!closed) {
        final started = DateTime.now();
        var bytes = 0;
        var pending = 0;
        try {
          // A provider that goes silent for 8 seconds counts as a hang-up.
          await for (final chunk in src.timeout(const Duration(seconds: 8))) {
            if (closed) break;
            if (stalker && sentTotal == 0 && bytes == 0) {
              debugPrint('[relay] $name: first data after ${DateTime.now().difference(asked).inMilliseconds} ms');
            }
            bytes += chunk.length;
            final o = filter.process(chunk);
            if (o.isNotEmpty) {
              s.add(o);
              pending += o.length;
              sentTotal += o.length;
            }
            if (pending > (1 << 20)) {
              pending = 0;
              await s.flush();
            }
          }
        } catch (_) {
          // Provider stalled, or the player hung up mid-write.
        }
        if (closed) break;
        final secs = DateTime.now().difference(started).inMilliseconds / 1000;
        debugPrint('[relay] provider ended $name after ${secs.toStringAsFixed(0)}s '
            '(${(bytes / 1e6).toStringAsFixed(1)} MB)${seamless ? '; reconnecting' : ''}');
        if (!seamless) break;
        TsRelay.onDrop?.call();
        // Answering and then sending nothing, three times running: the channel is down here.
        // Mark it so the player gets a clear "gone" (410) and switches to a backup within seconds.
        silentRuns = bytes == 0 ? silentRuns + 1 : 0;
        if (silentRuns >= 3) {
          t.dead = true;
          debugPrint('[relay] $name: server keeps answering with no video; treating this channel as down on this account');
          break;
        }
        quickEnds = secs < 3 ? quickEnds + 1 : 0;
        if (quickEnds >= 5) {
          debugPrint('[relay] $name keeps dropping; handing it back to the player');
          break;
        }
        HttpClientResponse? next;
        for (var attempt = 0; attempt < 4 && !closed && next == null; attempt++) {
          await Future.delayed(Duration(milliseconds: attempt == 0 ? 300 : 1500));
          if (closed) break;
          try {
            final rr = await open(fresh: true);
            if (rr.statusCode < 400) {
              next = rr;
            } else {
              debugPrint('[relay] $name reconnect refused (HTTP ${rr.statusCode})');
              rr.listen((_) {}).cancel();
              if (stalker && rr.statusCode == 407) {
                // Locked out: more links only extend it. Hand back to playback for a backup.
                t.dead = true;
                break;
              }
            }
          } catch (e) {
            debugPrint('[relay] $name reconnect failed: ${_why(e)}');
          }
        }
        if (next == null) break;
        // A different server's frames don't build on the old server's: hold for a full frame.
        filter.markReconnect(newServer: moved);
        moved = false;
        r = next;
        src = next;
      }
      if (!closed) {
        final rest = filter.flush();
        if (rest.isNotEmpty) s.add(rest);
        try {
          await s.flush();
        } catch (_) {}
      }
    } catch (e) {
      if (stalker) {
        // Never print the error's link: it carries a play token.
        debugPrint(closed
            ? '[relay] $name: cancelled (you moved on)'
            : '[relay] $name: error ${e is HttpException ? e.message : e.runtimeType}');
      }
      // Provider unreachable before anything was sent: report it as a server problem.
      if (!closed && socket == null) {
        final noAnswer = stalker && e is TimeoutException;
        if (noAnswer) {
          // Nothing within 12 s: down on this account, same as no video or a 407 (410 to the player).
          t.dead = true;
          debugPrint('[relay] $name: no answer within 12 s; treating this channel as down on this account');
        } else {
          debugPrint('[relay] provider unreachable: ${_why(e)}');
        }
        try {
          res.statusCode = noAnswer ? 410 : HttpStatus.badGateway;
          await res.close();
        } catch (_) {}
      }
    } finally {
      shutdown();
      if (socket == null) {
        // Never got to streaming (cancelled or failed): make sure the player's request is answered.
        try {
          await res.close();
        } catch (_) {}
      }
    }
  }
}

/// A stream to relay, and (for Stalker) how to get a fresh link for it.
class _Target {
  String url;
  final Future<String> Function()? refresh;
  final String? group; // Stalker account: one request at a time
  bool used = false; // a Stalker link is spent once the provider has been asked for it
  bool dead = false; // Stalker: this channel proved dead on this account (no video, or a 407 lockout)
  _Target(this.url, this.refresh, this.group);
}

/// How long a Stalker channel gets to answer and send its first video before it counts as down.
const _stalkerStart = Duration(seconds: 12);

/// [first], then the rest of [it]: a stream we already peeked into.
Stream<List<int>> _startingWith(List<int> first, StreamIterator<List<int>> it) async* {
  yield first;
  while (await it.moveNext()) {
    yield it.current;
  }
}

/// An error's reason without any link in it: stream links carry the MAC and a play token.
String _why(Object e) => '$e'.split(', uri =').first.replaceAll(RegExp(r'https?://\S+'), '<link>');

/// A short name for logs: the channel number from a stream link, never its credentials.
String _label(String url) {
  try {
    final u = Uri.parse(url);
    final s = u.queryParameters['stream'];
    if (s != null && s.isNotEmpty) return s;
    return u.pathSegments.isEmpty ? u.host : u.pathSegments.last;
  } catch (_) {
    return 'stream';
  }
}

/// Walks 188-byte TS packets: relabels Dolby (0x87 -> 0x81) in the track table, and right
/// after a provider reconnect drops footage already delivered, then stops as soon as the
/// stream has caught up. Normal playback is never touched. Compares DECODE timestamps,
/// which always move forward (display timestamps don't, with B-frames).
class _TsFilter {
  _TsFilter({required this.onDolby, required this.onResume, required this.onJump});
  final VoidCallback onDolby;
  final void Function(String) onResume;
  final VoidCallback onJump; // a reconnect that lost footage (the picture jumps forward)

  static const _videoTypes = {0x01, 0x02, 0x1B, 0x24};

  final _pmtPids = <int>{};
  final _esPids = <int>{};
  int? _videoPid;
  int? _videoType; // stream type from the track table: 0x1B H.264, 0x24 HEVC, 0x01/0x02 MPEG
  final _overlap = <int>{}; // tracks whose replay after a reconnect overlapped what we'd sent (no gap)
  bool _waitKey = false; // after a gap: hold the picture until the next full frame (no blocks)
  int _heldFrames = 0;
  final _lastTs = <int, int>{}; // per track: last decode timestamp passed along (90 kHz)
  final _catching = <int>{}; // tracks still skipping replayed footage after a reconnect
  final _dropping = <int, bool>{};
  final _outCc = <int, int>{};
  int _reconnects = 0;
  Uint8List _carry = Uint8List(0);
  bool _toldDolby = false;

  bool _newServer = false; // this reconnect is to a different server than the frames so far

  void markReconnect({bool newServer = false}) {
    _newServer = newServer;
    _reconnects++;
    _overlap.clear();
    _catching
      ..clear()
      ..addAll(_lastTs.keys);
    // Until each track's next frame start shows where it resumes, hold its packets back.
    for (final p in {..._dropping.keys, ..._esPids}) {
      _dropping[p] = true;
    }
  }

  Uint8List process(List<int> chunk) {
    final Uint8List d;
    if (_carry.isEmpty) {
      d = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
    } else {
      d = Uint8List(_carry.length + chunk.length)
        ..setRange(0, _carry.length, _carry)
        ..setRange(_carry.length, _carry.length + chunk.length, chunk);
    }
    final n = d.length;
    var i = 0;
    var w = 0;
    while (i + 188 <= n) {
      if (d[i] != 0x47) {
        // Lost packet alignment: skip ahead to the next believable packet start.
        var j = i + 1;
        while (j < n && !(d[j] == 0x47 && (j + 188 >= n || d[j + 188] == 0x47))) {
          j++;
        }
        i = j;
        continue;
      }
      if (_keep(d, i)) {
        if (w != i) d.setRange(w, w + 188, d, i);
        w += 188;
      }
      i += 188;
    }
    _carry = Uint8List.fromList(Uint8List.sublistView(d, i));
    return Uint8List.sublistView(d, 0, w);
  }

  Uint8List flush() {
    final c = _carry;
    _carry = Uint8List(0);
    return c;
  }

  static int _ts(Uint8List d, int o) =>
      ((d[o] >> 1) & 7) << 30 | d[o + 1] << 22 | (d[o + 2] >> 1) << 15 | d[o + 3] << 7 | d[o + 4] >> 1;

  bool _keep(Uint8List d, int i) {
    final pusi = (d[i + 1] & 0x40) != 0;
    final pid = ((d[i + 1] & 0x1F) << 8) | d[i + 2];
    if (pid == 0x1FFF) return true; // padding
    final afc = (d[i + 3] >> 4) & 3;
    final hasPayload = afc == 1 || afc == 3;
    var p = i + 4;
    if (afc == 2 || afc == 3) p += 1 + d[i + 4];
    final end = i + 188;
    if (pusi && hasPayload && p < end) {
      if (pid == 0 || _pmtPids.contains(pid)) {
        _tables(d, p, end, pid);
      } else if (p + 3 <= end && d[p] == 0 && d[p + 1] == 0 && d[p + 2] == 1) {
        // Start of a frame (PES): its decode timestamp (DTS if present, else PTS).
        int? t;
        if (p + 14 <= end && (d[p + 7] & 0x80) != 0) {
          t = _ts(d, p + 9);
          if ((d[p + 7] & 0xC0) == 0xC0 && p + 19 <= end) t = _ts(d, p + 14);
        }
        if (t == null) {
          _dropping[pid] = false;
        } else if (_catching.contains(pid)) {
          final last = _lastTs[pid]!;
          final diff = t - last;
          if (diff.abs() > 60 * 90000) {
            // Provider restarted its clock: don't risk dropping real footage, but the new
            // stream's frames can't build on ours, so hold the picture until a full frame.
            _catching.remove(pid);
            _dropping[pid] = false;
            _lastTs[pid] = t;
            if (pid == _videoPid) {
              _waitKey = true;
              onJump();
              onResume('provider restarted its clock; holding the picture until a full frame');
            }
          } else if (t <= last) {
            _dropping[pid] = true; // already delivered before the hang-up
            _overlap.add(pid);
          } else {
            _catching.remove(pid); // caught up: from here on, everything passes
            _dropping[pid] = false;
            _lastTs[pid] = t;
            if (pid == _videoPid) {
              final lost = diff / 90000.0;
              if (!_overlap.contains(pid) && lost > 0.5) {
                // The provider came back past where we were: footage is missing, and the next
                // frames refer to pictures we never got. Hold until a full frame (no blocks).
                _waitKey = true;
                onJump();
                onResume('lost ${lost.toStringAsFixed(1)} s of footage; holding the picture until a full frame');
              } else if (_newServer) {
                // Same moment in the show, but from a different server's encoder: its frames
                // refer to pictures we never got. Hold until a full frame (no blocks).
                _waitKey = true;
                onResume('caught up on a different server; holding the picture until a full frame');
              } else {
                onResume('caught up after skipping repeated footage');
              }
            }
          }
        } else {
          _dropping[pid] = false;
          _lastTs[pid] = t;
        }
        // Holding the picture: video waits for a full frame (sound keeps going).
        if (pid == _videoPid && _waitKey && _dropping[pid] != true) {
          if (_isFullFrame(d, i, p, end)) {
            _waitKey = false;
            _heldFrames = 0;
            onResume('full frame; picture resumes');
          } else if (++_heldFrames > 240) {
            _waitKey = false; // this stream doesn't mark full frames: don't freeze forever
            _heldFrames = 0;
            onResume('no full-frame marker found; picture resumes');
          } else {
            _dropping[pid] = true;
          }
        }
      } else {
        _dropping[pid] = false; // tables and other non-frame data
      }
    }
    if (_dropping[pid] == true) return false;

    // After a reconnect, keep each track's packet counter unbroken across the splice.
    final cc = d[i + 3] & 0x0F;
    final prev = _outCc[pid];
    if (_reconnects > 0) {
      if (prev == null) {
        _outCc[pid] = cc;
      } else {
        final next = hasPayload ? (prev + 1) & 0x0F : prev;
        d[i + 3] = (d[i + 3] & 0xF0) | next;
        _outCc[pid] = next;
      }
    } else if (hasPayload || prev == null) {
      _outCc[pid] = cc;
    }
    return true;
  }

  /// Whether the frame starting in this packet is a full frame (one that doesn't build on
  /// earlier pictures): the random-access flag most encoders set, or the frame's own markers
  /// (H.264 IDR/SPS, HEVC IRAP/VPS/SPS, MPEG-2 sequence/GOP header).
  bool _isFullFrame(Uint8List d, int i, int pes, int end) {
    final afc = (d[i + 3] >> 4) & 3;
    if ((afc == 2 || afc == 3) && d[i + 4] > 0 && (d[i + 5] & 0x40) != 0) return true;
    if (pes + 9 > end) return false;
    for (var k = pes + 9 + d[pes + 8]; k + 3 < end; k++) {
      if (d[k] != 0 || d[k + 1] != 0 || d[k + 2] != 1) continue;
      final b = d[k + 3];
      if (_videoType == 0x1B) {
        final nal = b & 0x1F; // H.264: IDR picture or sequence settings
        if (nal == 5 || nal == 7) return true;
      } else if (_videoType == 0x24) {
        final nal = (b >> 1) & 0x3F; // HEVC: random-access picture or stream settings
        if ((nal >= 16 && nal <= 21) || nal == 32 || nal == 33) return true;
      } else if (b == 0xB3 || b == 0xB8) {
        return true; // MPEG-2: sequence or group-of-pictures header
      }
      k += 2;
    }
    return false;
  }

  void _tables(Uint8List d, int p0, int end, int pid) {
    final p = p0 + 1 + d[p0]; // pointer field
    if (p + 12 > end) return;
    final tableId = d[p];
    final secLen = ((d[p + 1] & 0x0F) << 8) | d[p + 2];
    final secEnd = p + 3 + secLen;
    if (secLen < 9 || secEnd > end) return; // tables spanning packets are left alone
    if (pid == 0 && tableId == 0x00) {
      for (var k = p + 8; k + 4 <= secEnd - 4; k += 4) {
        final prog = (d[k] << 8) | d[k + 1];
        if (prog != 0) _pmtPids.add(((d[k + 2] & 0x1F) << 8) | d[k + 3]);
      }
      return;
    }
    if (tableId != 0x02) return;
    final progInfo = ((d[p + 10] & 0x0F) << 8) | d[p + 11];
    var k = p + 12 + progInfo;
    var changed = false;
    while (k + 5 <= secEnd - 4) {
      final esPid = ((d[k + 1] & 0x1F) << 8) | d[k + 2];
      _esPids.add(esPid);
      if (_videoTypes.contains(d[k]) && _videoPid == null) {
        _videoPid = esPid;
        _videoType = d[k];
      }
      if (d[k] == 0x87) {
        d[k] = 0x81;
        changed = true;
      }
      k += 5 + (((d[k + 3] & 0x0F) << 8) | d[k + 4]);
    }
    if (!changed) return;
    final crc = _crc32(d, p, secEnd - 4);
    d[secEnd - 4] = (crc >> 24) & 0xFF;
    d[secEnd - 3] = (crc >> 16) & 0xFF;
    d[secEnd - 2] = (crc >> 8) & 0xFF;
    d[secEnd - 1] = crc & 0xFF;
    if (!_toldDolby) {
      _toldDolby = true;
      onDolby();
    }
  }

  static final Uint32List _table = () {
    final t = Uint32List(256);
    for (var i = 0; i < 256; i++) {
      var c = i << 24;
      for (var j = 0; j < 8; j++) {
        c = (c & 0x80000000) != 0 ? ((c << 1) ^ 0x04C11DB7) : (c << 1);
        c &= 0xFFFFFFFF;
      }
      t[i] = c;
    }
    return t;
  }();

  /// MPEG-2 CRC-32 (what TS tables are signed with).
  static int _crc32(Uint8List d, int start, int end) {
    var crc = 0xFFFFFFFF;
    for (var i = start; i < end; i++) {
      crc = ((crc << 8) & 0xFFFFFFFF) ^ _table[((crc >> 24) ^ d[i]) & 0xFF];
    }
    return crc;
  }
}
