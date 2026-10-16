import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../storage/database.dart';
import '../accounts/account_repository.dart';
import '../providers/xtream.dart';

class EpgEntry {
  final String title;
  final DateTime start;
  final DateTime end;
  const EpgEntry(this.title, this.start, this.end);
}

/// 5:00 PM style.
String epgTime(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
}

/// Now / next for Xtream live channels, fetched only for rows on screen.
/// Light by design: tiny per-channel requests, max 3 at a time, cached in memory.
class EpgService {
  final AccountRepository accounts;
  EpgService(this.accounts);

  /// Bumps when new guide info arrives, so rows can refresh.
  final changes = ValueNotifier<int>(0);

  final _cache = <String, (DateTime, List<EpgEntry>)>{};
  final _inFlight = <String>{};
  final _queue = <Item>[];
  final _clients = <String, XtreamClient?>{};
  final _loggedFailures = <String>{};
  int _active = 0;
  static const _maxActive = 3;

  String _key(Item i) => '${i.accountId}|${i.streamId}';
  bool _supported(Item i) => i.kind == 'live' && i.url.isEmpty && i.streamId.isNotEmpty;
  List<EpgEntry> _entries(Item i) => _cache[_key(i)]?.$2 ?? const [];

  EpgEntry? nowFor(Item i) {
    final n = DateTime.now();
    for (final e in _entries(i)) {
      if (!n.isBefore(e.start) && n.isBefore(e.end)) return e;
    }
    return null;
  }

  EpgEntry? nextFor(Item i) {
    final n = DateTime.now();
    for (final e in _entries(i)) {
      if (e.start.isAfter(n)) return e;
    }
    return null;
  }

  /// Ask for guide info for a row that's on screen. Cheap to call on every build.
  void request(Item i) {
    if (!_supported(i)) return;
    final k = _key(i);
    final c = _cache[k];
    if (c != null) {
      final age = DateTime.now().difference(c.$1);
      // Fresh enough: a show is on now, or we asked recently (2h if the provider had nothing).
      if (nowFor(i) != null || age < (c.$2.isEmpty ? const Duration(hours: 2) : const Duration(minutes: 10))) return;
    }
    if (_inFlight.contains(k) || _queue.any((q) => _key(q) == k)) return;
    _queue.add(i);
    if (_queue.length > 40) _queue.removeAt(0); // drop rows you've scrolled far past
    Future.microtask(_pump);
  }

  void _pump() {
    while (_active < _maxActive && _queue.isNotEmpty) {
      final i = _queue.removeLast(); // newest first: what's on screen now
      final k = _key(i);
      if (_inFlight.contains(k)) continue;
      _inFlight.add(k);
      _active++;
      _fetch(i).whenComplete(() {
        _inFlight.remove(k);
        _active--;
        _pump();
      });
    }
  }

  Future<XtreamClient?> _client(String accountId) async {
    if (_clients.containsKey(accountId)) return _clients[accountId];
    final a = await accounts.get(accountId);
    XtreamClient? c;
    if (a != null && a.type == 'xtream') {
      c = XtreamClient(a.server, a.username, await accounts.password(a.id) ?? '');
    }
    _clients[accountId] = c;
    return c;
  }

  static final _b64 = RegExp(r'^[A-Za-z0-9+/]+={0,2}$');

  // Xtream sends titles base64-encoded; fall back to the raw text if it isn't.
  String _decode(String s) {
    final t = s.trim();
    if (t.length >= 4 && t.length % 4 == 0 && _b64.hasMatch(t)) {
      try {
        return utf8.decode(base64.decode(t)).trim();
      } catch (_) {}
    }
    return t;
  }

  Future<void> _fetch(Item i) async {
    try {
      final x = await _client(i.accountId);
      if (x == null) {
        _cache[_key(i)] = (DateTime.now(), const []);
        return;
      }
      final raw = await x.shortEpg(i.streamId, limit: 3);
      final list = <EpgEntry>[];
      for (final m in raw) {
        final s = int.tryParse('${m['start_timestamp'] ?? ''}');
        final e = int.tryParse('${m['stop_timestamp'] ?? ''}');
        if (s == null || e == null) continue;
        list.add(EpgEntry(
          _decode('${m['title'] ?? ''}'),
          DateTime.fromMillisecondsSinceEpoch(s * 1000),
          DateTime.fromMillisecondsSinceEpoch(e * 1000),
        ));
      }
      list.sort((a, b) => a.start.compareTo(b.start));
      _cache[_key(i)] = (DateTime.now(), list);
      if (list.isNotEmpty) changes.value++;
    } catch (e) {
      _cache[_key(i)] = (DateTime.now(), const []);
      if (_loggedFailures.add(i.accountId)) debugPrint('[epg] guide request failed for ${i.name}: $e');
    }
  }
}
