import 'package:flutter/foundation.dart';

/// Tracks which servers are failing. 3 different streams failing to open on one server
/// within 10 minutes marks it down for 30 minutes. One good play clears it.
class ServerHealth {
  final _fails = <String, List<(DateTime, String)>>{};
  final _downUntil = <String, DateTime>{};
  final _okAt = <String, DateTime>{};

  /// Bumps whenever anything changes, so the UI can refresh.
  final changes = ValueNotifier<int>(0);

  void fail(String host, String stream) {
    final now = DateTime.now();
    final list = _fails.putIfAbsent(host, () => []);
    list.removeWhere((f) => now.difference(f.$1) > const Duration(minutes: 10));
    list.add((now, stream));
    final distinct = list.map((f) => f.$2).toSet().length;
    if (distinct >= 3 && !isDown(host)) {
      _downUntil[host] = now.add(const Duration(minutes: 30));
      debugPrint('[health] $host marked down for 30 min ($distinct streams failed)');
    }
    changes.value++;
  }

  void ok(String host) {
    _okAt[host] = DateTime.now();
    _downUntil.remove(host);
    _fails.remove(host);
    changes.value++;
  }

  void clear(String host) {
    _downUntil.remove(host);
    _fails.remove(host);
    changes.value++;
  }

  bool isDown(String host) => _downUntil[host]?.isAfter(DateTime.now()) ?? false;
  DateTime? downUntil(String host) => isDown(host) ? _downUntil[host] : null;
  DateTime? lastOk(String host) => _okAt[host];
  Set<String> get downHosts => {for (final h in _downUntil.keys) if (isDown(h)) h};
}
