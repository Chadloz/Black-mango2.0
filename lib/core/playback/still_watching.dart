import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/theme.dart';
import '../prefs.dart';
import '../services.dart';

/// After a stretch with no mouse or keyboard activity, pause and ask.
class StillWatching {
  static const defaultMessage = 'Are you getting laid?';
  static DateTime _last = DateTime.now();
  static final prompt = ValueNotifier<bool>(false);
  static Timer? _timer;

  static String get message {
    final m = Prefs.getStr('still.msg');
    return (m == null || m.trim().isEmpty) ? defaultMessage : m;
  }

  static void start() {
    GestureBinding.instance.pointerRouter.addGlobalRoute((e) {
      if (e is PointerDownEvent || e is PointerHoverEvent || e is PointerScrollEvent) _last = DateTime.now();
    });
    HardwareKeyboard.instance.addHandler((e) {
      _last = DateTime.now();
      return false;
    });
    Services.playback.current.addListener(() => _last = DateTime.now());
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _check());
  }

  static void _check() {
    if (Prefs.getBool('still.disabled') || prompt.value) return;
    final p = Services.playback;
    if (p.current.value == null || !p.player.state.playing) return;
    final hours = Prefs.getInt('still.hours') ?? 3;
    if (DateTime.now().difference(_last) >= Duration(hours: hours)) {
      p.player.pause();
      prompt.value = true;
      debugPrint('[still] no activity for $hours h, paused');
    }
  }

  static void dismiss() {
    prompt.value = false;
    _last = DateTime.now();
    Services.playback.player.play();
  }
}

/// Shown over the video (fullscreen too) when Still Watching pauses playback.
class StillWatchingOverlay extends StatelessWidget {
  const StillWatchingOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: StillWatching.prompt,
      builder: (context, on, _) {
        if (!on) return const SizedBox.shrink();
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {}, // keep taps here from toggling the video underneath
          child: Container(
            color: Colors.black87,
            alignment: Alignment.center,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.bedtime, size: 40, color: BMColors.mango),
                const SizedBox(height: 12),
                Text(StillWatching.message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 8),
                const Text('Playback paused.', style: TextStyle(color: BMColors.dim)),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: StillWatching.dismiss,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Keep watching'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
