import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';
import '../../app/nav.dart';
import '../../app/theme.dart';
import '../catalog/display_name.dart';
import '../hotkeys.dart';
import '../prefs.dart';
import '../services.dart';
import '../storage/database.dart';
import 'player_controls.dart';
import 'track_menu.dart';
import 'transport.dart';

/// Which screen shows the full player for this kind of item.
int screenFor(Item i) => i.kind == 'live' ? AppNav.live : (i.kind == 'movie' ? AppNav.movies : AppNav.shows);

/// Closing a mini player: back to the full player, paused (not stopped).
Future<void> dockToFullPlayer() async {
  final cur = Services.playback.current.value;
  await Services.playback.player.pause();
  if (PopOut.active.value) await PopOut.exit();
  if (cur != null) AppNav.index.value = screenFor(cur);
}

/// The auto-float switch (same as Settings > Float when I switch to another app), as a button
/// on the full player and on the mini player. Mango when on.
class AutoFloatToggle extends StatelessWidget {
  final double size;
  const AutoFloatToggle({super.key, this.size = 22});

  static bool get isOn => !Prefs.getBool('mini.autoFloat.off');

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: Prefs.changes,
      builder: (context, _, _) {
        final on = isOn;
        return IconButton(
          tooltip: on
              ? 'Auto-float is on: the video floats when you switch apps. Click to turn it off.'
              : 'Auto-float is off. Click to turn it on.',
          onPressed: () {
            Prefs.setBool('mini.autoFloat.off', on);
            Services.playback.showNote(on ? 'Auto-float off' : 'Auto-float on');
          },
          icon: Icon(on ? Icons.flip_to_front : Icons.flip_to_back, size: size, color: on ? BMColors.mango : Colors.white70),
        );
      },
    );
  }
}

/// Pops out automatically when you click over to another app while something plays.
class _BlurWatcher with WindowListener {
  Timer? _saveT;

  /// Remembers the normal (not floating) window size and spot, so it reopens there.
  void _remember() {
    if (PopOut.active.value) return;
    _saveT?.cancel();
    _saveT = Timer(const Duration(milliseconds: 600), () async {
      if (PopOut.active.value) return;
      final b = await windowManager.getBounds();
      if (b.width >= 640 && b.height >= 400) {
        Prefs.setStr('window.bounds', '${b.left},${b.top},${b.width},${b.height}');
      }
    });
  }

  @override
  void onWindowResized() => _remember();

  @override
  void onWindowMoved() => _remember();

  @override
  void onWindowBlur() {
    if (Prefs.getBool('mini.autoFloat.off')) return;
    final p = Services.playback;
    if (PopOut.active.value || p.current.value == null || !p.player.state.playing || p.handedOff.value) return;
    if (BMControls.activeState?.isFullscreen() ?? false) return;
    debugPrint('[mini] switched apps, floating');
    PopOut.enter();
  }
}

/// Pop-out: shrink the whole window into a small always-on-top video window.
class PopOut {
  static final active = ValueNotifier<bool>(false);

  /// Minimized: the mini player (card or floating window) is a slim bar with the title,
  /// play/pause and close. No video; the sound keeps playing.
  static final slim = ValueNotifier<bool>(false);
  static const _slimSize = Size(380, 52);
  static const _floatSize = Size(480, 270);

  static Future<void> setSlim(bool v) async {
    if (slim.value == v) return;
    slim.value = v;
    if (!active.value) return; // the in-app card redraws itself
    try {
      // Keep the window's bottom-right corner where it is while it changes size.
      final b = await windowManager.getBounds();
      final s = v ? _slimSize : _floatSize;
      if (v) {
        await windowManager.setAspectRatio(0);
        await windowManager.setMinimumSize(const Size(260, 44));
      } else {
        await windowManager.setMinimumSize(const Size(256, 144));
      }
      await windowManager.setBounds(Rect.fromLTWH(b.right - s.width, b.bottom - s.height, s.width, s.height));
      if (!v) await windowManager.setAspectRatio(16 / 9);
    } catch (e) {
      debugPrint('[mini] resize failed: $e');
    }
  }
  static Rect? _saved;
  static bool _hooked = false;

  static void startAutoFloat() {
    windowManager.addListener(_BlurWatcher());
    _restoreWindow();
  }

  /// Opens at the last normal size. Never reopens floating-small.
  static Future<void> _restoreWindow() async {
    try {
      await windowManager.setMinimumSize(const Size(960, 600));
      final s = Prefs.getStr('window.bounds')?.split(',').map(double.tryParse).toList();
      if (s != null && s.length == 4 && !s.contains(null) && s[2]! >= 640 && s[3]! >= 400) {
        await windowManager.setBounds(Rect.fromLTWH(s[0]!, s[1]!, s[2]!, s[3]!));
      } else {
        final b = await windowManager.getBounds();
        if (b.width < 640 || b.height < 400) {
          await windowManager.setSize(const Size(1280, 800));
          await windowManager.center();
        }
      }
    } catch (e) {
      debugPrint('[mini] window restore failed: $e');
    }
  }

  static Future<void> enter() async {
    if (active.value || Services.playback.current.value == null) return;
    if (!_hooked) {
      _hooked = true;
      Services.playback.current.addListener(() {
        if (active.value && Services.playback.current.value == null) exit();
      });
    }
    try {
      _saved = await windowManager.getBounds();
      slim.value = false; // floating always starts with the video showing
      active.value = true;
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
      await windowManager.setMinimumSize(const Size(256, 144));
      await windowManager.setSize(const Size(480, 270));
      await windowManager.setAlignment(Alignment.bottomRight);
      await windowManager.setAspectRatio(16 / 9);
      await windowManager.setAlwaysOnTop(true);
      try {
        await windowManager.setVisibleOnAllWorkspaces(true);
      } catch (_) {}
      debugPrint('[mini] popped out');
    } catch (e) {
      debugPrint('[mini] pop-out failed: $e');
      await exit();
    }
  }

  /// Floating window -> full app, on the screen that shows this video (not the mini card).
  static Future<void> backToFull() async {
    await exit();
    final cur = Services.playback.current.value;
    if (cur != null) AppNav.index.value = screenFor(cur);
  }

  static Future<void> exit() async {
    if (!active.value) return;
    active.value = false;
    slim.value = false;
    try {
      await windowManager.setAlwaysOnTop(false);
      try {
        await windowManager.setVisibleOnAllWorkspaces(false);
      } catch (_) {}
      await windowManager.setAspectRatio(0);
      await windowManager.setTitleBarStyle(TitleBarStyle.normal);
      await windowManager.setMinimumSize(const Size(960, 600));
      final s = _saved;
      if (s != null) await windowManager.setBounds(s);
      await windowManager.focus();
      debugPrint('[mini] restored');
    } catch (e) {
      debugPrint('[mini] restore failed: $e');
    }
  }
}

/// Puts the mini player layer above every screen (installed once).
class MiniPlayerHost {
  static OverlayEntry? _entry;

  static void install(BuildContext context) {
    if (_entry != null) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _entry = OverlayEntry(builder: (_) => const _MiniLayer());
    overlay.insert(_entry!);
  }
}

class _MiniLayer extends StatefulWidget {
  const _MiniLayer();

  @override
  State<_MiniLayer> createState() => _MiniLayerState();
}

class _MiniLayerState extends State<_MiniLayer> {
  static const _w = 340.0, _h = 191.0, _barH = 48.0;

  @override
  void initState() {
    super.initState();
    AppNav.index.addListener(_unslimOnFull);
    Services.playback.current.addListener(_unslimOnFull);
  }

  @override
  void dispose() {
    AppNav.index.removeListener(_unslimOnFull);
    Services.playback.current.removeListener(_unslimOnFull);
    super.dispose();
  }

  /// Back on the full player, or nothing playing: the next mini player shows the video again.
  void _unslimOnFull() {
    final cur = Services.playback.current.value;
    if (PopOut.active.value) return;
    if (cur == null || AppNav.index.value == screenFor(cur)) PopOut.slim.value = false;
  }

  /// Minimized mini player: title, play/pause, close. Sound keeps playing.
  Widget _slimBar(Item cur, {required bool popped}) {
    Widget b(IconData icon, String tip, VoidCallback onTap) => IconButton(
          tooltip: tip,
          onPressed: onTap,
          icon: Icon(icon, color: BMColors.text, size: 20),
        );
    return Material(
      color: BMColors.surface,
      elevation: popped ? 0 : 12,
      borderRadius: popped ? null : BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          b(Icons.open_in_full, 'Show the video again', () => PopOut.setSlim(false)),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: popped ? (_) => windowManager.startDragging() : null,
              onDoubleTap: () => PopOut.setSlim(false),
              child: Text(
                displayName(cur.name).title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: BMColors.text, fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ),
          StreamBuilder<bool>(
            stream: Services.playback.player.stream.playing,
            initialData: Services.playback.player.state.playing,
            builder: (context, snap) => b(
              snap.data == true ? Icons.pause : Icons.play_arrow,
              snap.data == true ? 'Pause' : 'Play',
              () => Services.playback.player.playOrPause(),
            ),
          ),
          b(Icons.close, 'Close (stops playback)', () => Services.playback.stop()),
        ],
      ),
    );
  }
  Offset? _pos;
  bool _dragging = false;
  bool _hover = false;
  bool _controlsUp = false;
  bool _fading = false;
  Timer? _fadeT;
  Timer? _hideT;

  /// Controls appear the instant the mouse arrives.
  void _hoverOn() {
    _fadeT?.cancel();
    _hideT?.cancel();
    setState(() {
      _hover = true;
      _controlsUp = true;
      _fading = false;
    });
  }

  /// They stay 10 seconds after the mouse leaves, fading over the last 1.5.
  void _hoverOff() {
    setState(() => _hover = false);
    _fadeT?.cancel();
    _hideT?.cancel();
    _fadeT = Timer(const Duration(milliseconds: 8500), () {
      if (mounted) setState(() => _fading = true);
    });
    _hideT = Timer(const Duration(seconds: 10), () {
      if (mounted) {
        setState(() {
          _controlsUp = false;
          _fading = false;
        });
      }
    });
  }

  Widget _fade(Widget c) => AnimatedOpacity(
        opacity: _fading ? 0 : 1,
        duration: _fading ? const Duration(milliseconds: 1500) : Duration.zero,
        child: c,
      );


  Widget _video() => Video(
        controller: Services.playback.controller,
        controls: NoVideoControls,
        subtitleViewConfiguration: const SubtitleViewConfiguration(visible: false),
      );

  Widget _btn(IconData icon, String tip, VoidCallback onTap) => IconButton(
        tooltip: tip,
        onPressed: onTap,
        icon: Icon(icon, color: Colors.white, size: 20),
      );

  void _seek(int secs) {
    final pl = Services.playback.player;
    final t = pl.state.position + Duration(seconds: secs);
    pl.seek(t < Duration.zero ? Duration.zero : t);
  }

  bool _entering = false;
  final _numCtrl = TextEditingController();

  /// Opens a small Channel # box on the video itself (dialogs would hide behind the floating video).
  Future<void> _askNumber(BuildContext context) async {
    await windowManager.focus(); // so typing goes here, not to the app underneath
    _numCtrl.clear();
    if (mounted) setState(() => _entering = true);
  }

  void _submitNumber() {
    final n = int.tryParse(_numCtrl.text.trim());
    setState(() => _entering = false);
    if (n != null && n > 0) Hotkeys.gotoChannel.add(n);
  }

  Widget _numberBox() => Center(
        child: Material(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            child: SizedBox(
              width: 210,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _numCtrl,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white, fontSize: 18),
                      decoration: const InputDecoration(
                        hintText: 'Channel #',
                        hintStyle: TextStyle(color: Colors.white54),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      onSubmitted: (_) => _submitNumber(),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Go',
                    onPressed: _submitNumber,
                    icon: const Icon(Icons.check, color: Colors.white, size: 20),
                  ),
                  IconButton(
                    tooltip: 'Cancel',
                    onPressed: () => setState(() => _entering = false),
                    icon: const Icon(Icons.close, color: Colors.white, size: 20),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _topBar(Item cur, {required bool popped}) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xAA000000), Color(0x00000000)],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          const AutoFloatToggle(size: 20),
          _btn(Icons.minimize, 'Minimize to a slim bar (sound keeps playing)', () => PopOut.setSlim(true)),
          if (popped)
            _btn(Icons.close_fullscreen, 'Back to the full player', () => PopOut.backToFull())
          else ...[
            _btn(Icons.open_in_full, 'Back to the full player', () => AppNav.index.value = screenFor(cur)),
            _btn(Icons.picture_in_picture_alt, 'Float over other apps', () => PopOut.enter()),
          ],
          _btn(Icons.close, 'Close (stops playback, stays on this screen)', () => Services.playback.stop()),
        ],
      ),
    );
  }

  Widget _bottomBar(BuildContext context, Item cur) {
    final live = cur.kind == 'live';
    return Container(
      padding: const EdgeInsets.fromLTRB(2, 12, 6, 2),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xCC000000), Color(0x00000000)],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!live) const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: MiniTimeBar()),
          Row(
            children: [
              const TransportButtons(full: false, iconSize: 20),
              const Spacer(),
              if (live) _btn(Icons.dialpad, 'Go to channel number (or just type the digits)', () => _askNumber(context)),
              const VolumeButton(),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _overlays(BuildContext context, Item cur, {required bool popped}) => [
        const Positioned.fill(child: IgnorePointer(child: ChannelNumberBadge())),
        if (_entering) Positioned.fill(child: _numberBox()),
        const Positioned.fill(child: UpNextCard(compact: true)),
        if (_controlsUp && !_dragging) ...[
          Positioned(top: 0, left: 0, right: 0, child: _fade(_topBar(cur, popped: popped))),
          Positioned(bottom: 0, left: 0, right: 0, child: _fade(_bottomBar(context, cur))),
        ],
      ];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([Services.playback.current, AppNav.index, PopOut.active, PopOut.slim]),
      builder: (context, _) {
        final cur = Services.playback.current.value;
        if (cur == null) return const SizedBox.shrink();

        // Popped out and minimized: the whole (slim, always-on-top) window is the bar.
        if (PopOut.active.value && PopOut.slim.value) return _slimBar(cur, popped: true);

        // Popped out: the whole (small, always-on-top) window is the video.
        if (PopOut.active.value) {
          return Listener(
            // A click makes Black Mango the active app, so typed channel numbers reach it.
            onPointerDown: (_) => windowManager.focus(),
            child: Material(
            color: Colors.black,
            child: MouseRegion(
              onEnter: (_) => _hoverOn(),
              onExit: (_) => _hoverOff(),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _video(),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (_) => windowManager.startDragging(),
                    onDoubleTap: () => PopOut.backToFull(),
                  ),
                  ..._overlays(context, cur, popped: true),
                ],
              ),
            ),
          ));
        }

        // On the screen that already shows this video: no mini card needed.
        if (AppNav.index.value == screenFor(cur)) return const SizedBox.shrink();

        // Floating card. Drag it past the window's edge to pop it out over other apps.
        return LayoutBuilder(
          builder: (context, box) {
            final slim = PopOut.slim.value;
            final h = slim ? _barH : _h;
            Offset clampIn(Offset o) => Offset(
                  o.dx.clamp(0.0, (box.maxWidth - _w).clamp(0.0, double.infinity)).toDouble(),
                  o.dy.clamp(0.0, (box.maxHeight - h).clamp(0.0, double.infinity)).toDouble(),
                );
            final def = Offset(box.maxWidth - _w - 20, box.maxHeight - h - 20);
            final raw = _pos ?? def;
            final p = _dragging ? raw : clampIn(raw);
            return Stack(
              children: [
                Positioned(
                  left: p.dx,
                  top: p.dy,
                  width: _w,
                  height: h,
                  child: MouseRegion(
                    onEnter: (_) => _hoverOn(),
                    onExit: (_) => _hoverOff(),
                    child: GestureDetector(
                      onPanStart: (_) => setState(() {
                        _dragging = true;
                        _pos = p;
                      }),
                      onPanUpdate: (d) => setState(() => _pos = (_pos ?? p) + d.delta),
                      onPanEnd: (_) {
                        final o = _pos ?? p;
                        final offEdge = o.dx < -_w * 0.4 ||
                            o.dx > box.maxWidth - _w * 0.6 ||
                            o.dy < -h * 0.4 ||
                            o.dy > box.maxHeight - h * 0.6;
                        setState(() {
                          _dragging = false;
                          _pos = offEdge ? null : clampIn(o);
                        });
                        if (offEdge) PopOut.enter();
                      },
                      onDoubleTap: () => AppNav.index.value = screenFor(cur),
                      child: slim
                          ? _slimBar(cur, popped: false)
                          : Material(
                        elevation: 12,
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(12),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _video(),
                            ..._overlays(context, cur, popped: false),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
