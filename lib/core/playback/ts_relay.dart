import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../prefs.dart';

/// A tiny relay on 127.0.0.1 for live .ts channels.
///
/// Some US channels label Dolby Digital Plus audio with the ATSC stream type 0x87,
/// which the bundled (older) FFmpeg skips, so they play silent. The relay passes
/// the stream through untouched except for that one label in the track table
/// (PMT): 0x87 -> 0x81 (AC-3), with the table's CRC recomputed. FFmpeg's Dolby
/// reader then detects the real E-AC-3 data and decodes it.
///
/// Provider status codes pass through unchanged (403 busy, 404, 5xx), and the
/// upstream connection closes as soon as the player disconnects.
class TsRelay {
  static HttpServer? _server;
  static final _urls = <String, String>{};
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
  static String wrap(String url) {
    final s = _server;
    if (s == null || Prefs.getBool('relay.off') || !_isLiveTs(url)) return url;
    final id = '${_next++}';
    _urls[id] = url;
    if (_urls.length > 40) _urls.remove(_urls.keys.first);
    return 'http://127.0.0.1:${s.port}/r/$id.ts';
  }

  static Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    final seg = req.uri.pathSegments;
    final id = seg.length == 2 && seg[0] == 'r' ? seg[1].replaceAll('.ts', '') : '';
    final target = _urls[id];
    if (target == null) {
      res.statusCode = HttpStatus.notFound;
      await res.close();
      return;
    }
    final name = Uri.parse(target).pathSegments.last;
    debugPrint('[relay] stream $name via relay');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12)
      ..autoUncompress = false;
    Socket? socket;
    var closed = false;
    // Closes both sides. Called the moment either the player or the provider hangs up,
    // so the provider's connection slot is freed right away (one-connection accounts).
    void shutdown() {
      if (closed) return;
      closed = true;
      client.close(force: true);
      socket?.destroy();
    }

    try {
      final up = await client.getUrl(Uri.parse(target));
      for (final h in const ['user-agent', 'range', 'accept']) {
        final v = req.headers.value(h);
        if (v != null) up.headers.set(h, v);
      }
      final r = await up.close();
      res.statusCode = r.statusCode;
      res.reasonPhrase = r.reasonPhrase;
      for (final h in const ['content-type', 'content-range', 'accept-ranges']) {
        final v = r.headers.value(h);
        if (v != null) res.headers.set(h, v);
      }
      if (r.statusCode >= 400) {
        // Pass the provider's answer (403 busy, 404, 5xx...) straight to the player.
        await res.close();
        shutdown();
        return;
      }
      res.persistentConnection = false;
      if (r.contentLength >= 0) {
        res.contentLength = r.contentLength;
      } else {
        res.headers.chunkedTransferEncoding = false; // plain stream until either side closes
      }
      final s = await res.detachSocket(writeHeaders: true);
      socket = s;
      // The player hanging up (channel change, stop, close) shows up as its socket closing.
      s.listen((_) {}, onDone: shutdown, onError: (_) => shutdown(), cancelOnError: true);

      final started = DateTime.now();
      var bytes = 0;
      final patcher = _TsPatcher(() => debugPrint('[relay] Dolby Digital Plus audio relabeled so it plays'));
      try {
        await s.addStream(r.transform(StreamTransformer<List<int>, List<int>>.fromHandlers(
          handleData: (d, sink) {
            bytes += d.length;
            final o = patcher.process(d);
            if (o.isNotEmpty) sink.add(o);
          },
          handleDone: (sink) {
            final o = patcher.flush();
            if (o.isNotEmpty) sink.add(o);
            sink.close();
          },
        )));
        await s.flush();
        if (!closed) {
          final secs = DateTime.now().difference(started).inSeconds;
          debugPrint('[relay] provider ended $name after ${secs}s (${(bytes / 1e6).toStringAsFixed(1)} MB)');
        }
      } catch (_) {
        // The player hung up mid-stream: normal on channel change.
      }
    } catch (e) {
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

/// Walks 188-byte TS packets and relabels E-AC-3 (0x87) as AC-3 (0x81) in the PMT.
class _TsPatcher {
  _TsPatcher(this.onPatched);
  final VoidCallback onPatched;
  final _pmtPids = <int>{};
  Uint8List _carry = Uint8List(0);
  bool _told = false;

  Uint8List process(List<int> chunk) {
    final Uint8List data;
    if (_carry.isEmpty) {
      data = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
    } else {
      data = Uint8List(_carry.length + chunk.length)
        ..setRange(0, _carry.length, _carry)
        ..setRange(_carry.length, _carry.length + chunk.length, chunk);
    }
    final n = data.length;
    var i = 0;
    while (i + 188 <= n) {
      if (data[i] != 0x47) {
        // Lost packet alignment: skip ahead to the next believable packet start (bytes pass through as-is).
        var j = i + 1;
        while (j < n && !(data[j] == 0x47 && (j + 188 >= n || data[j + 188] == 0x47))) {
          j++;
        }
        i = j;
        continue;
      }
      _inspect(data, i);
      i += 188;
    }
    _carry = Uint8List.fromList(Uint8List.sublistView(data, i));
    return Uint8List.sublistView(data, 0, i);
  }

  Uint8List flush() {
    final c = _carry;
    _carry = Uint8List(0);
    return c;
  }

  void _inspect(Uint8List d, int i) {
    if ((d[i + 1] & 0x40) == 0) return; // only packets that start a table
    final pid = ((d[i + 1] & 0x1F) << 8) | d[i + 2];
    if (pid != 0 && !_pmtPids.contains(pid)) return;
    final afc = (d[i + 3] >> 4) & 3;
    if (afc == 0 || afc == 2) return;
    final end = i + 188;
    var p = i + 4;
    if (afc == 3) p += 1 + d[p];
    if (p >= end) return;
    p += 1 + d[p]; // pointer field
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
    if (!_told) {
      _told = true;
      onPatched();
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
