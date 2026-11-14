import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

/// Startup timing for the log, and a watchdog that notices freezes.
///
/// Why: on some Windows PCs Black Mango stops responding for 8 to 40 seconds when it opens
/// after the PC has slept or sat idle. These lines show which step the time goes to, so the
/// fix can go in the right place. All of it only writes to the log.
class StartupLog {
  static final _clock = Stopwatch();
  static int _lastAt = 0;
  static String _last = 'launch';

  // The last few things the app asked the video engine, and when (ms since launch).
  static final _asked = <(String, int)>[];

  /// Notes what the app is about to ask the video engine (mpv).
  ///
  /// Why: those requests wait for the engine's answer. When the engine is tied up, say with a
  /// stream that won't open or won't close, the whole app waits with it. Test build 8 caught
  /// 2 to 4 second freezes every time a failing channel was being replaced; this is how the
  /// next freeze line names the exact request the app was stuck on.
  static void doing(String what) {
    final now = _clock.elapsedMilliseconds;
    if (_asked.isNotEmpty && _asked.last.$1 == what) {
      _asked[_asked.length - 1] = (what, now);
      return;
    }
    _asked.add((what, now));
    if (_asked.length > 12) _asked.removeAt(0);
  }

  static const _long = Duration(milliseconds: 1500);
  static const _asleep = Duration(minutes: 2); // longer than this was the computer sleeping, not a freeze

  static void begin() => _clock.start();

  /// A startup step just finished: how long it took, and how far into startup we are.
  static void mark(String step) {
    final now = _clock.elapsedMilliseconds;
    debugPrint('[startup] $step: ${now - _lastAt} ms ($now ms since launch)');
    _lastAt = now;
    _last = step;
  }

  /// Times one piece of work that runs on its own (not part of the step-by-step startup).
  static Future<T> time<T>(String what, Future<T> Function() work) async {
    final from = _clock.elapsedMilliseconds;
    try {
      return await work();
    } finally {
      debugPrint('[startup] $what: ${_clock.elapsedMilliseconds - from} ms');
    }
  }

  /// Logs when the first screen has been drawn.
  static void firstFrame() => WidgetsBinding.instance.addPostFrameCallback((_) => mark('first screen drawn'));

  /// Two checks, from here until the app closes:
  /// - the app's own heartbeat (4 times a second): a late beat means the app itself was stuck;
  /// - a question to the window every 2 seconds: a late answer means the window side was stuck.
  static void watch() {
    var prev = DateTime.now();
    Timer.periodic(const Duration(milliseconds: 250), (_) {
      final now = DateTime.now();
      final gap = now.difference(prev);
      prev = now;
      if (gap > _long && gap < _asleep) _say('the app stopped responding', gap);
    });
    _askWindow();
  }

  static Future<void> _askWindow() async {
    while (true) {
      await Future.delayed(const Duration(seconds: 2));
      final sw = Stopwatch()..start();
      try {
        await windowManager.isVisible();
      } catch (_) {
        return; // no window to ask here: nothing to measure
      }
      final gap = sw.elapsed;
      if (gap > _long && gap < _asleep) _say('the window stopped answering', gap);
    }
  }

  static void _say(String what, Duration gap) {
    // A hidden or minimized app is allowed to doze (macOS slows its timers down): not a freeze.
    final state = WidgetsBinding.instance.lifecycleState;
    if (state == AppLifecycleState.hidden || state == AppLifecycleState.paused || state == AppLifecycleState.detached) return;
    final now = _clock.elapsedMilliseconds;
    final began = now - gap.inMilliseconds;
    String ago(int at) => '${((now - at) / 1000).toStringAsFixed(1)} s ago';
    // The request the app was stuck on is the last one made before the freeze began (a little
    // slack for timing); the ones after it ran once the engine let go.
    final before = _asked.where((a) => a.$2 <= began + 300).toList();
    final after = _asked.where((a) => a.$2 > began + 300).toList();
    final stuck = before.isEmpty || began - before.last.$2 > 3000
        ? 'nothing had just been asked of the video engine'
        : 'the app had just asked the video engine: ${before.last.$1} (${ago(before.last.$2)})';
    final earlier = before.length < 2
        ? ''
        : ' Before that: ${before.reversed.skip(1).take(3).map((a) => '${a.$1} (${ago(a.$2)})').join(', ')}.';
    final next = after.isEmpty ? '' : ' Then: ${after.take(2).map((a) => a.$1).join(', ')}.';
    final startup = _clock.elapsed < const Duration(minutes: 1) ? ' Last startup step: $_last.' : '';
    debugPrint('[freeze] $what for ${(gap.inMilliseconds / 1000).toStringAsFixed(1)} s '
        '(${_clock.elapsed.inSeconds} s after launch): $stuck.$earlier$next$startup');
  }
}
