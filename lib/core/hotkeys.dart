import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app/nav.dart';
import '../app/theme.dart';
import 'prefs.dart';
import 'services.dart';
import 'widgets/player_controls.dart';
import 'widgets/mini_player.dart';

/// Every action a key can trigger.
enum HK {
  playPause,
  playSelected,
  fullscreen,
  mute,
  volumeUp,
  volumeDown,
  seekBack,
  seekForward,
  closePlayer,
  backToLast,
  navUp,
  navDown,
  channelNext,
  channelPrev,
  popOut,
}

const hkLabels = {
  HK.playPause: 'Play / pause',
  HK.playSelected: 'Play selected channel',
  HK.fullscreen: 'Fullscreen',
  HK.mute: 'Mute',
  HK.volumeUp: 'Volume up',
  HK.volumeDown: 'Volume down',
  HK.seekBack: 'Back 10 seconds',
  HK.seekForward: 'Forward 10 seconds',
  HK.closePlayer: 'Close player (exits fullscreen first)',
  HK.backToLast: 'Back to last screen',
  HK.navUp: 'Move selection up',
  HK.navDown: 'Move selection down',
  HK.channelNext: 'Next channel',
  HK.channelPrev: 'Previous channel',
  HK.popOut: 'Mini player (always on top)',
};

final _defaults = {
  HK.playPause: LogicalKeyboardKey.space,
  HK.playSelected: LogicalKeyboardKey.enter,
  HK.fullscreen: LogicalKeyboardKey.keyF,
  HK.mute: LogicalKeyboardKey.keyM,
  HK.volumeUp: LogicalKeyboardKey.equal,
  HK.volumeDown: LogicalKeyboardKey.minus,
  HK.seekBack: LogicalKeyboardKey.bracketLeft,
  HK.seekForward: LogicalKeyboardKey.bracketRight,
  HK.closePlayer: LogicalKeyboardKey.escape,
  HK.backToLast: LogicalKeyboardKey.tab,
  HK.navUp: LogicalKeyboardKey.arrowUp,
  HK.navDown: LogicalKeyboardKey.arrowDown,
  HK.channelNext: LogicalKeyboardKey.pageDown,
  HK.channelPrev: LogicalKeyboardKey.pageUp,
  HK.popOut: LogicalKeyboardKey.keyP,
};

final _modifiers = {
  LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.shiftRight, LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.controlRight, LogicalKeyboardKey.altLeft, LogicalKeyboardKey.altRight,
  LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.metaRight, LogicalKeyboardKey.capsLock, LogicalKeyboardKey.fn,
};

String keyName(LogicalKeyboardKey k) {
  final names = {
    LogicalKeyboardKey.space: 'Space',
    LogicalKeyboardKey.escape: 'Esc',
    LogicalKeyboardKey.tab: 'Tab',
    LogicalKeyboardKey.enter: 'Enter',
    LogicalKeyboardKey.arrowUp: '↑',
    LogicalKeyboardKey.arrowDown: '↓',
    LogicalKeyboardKey.arrowLeft: '←',
    LogicalKeyboardKey.arrowRight: '→',
    LogicalKeyboardKey.pageUp: 'Page Up',
    LogicalKeyboardKey.pageDown: 'Page Down',
    LogicalKeyboardKey.equal: '+ / =',
    LogicalKeyboardKey.minus: '−',
  };
  final n = names[k];
  if (n != null) return n;
  final l = k.keyLabel.trim();
  return l.isEmpty ? 'Key ${k.keyId}' : l.toUpperCase();
}

/// App-wide hotkeys. Ignored while typing in a text box, and Cmd/Ctrl/Alt combos are left alone.
/// Screens listen to [events] for list navigation, Enter, and channel flipping.
class Hotkeys {
  static final events = StreamController<HK>.broadcast();
  static bool capturing = false; // Settings is waiting for a new key
  /// Channel numbers typed like a TV remote (fires 1.2s after the last digit).
  static final gotoChannel = StreamController<int>.broadcast();
  static final typedNumber = ValueNotifier<String?>(null);
  static String _typed = '';
  static Timer? _typeTimer;
  static int _prev = AppNav.home;
  static int _cur = AppNav.index.value;

  static void start() {
    HardwareKeyboard.instance.addHandler(_handle);
    AppNav.index.addListener(() {
      if (AppNav.index.value != _cur) {
        _prev = _cur;
        _cur = AppNav.index.value;
      }
    });
  }

  static LogicalKeyboardKey keyFor(HK a) {
    final id = Prefs.getInt('hotkey.${a.name}');
    if (id == null) return _defaults[a]!;
    return LogicalKeyboardKey.findKeyByKeyId(id) ?? _defaults[a]!;
  }

  static bool isModifier(LogicalKeyboardKey k) => _modifiers.contains(k);

  static bool _typing() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    return ctx.widget is EditableText || ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  static const _repeatable = {HK.volumeUp, HK.volumeDown, HK.seekBack, HK.seekForward, HK.navUp, HK.navDown};

  static bool _handle(KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return false;
    if (capturing || _typing()) return false;
    final hw = HardwareKeyboard.instance;
    if (hw.isMetaPressed || hw.isControlPressed || hw.isAltPressed) return false;
    for (final a in HK.values) {
      if (keyFor(a) == e.logicalKey) {
        if (e is KeyRepeatEvent && !_repeatable.contains(a)) return true;
        return _run(a);
      }
    }
    // Digits while a live channel plays: type a channel number like a TV remote.
    final d = _digitOf(e.logicalKey);
    if (d != null && e is KeyDownEvent && Services.playback.current.value?.kind == 'live') {
      _typeDigit(d);
      return true;
    }
    return false;
  }

  static int? _digitOf(LogicalKeyboardKey k) {
    const top = [
      LogicalKeyboardKey.digit0, LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit2, LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4, LogicalKeyboardKey.digit5, LogicalKeyboardKey.digit6, LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8, LogicalKeyboardKey.digit9,
    ];
    const pad = [
      LogicalKeyboardKey.numpad0, LogicalKeyboardKey.numpad1, LogicalKeyboardKey.numpad2, LogicalKeyboardKey.numpad3,
      LogicalKeyboardKey.numpad4, LogicalKeyboardKey.numpad5, LogicalKeyboardKey.numpad6, LogicalKeyboardKey.numpad7,
      LogicalKeyboardKey.numpad8, LogicalKeyboardKey.numpad9,
    ];
    var i = top.indexOf(k);
    if (i >= 0) return i;
    i = pad.indexOf(k);
    return i >= 0 ? i : null;
  }

  static void _typeDigit(int d) {
    if (_typed.length >= 5) _typed = '';
    _typed += '$d';
    typedNumber.value = _typed;
    _typeTimer?.cancel();
    _typeTimer = Timer(const Duration(milliseconds: 1200), () {
      final n = int.tryParse(_typed);
      _typed = '';
      typedNumber.value = null;
      if (n != null && n > 0) gotoChannel.add(n);
    });
  }

  static bool _run(HK a) {
    final p = Services.playback;
    final pl = p.player;
    final cur = p.current.value;
    final live = cur?.kind == 'live';
    switch (a) {
      case HK.playPause:
        if (cur == null) return false;
        pl.playOrPause();
        return true;
      case HK.fullscreen:
        final s = BMControls.activeState;
        if (s == null || cur == null) return false;
        s.toggleFullscreen();
        return true;
      case HK.mute:
        p.toggleMute();
        return true;
      case HK.volumeUp:
        p.setVolume((pl.state.volume + 5).clamp(0.0, 150.0).toDouble());
        return true;
      case HK.volumeDown:
        p.setVolume((pl.state.volume - 5).clamp(0.0, 150.0).toDouble());
        return true;
      case HK.seekBack:
      case HK.seekForward:
        if (cur == null || live) return false;
        final step = Duration(seconds: a == HK.seekBack ? -10 : 10);
        final t = pl.state.position + step;
        pl.seek(t < Duration.zero ? Duration.zero : t);
        return true;
      case HK.closePlayer:
        if (PopOut.active.value) {
          PopOut.backToFull();
          return true;
        }
        final s = BMControls.activeState;
        if (s != null && s.isFullscreen()) {
          s.exitFullscreen();
          return true;
        }
        if (cur != null) {
          p.stop();
          return true;
        }
        return false;
      case HK.popOut:
        if (cur == null) return false;
        PopOut.active.value ? PopOut.backToFull() : PopOut.enter();
        return true;
      case HK.backToLast:
        AppNav.index.value = _prev;
        return true;
      default:
        events.add(a); // list navigation, Enter, channel flipping: handled by screens
        return true;
    }
  }
}

/// Big "Ch 12" shown on the video while a channel number is being typed.
class ChannelNumberBadge extends StatelessWidget {
  const ChannelNumberBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: Hotkeys.typedNumber,
      builder: (context, v, _) {
        if (v == null) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.topCenter,
          child: Container(
            margin: const EdgeInsets.only(top: 16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(10)),
            child: Text('Ch $v',
                style: const TextStyle(fontFamily: BMFonts.mono, fontSize: 28, fontWeight: FontWeight.w700, color: BMColors.mango)),
          ),
        );
      },
    );
  }
}

/// Settings: click a binding, press the new key. Esc cancels.
class HotkeyEditor extends StatefulWidget {
  const HotkeyEditor({super.key});

  @override
  State<HotkeyEditor> createState() => _HotkeyEditorState();
}

class _HotkeyEditorState extends State<HotkeyEditor> {
  HK? _capturing;

  bool _onKey(KeyEvent e) {
    final a = _capturing;
    if (a == null || e is! KeyDownEvent) return false;
    if (Hotkeys.isModifier(e.logicalKey)) return true;
    if (e.logicalKey != LogicalKeyboardKey.escape) Prefs.setInt('hotkey.${a.name}', e.logicalKey.keyId);
    _stop();
    return true;
  }

  void _start(HK a) {
    _stop();
    setState(() => _capturing = a);
    Hotkeys.capturing = true;
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  void _stop() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    Hotkeys.capturing = false;
    if (mounted) setState(() => _capturing = null);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    Hotkeys.capturing = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Click a key, then press the new one (Esc cancels). Shortcuts work anywhere except while typing in a text box. Double-clicking the video also toggles fullscreen.',
                style: TextStyle(color: BMColors.dim, fontSize: 12),
              ),
            ),
            const SizedBox(width: 16),
            OutlinedButton(
              onPressed: () {
                for (final a in HK.values) {
                  Prefs.setStr('hotkey.${a.name}', null);
                }
                setState(() {});
              },
              child: const Text('Reset defaults'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final a in HK.values)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(child: Text(hkLabels[a]!, style: const TextStyle(color: BMColors.text, fontSize: 14))),
                SizedBox(
                  width: 160,
                  child: OutlinedButton(
                    onPressed: () => _start(a),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _capturing == a ? BMColors.mango : BMColors.text,
                      side: BorderSide(color: _capturing == a ? BMColors.mango : BMColors.border),
                    ),
                    child: Text(
                      _capturing == a ? 'Press a key…' : keyName(Hotkeys.keyFor(a)),
                      style: const TextStyle(fontFamily: BMFonts.mono, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
