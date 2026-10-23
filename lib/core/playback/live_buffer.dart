import 'dart:math';
import '../prefs.dart';
import '../storage/database.dart';

/// Extra buffer for flaky live channels, remembered per channel on each account (survives
/// restarts). A channel that stalls twice in 5 minutes gets 3 more seconds of cushion, up to
/// 15 seconds in all; after 30 minutes of smooth watching it steps back down by 3.
/// A channel whose provider keeps dropping the connection can go further, up to 30 seconds
/// (in steps of 5 past 15), since each reconnect can take a while.
class LiveBuffer {
  static const step = 3; // seconds added (or taken back) each time
  static const maxTotal = 15; // the most cushion a channel normally gets
  static const maxHeavy = 30; // ...and one whose provider keeps dropping the connection
  static const _prefix = 'livebuf.';
  static const _heavyPrefix = 'livebufheavy.';

  static String _id(Item i) => '${i.accountId}|${i.streamId.isNotEmpty ? i.streamId : i.url}';
  static String _key(Item i) => '$_prefix${_id(i)}';

  /// This channel's provider keeps dropping the connection (4 drops in 2 minutes, see playback).
  static bool isHeavy(Item i) => Prefs.getStr('$_heavyPrefix${_id(i)}') != null;
  static Future<void> markHeavy(Item i) => Prefs.setStr('$_heavyPrefix${_id(i)}', '1');

  /// The most cushion this channel can get.
  static int maxFor(Item i) => isHeavy(i) ? maxHeavy : maxTotal;

  /// How much the next step adds: 3 seconds, or 5 once past the normal 15.
  static int stepFor(Item i) => base + extra(i) >= maxTotal ? 5 : step;

  /// Your "Buffer before a channel starts" setting.
  static int get base => Prefs.getInt('live.buffer') ?? 3;

  /// Extra seconds this channel has earned.
  static int extra(Item i) => int.tryParse(Prefs.getStr(_key(i)) ?? '') ?? 0;

  /// What this channel actually uses: your setting plus its extra, never above its max.
  static int total(Item i) => min(maxFor(i), base + extra(i));

  static Future<void> setExtra(Item i, int seconds) => Prefs.setStr(_key(i), seconds <= 0 ? null : '$seconds');

  // Channels that play better as HLS (set by playback), and accounts where HLS didn't work.
  static bool _isFix(String k) =>
      k.startsWith(_prefix) || k.startsWith(_heavyPrefix) || k.startsWith('hls.') || k.startsWith('hlsno.');

  /// How many channels currently have a fix (extra buffer, or opening as HLS).
  static int count() => Prefs.keys().where((k) => k.startsWith(_prefix) || k.startsWith('hls.')).length;

  /// Settings > Reset: every channel back to your normal buffer and the regular stream.
  static Future<void> resetAll() async {
    for (final k in Prefs.keys().where(_isFix).toList()) {
      await Prefs.setStr(k, null);
    }
  }
}
