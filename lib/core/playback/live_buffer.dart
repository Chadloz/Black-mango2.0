import 'dart:math';
import '../prefs.dart';
import '../storage/database.dart';

/// Extra buffer for flaky live channels, remembered per channel on each account (survives
/// restarts). A channel that stalls twice in 5 minutes gets 3 more seconds of cushion, up to
/// 15 seconds in all; after 30 minutes of smooth watching it steps back down by 3.
class LiveBuffer {
  static const step = 3; // seconds added (or taken back) each time
  static const maxTotal = 15; // the most cushion any channel gets
  static const _prefix = 'livebuf.';

  static String _key(Item i) => '$_prefix${i.accountId}|${i.streamId.isNotEmpty ? i.streamId : i.url}';

  /// Your "Buffer before a channel starts" setting.
  static int get base => Prefs.getInt('live.buffer') ?? 3;

  /// Extra seconds this channel has earned.
  static int extra(Item i) => int.tryParse(Prefs.getStr(_key(i)) ?? '') ?? 0;

  /// What this channel actually uses: your setting plus its extra, never above [maxTotal].
  static int total(Item i) => min(maxTotal, base + extra(i));

  static Future<void> setExtra(Item i, int seconds) => Prefs.setStr(_key(i), seconds <= 0 ? null : '$seconds');

  /// How many channels currently have extra buffer.
  static int count() => Prefs.keys().where((k) => k.startsWith(_prefix)).length;

  /// Settings > Reset: every channel back to your normal buffer.
  static Future<void> resetAll() async {
    for (final k in Prefs.keys().where((k) => k.startsWith(_prefix)).toList()) {
      await Prefs.setStr(k, null);
    }
  }
}
