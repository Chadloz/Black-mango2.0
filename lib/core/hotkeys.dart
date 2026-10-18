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
  seekBack30,
  seekForward30,
  restart,
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
  HK.playSelected: 'Play the highlighted channel',
  HK.fullscreen: 'Fullscreen',
  HK.mute: 'Mute',
  HK.volumeUp: 'Volume up',
  HK.volumeDown: 'Volume down',
  HK.seekBack: 'Back 15 seconds',
  HK.seekForward: 'Forward 15 seconds',
  HK.seekBack30: 'Back 30 seconds',
  HK.seekForward30: 'Forward 30 seconds',
  HK.restart: 'Start over',
  HK.closePlayer: 'Close player (leaves fullscreen or floating first)',
  HK.backToLast: 'Back to last screen',
  HK.navUp: 'Move highlight up',
  HK.navDown: 'Move highlight down',
  HK.channelNext: 'Next episode / channel',
  HK.channelPrev: 'Previous episode / channel',
  HK.popOut: 'Float over other apps (and back)',
};

/// Added to a key id to mean "with Shift held".
const shiftBit = 1 << 48;

final _defaults = <HK, int>{
  HK.playPause: LogicalKeyboardKey.space.keyId,
  HK.playSelected: LogicalKeyboardKey.enter.keyId,
  HK.fullscreen: LogicalKeyboardKey.keyF.keyId,
  HK.mute: LogicalKeyboardKey.keyM.keyId,
  HK.volumeUp: LogicalKeyboardKey.equal.keyId,
  HK.volumeDown: LogicalKeyboardKey.minus.keyId,
  HK.seekForward: LogicalKeyboardKey.pageUp.keyId,
  HK.seekBack: LogicalKeyboardKey.pageDown.keyId,
  HK.seekForward30: LogicalKeyboardKey.pageUp.keyId | shiftBit,
  HK.seekBack30: LogicalKeyboardKey.pageDown.keyId | shiftBit,
  HK.restart: LogicalKeyboardKey.keyR.keyId,
  HK.closePlayer: LogicalKeyboardKey.escape.keyId,
  HK.backToLast: LogicalKeyboardKey.tab.keyId,
  HK.navUp: LogicalKeyboardKey.arrowUp.keyId,
  HK.navDown: LogicalKeyboardKey.arrowDown.keyId,
  HK.channelPrev: LogicalKeyboardKey.arrowLeft.keyId,
  HK.channelNext: LogicalKeyboardKey.arrowRight.keyId,
  HK.popOut: LogicalKeyboardKey.keyP.keyId,
};

/// How Settings groups the shortcuts: (title, note, actions).
const hkSections = <(String, String, List<HK>)>[
  ('APP', '', [HK.backToLast]),
  (
    'PLAYER',
    'Work in the full player, the mini player and the floating window.',
    [
      HK.playPause,
      HK.seekBack,
      HK.seekForward,
      HK.seekBack30,
      HK.seekForward30,
      HK.channelPrev,
      HK.channelNext,
      HK.restart,
      HK.volumeUp,
      HK.volumeDown,
      HK.mute,
      HK.fullscreen,
      HK.closePlayer,
    ]
  ),
  ('MINI PLAYER', '', [HK.popOut]),
  ('LIVE TV', 'While a channel plays, type its number to jump to it.', [HK.navUp, HK.navDown, HK.playSelected]),
];

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
    LogicalKeyboardKey.home: 'Home',
    LogicalKeyboardKey.end: 'End',
    LogicalKeyboardKey.equal: '+ / =',
    LogicalKeyboardKey.minus: '−',
  };
  final n = names[k];
  if (n != null) return n;
  final l = k.keyLabel.trim();
  return l.isEmpty ? 'Key ${k.keyId}' : l.toUpperCase();
}

/// "Shift+Page Up" for a stored binding.
String bindingName(int b) {
  final k = LogicalKeyboardKey.findKeyByKeyId(b & ~shiftBit);
  final base = k == null ? '?' : keyName(k);
  return (b & shiftBit) != 0 ? 'Shift+$base' : base;
}

/// App-wide hotkeys. Ignored while typing in a text box; Cmd/Ctrl/Alt combos are left alone.
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
        debugPrint('[nav] screen $_cur -> ${AppNav.index.value}');
        _prev = _cur;
        _cur = AppNav.index.value;
      }
    });
  }

  /// The key (plus Shift flag) bound to an action.
  static int bindingFor(HK a) {
    final v = Prefs.getInt('hotkey.${a.name}');
    if (v == null || LogicalKeyboardKey.findKeyByKeyId(v & ~shiftBit) == null) return _defaults[a]!;
    return v;
  }

  /// The plain key for an action (older callers).
  static LogicalKeyboardKey keyFor(HK a) =>
      LogicalKeyboardKey.findKeyByKeyId(bindingFor(a) & ~shiftBit) ?? LogicalKeyboardKey.space;

  static bool isModifier(LogicalKeyboardKey k) => _modifiers.contains(k);

  static bool _typing() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    return ctx.widget is EditableText || ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  static const _repeatable = {
    HK.volumeUp, HK.volumeDown, HK.seekBack, HK.seekForward, HK.seekBack30, HK.seekForward30, HK.navUp, HK.navDown,
  };

  static bool _handle(KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return false;
    if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.enter) {
      final f = FocusManager.instance.primaryFocus;
      debugPrint('[keys] Enter on screen ${AppNav.index.value}: typing=${_typing()} capturing=$capturing focus=${f?.context?.widget.runtimeType}');
    }
    if (capturing || _typing()) return false;
    final hw = HardwareKeyboard.instance;
    if (hw.isMetaPressed || hw.isControlPressed || hw.isAltPressed) return false;
    final pressed = e.logicalKey.keyId | (hw.isShiftPressed ? shiftBit : 0);
    for (final a in HK.values) {
      if (bindingFor(a) == pressed) {
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
      case HK.seekBack30:
      case HK.seekForward30:
        if (cur == null || live) return false;
        p.skip(switch (a) {
          HK.seekBack => -15,
          HK.seekForward => 15,
          HK.seekBack30 => -30,
          _ => 30,
        });
        return true;
      case HK.restart:
        if (cur == null || live) return false;
        p.restartCurrent();
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
      case HK.channelNext:
      case HK.channelPrev:
        // Previous/next: episodes when watching a show, channels on live TV.
        if (cur?.kind == 'episode') {
          a == HK.channelNext ? p.nextEpisode() : p.prevEpisode();
          return true;
        }
        if (!live) return false;
        events.add(a);
        return true;
      default:
        events.add(a); // list navigation and Enter: handled by Live TV
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

/// Settings: shortcuts grouped by where they matter. Click one, press the new key
/// (hold Shift for a Shift combo). Esc cancels.
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
    if (e.logicalKey != LogicalKeyboardKey.escape) {
      final shift = HardwareKeyboard.instance.isShiftPressed;
      Prefs.setInt('hotkey.${a.name}', e.logicalKey.keyId | (shift ? shiftBit : 0));
    }
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
    // Which actions share a key, so we can warn about it.
    final byKey = <int, List<HK>>{};
    for (final a in HK.values) {
      byKey.putIfAbsent(Hotkeys.bindingFor(a), () => []).add(a);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Click a shortcut, then press the new key. Hold Shift while pressing it for a Shift combo. Esc cancels. Shortcuts work anywhere except while typing in a text box.',
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
        for (final (title, note, actions) in hkSections) ...[
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 4),
            child: Text(title,
                style: const TextStyle(fontFamily: BMFonts.mono, fontSize: 11, letterSpacing: 1.5, color: BMColors.mango)),
          ),
          if (note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(note, style: const TextStyle(color: BMColors.dim, fontSize: 12)),
            ),
          for (final a in actions)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(hkLabels[a]!, style: const TextStyle(color: BMColors.text, fontSize: 14)),
                        if ((byKey[Hotkeys.bindingFor(a)]?.length ?? 0) > 1)
                          Text(
                            'Same key as: ${byKey[Hotkeys.bindingFor(a)]!.where((o) => o != a).map((o) => hkLabels[o]).join(', ')}',
                            style: const TextStyle(color: Colors.orangeAccent, fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 170,
                    child: OutlinedButton(
                      onPressed: () => _start(a),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _capturing == a ? BMColors.mango : BMColors.text,
                        side: BorderSide(color: _capturing == a ? BMColors.mango : BMColors.border),
                      ),
                      child: Text(
                        _capturing == a ? 'Press a key…' : bindingName(Hotkeys.bindingFor(a)),
                        style: const TextStyle(fontFamily: BMFonts.mono, fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
