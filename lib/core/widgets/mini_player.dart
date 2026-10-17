import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';
import '../../app/nav.dart';
import '../prefs.dart';
import '../services.dart';
import '../storage/database.dart';
import 'player_controls.dart';

/// Which screen shows the full player for this kind of item.
int screenFor(Item i) => i.kind == 'live' ? AppNav.live : (i.kind == 'movie' ? AppNav.movies : AppNav.shows);

/// Closing a mini player: back to the full player, paused (not stopped).
Future<void> dockToFullPlayer() async {
  final cur = Services.playback.current.value;
  await Services.playback.player.pause();
  if (PopOut.active.value) await PopOut.exit();
  if (cur != null) AppNav.index.value = screenFor(cur);
}

/// Pops out automatically when you click over to another app while something plays.
class _BlurWatcher with WindowListener {
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
  static Rect? _saved;
  static bool _hooked = false;

  static void startAutoFloat() => windowManager.addListener(_BlurWatcher());

  static Future<void> enter() async {
    if (active.value || Services.playback.current.value == null) return;
    if (!_hooked) {
      _hooked = true;
      // Playback stopped while popped out: bring the full window back.
      Services.playback.current.addListener(() {
        if (active.value && Services.playback.current.value == null) exit();
      });
    }
    try {
      _saved = await windowManager.getBounds();
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

  static Future<void> exit() async {
    if (!active.value) return;
    active.value = false;
    try {
      await windowManager.setAlwaysOnTop(false);
      try {
        await windowManager.setVisibleOnAllWorkspaces(false);
      } catch (_) {}
      await windowManager.setAspectRatio(0);
      await windowManager.setTitleBarStyle(TitleBarStyle.normal);
      await windowManager.setMinimumSize(const Size(640, 400));
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
  static const _w = 340.0, _h = 191.0;
  Offset? _pos;
  bool _dragging = false;
  bool _hover = false;

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

  Widget _controls(Item cur, {required bool popped}) {
    final pl = Services.playback.player;
    return StreamBuilder<bool>(
      stream: pl.stream.playing,
      initialData: pl.state.playing,
      builder: (context, snap) {
        final playing = snap.data ?? false;
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
              _btn(playing ? Icons.pause : Icons.play_arrow, playing ? 'Pause' : 'Play', () => pl.playOrPause()),
              if (popped)
                _btn(Icons.close_fullscreen, 'Back to Black Mango (keeps playing)', () => PopOut.exit())
              else ...[
                _btn(Icons.open_in_full, 'Back to the full player', () => AppNav.index.value = screenFor(cur)),
                _btn(Icons.picture_in_picture_alt, 'Float over other apps', () => PopOut.enter()),
              ],
              _btn(Icons.close, 'Close mini player (pauses)', () => dockToFullPlayer()),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([Services.playback.current, AppNav.index, PopOut.active]),
      builder: (context, _) {
        final cur = Services.playback.current.value;
        if (cur == null) return const SizedBox.shrink();

        // Popped out: the whole (small, always-on-top) window is the video.
        if (PopOut.active.value) {
          return Material(
            color: Colors.black,
            child: MouseRegion(
              onEnter: (_) => setState(() => _hover = true),
              onExit: (_) => setState(() => _hover = false),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _video(),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (_) => windowManager.startDragging(),
                    onDoubleTap: () => PopOut.exit(),
                  ),
                  if (_hover) Positioned(top: 0, left: 0, right: 0, child: _controls(cur, popped: true)),
                ],
              ),
            ),
          );
        }

        // On the screen that already shows this video: no mini card needed.
        if (AppNav.index.value == screenFor(cur)) return const SizedBox.shrink();

        // Floating card. Drag it past the window's edge to pop it out over other apps.
        return LayoutBuilder(
          builder: (context, box) {
            Offset clampIn(Offset o) => Offset(
                  o.dx.clamp(0.0, (box.maxWidth - _w).clamp(0.0, double.infinity)).toDouble(),
                  o.dy.clamp(0.0, (box.maxHeight - _h).clamp(0.0, double.infinity)).toDouble(),
                );
            final def = Offset(box.maxWidth - _w - 20, box.maxHeight - _h - 20);
            final raw = _pos ?? def;
            final p = _dragging ? raw : clampIn(raw);
            return Stack(
              children: [
                Positioned(
                  left: p.dx,
                  top: p.dy,
                  width: _w,
                  height: _h,
                  child: MouseRegion(
                    onEnter: (_) => setState(() => _hover = true),
                    onExit: (_) => setState(() => _hover = false),
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
                            o.dy < -_h * 0.4 ||
                            o.dy > box.maxHeight - _h * 0.6;
                        setState(() {
                          _dragging = false;
                          _pos = offEdge ? null : clampIn(o);
                        });
                        if (offEdge) PopOut.enter();
                      },
                      onDoubleTap: () => AppNav.index.value = screenFor(cur),
                      child: Material(
                        elevation: 12,
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(12),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _video(),
                            if (_hover && !_dragging)
                              Positioned(top: 0, left: 0, right: 0, child: _controls(cur, popped: false)),
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
