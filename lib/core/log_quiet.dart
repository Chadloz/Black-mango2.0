import 'package:flutter/foundation.dart';

/// Collapses floods of identical player messages (a broken stream can log the
/// same audio error thousands of times). Each repeating player line shows at
/// most once per 30 seconds, with a count. Black Mango's own lines are untouched.
class LogQuiet {
  static final _last = <String, DateTime>{};
  static final _hidden = <String, int>{};

  static bool _noisy(String m) => m.startsWith('[mpv]') || m.contains('non-fatal');

  static void start() {
    final inner = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      final m = message ?? '';
      if (!_noisy(m)) {
        inner(message, wrapWidth: wrapWidth);
        return;
      }
      final now = DateTime.now();
      final prev = _last[m];
      if (prev != null && now.difference(prev) < const Duration(seconds: 30)) {
        _hidden[m] = (_hidden[m] ?? 0) + 1;
        return;
      }
      final n = _hidden.remove(m) ?? 0;
      if (_last.length > 500) _last.clear();
      _last[m] = now;
      inner(n > 0 ? '$m  (repeated $n more times)' : m, wrapWidth: wrapWidth);
    };
  }
}
