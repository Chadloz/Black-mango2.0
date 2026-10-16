import 'package:flutter/foundation.dart';

/// Keeps the last 3,000 log lines in memory so they can be copied from Settings.
/// Credentials in stream links are hidden as they're recorded.
class AppLog {
  static const _max = 3000;
  static final _lines = <String>[];
  static final _pathCreds = RegExp(r'(/(?:live|movie|series)/)[^/\s]+/[^/\s]+/');
  static final _queryCreds = RegExp(r'((?:username|password)=)[^&\s]+', caseSensitive: false);

  static void start() {
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) add(message);
      original(message, wrapWidth: wrapWidth);
    };
  }

  static void add(String m) {
    final t = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final clean = m
        .replaceAllMapped(_pathCreds, (x) => '${x[1]}***/***/')
        .replaceAllMapped(_queryCreds, (x) => '${x[1]}***');
    _lines.add('${two(t.hour)}:${two(t.minute)}:${two(t.second)} $clean');
    if (_lines.length > _max) _lines.removeRange(0, _lines.length - _max);
  }

  static int get count => _lines.length;

  static String text({int? last}) {
    final l = (last == null || last >= _lines.length) ? _lines : _lines.sublist(_lines.length - last);
    return l.join('\n');
  }

  static void clear() => _lines.clear();
}
