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
  static HttpServer? _server;
  static final _urls = <String, _Target>{};
  static int _next = 0;

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
  static String wrap(String url, {bool live = false, Future<String> Function()? refresh}) {
    final s = _server;
    if (s == null || Prefs.getBool('relay.off') || !(live || _isLiveTs(url))) return url;
    final id = '${_next++}';
    _urls[id] = _Target(url, refresh);
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
    // Stalker links are good for one connection. When the player asks for the same stream
    // again (it reconnects on its own sometimes), get a fresh link instead of the spent one.
    final stalker = t.refresh != null;
    if (stalker && t.used) {
      try {
        t.url = await t.refresh!();
      } catch (e) {
        debugPrint('[relay] could not get a fresh link: $e');
      }
    }
    t.used = true;
    var target = t.url;
    final name = _label(target);
    debugPrint('[relay] stream $name via relay');
    final asked = DateTime.now();
    var sentTotal = 0;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12)
      ..autoUncompress = false;
    Socket? socket;
    var closed = false;
    // Closes both sides. Called the moment the player hangs up or we give up,
    // so the provider's connection slot is freed right away.
    void shutdown() {
      if (closed) return;
      closed = true;
      client.close(force: true);
      socket?.destroy();
    }

    Future<HttpClientResponse> open({bool fresh = false}) async {
      final refresh = t.refresh;
      if (fresh && refresh != null) {
        try {
          target = await refresh();
        } catch (e) {
          debugPrint('[relay] $name could not get a fresh link: $e');
        }
      }
      final up = await client.getUrl(Uri.parse(target));
      for (final h in const ['user-agent', 'accept']) {
        final v = req.headers.value(h);
        if (v != null) up.headers.set(h, v);
      }
      if (!fresh) {
        final range = req.headers.value('range');
        if (range != null) up.headers.set('range', range);
      }
      final began = DateTime.now();
      final r = await up.close();
      if (stalker) {
        // Diagnostics for Stalker: what the stream server answered (never the link itself).
        final hops = r.redirects.isEmpty ? '' : ', redirected to ${r.redirects.last.location.host}';
        debugPrint('[relay] $name: server answered ${r.statusCode} '
            '${r.headers.value('content-type') ?? '-'}, length ${r.contentLength}, '
            'in ${DateTime.now().difference(began).inMilliseconds} ms'
            '${up.headers.value('range') != null ? ', player asked for a range' : ''}$hops');
      }
      return r;
    }

    try {
      var r = await open();
      res.statusCode = r.statusCode;
      res.reasonPhrase = r.reasonPhrase;
      for (final h in const ['content-type', 'content-range', 'accept-ranges']) {
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
      res.persistentConnection = false;
      final seamless = r.contentLength < 0; // live streams have no fixed length
      if (r.contentLength >= 0) {
        res.contentLength = r.contentLength;
      } else {
        res.headers.chunkedTransferEncoding = false; // plain stream until either side closes
      }
      final s = await res.detachSocket(writeHeaders: true);
      socket = s;
      // The player hanging up (channel change, stop, close) shows up as its socket closing.
      s.listen((_) {}, onDone: () {
        if (stalker && !closed) {
          debugPrint('[relay] $name: player hung up after ${(sentTotal / 1000).toStringAsFixed(0)} KB, '
              '${DateTime.now().difference(asked).inMilliseconds} ms');
        }
        shutdown();
      }, onError: (_) => shutdown(), cancelOnError: true);

      final filter = _TsFilter(
        onDolby: () => debugPrint('[relay] Dolby Digital Plus audio relabeled so it plays'),
        onResume: (m) => debugPrint('[relay] $name reconnected: $m'),
      );
      var quickEnds = 0;
      while (!closed) {
        final started = DateTime.now();
        var bytes = 0;
        var pending = 0;
        try {
          // A provider that goes silent for 8 seconds counts as a hang-up.
          await for (final chunk in r.timeout(const Duration(seconds: 8))) {
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
            }
          } catch (e) {
            debugPrint('[relay] $name reconnect failed: $e');
          }
        }
        if (next == null) break;
        filter.markReconnect();
        r = next;
      }
      if (!closed) {
        final rest = filter.flush();
        if (rest.isNotEmpty) s.add(rest);
        try {
          await s.flush();
        } catch (_) {}
      }
    } catch (e) {
      if (stalker) debugPrint('[relay] $name: error $e');
      // Provider unreachable before anything was sent: report it as a server problem.
      if (!closed && socket == null) {
        debugPrint('[relay] provider unreachable: $e');
        try {
          res.statusCode = HttpStatus.badGateway;
          await res.close();
        } catch (_) {}
      }
    } finally {
      shutdown();
    }
  }
}

/// A stream to relay, and (for Stalker) how to get a fresh link for it.
class _Target {
  String url;
  final Future<String> Function()? refresh;
  bool used = false; // a Stalker link is spent once the provider has been asked for it
  _Target(this.url, this.refresh);
}

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
  _TsFilter({required this.onDolby, required this.onResume});
  final VoidCallback onDolby;
  final void Function(String) onResume;

  static const _videoTypes = {0x01, 0x02, 0x1B, 0x24};

  final _pmtPids = <int>{};
  final _esPids = <int>{};
  int? _videoPid;
  final _lastTs = <int, int>{}; // per track: last decode timestamp passed along (90 kHz)
  final _catching = <int>{}; // tracks still skipping replayed footage after a reconnect
  final _dropping = <int, bool>{};
  final _outCc = <int, int>{};
  int _reconnects = 0;
  Uint8List _carry = Uint8List(0);
  bool _toldDolby = false;

  void markReconnect() {
    _reconnects++;
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
            // Provider restarted its clock: don't risk dropping real footage.
            _catching.remove(pid);
            _dropping[pid] = false;
            _lastTs[pid] = t;
            if (pid == _videoPid) onResume('provider restarted its clock; passing it through');
          } else if (t <= last) {
            _dropping[pid] = true; // already delivered before the hang-up
          } else {
            _catching.remove(pid); // caught up: from here on, everything passes
            _dropping[pid] = false;
            _lastTs[pid] = t;
            if (pid == _videoPid) onResume('caught up after skipping repeated footage');
          }
        } else {
          _dropping[pid] = false;
          _lastTs[pid] = t;
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
      if (_videoTypes.contains(d[k]) && _videoPid == null) _videoPid = esPid;
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
