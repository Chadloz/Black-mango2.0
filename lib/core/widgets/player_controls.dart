import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../app/theme.dart';
import '../services.dart';
import 'track_menu.dart';
import '../playback/still_watching.dart';
import 'mini_player.dart';
import '../hotkeys.dart';

String _time(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

/// Black Mango's own player controls (replaces media_kit's, which crashed during reconnect loops).
/// Space play/pause, arrows seek/volume, F fullscreen, M mute, Esc exit fullscreen.
class BMControls extends StatefulWidget {
  final VideoState state;
  final double rightInset; // room for a close button on the panel
  /// The video on screen right now, for app-wide hotkeys (fullscreen, Esc).
  static VideoState? activeState;
  const BMControls({super.key, required this.state, this.rightInset = 0});

  @override
  State<BMControls> createState() => _BMControlsState();
}

class _BMControlsState extends State<BMControls> {
  final _focus = FocusNode();
  final _subs = <StreamSubscription>[];
  bool _visible = true;
  bool _playing = false;
  double? _drag; // seek position while dragging, in ms
  Timer? _hide;

  dynamic get _p => Services.playback.player;
  bool get _live => Services.playback.current.value?.kind == 'live';

  @override
  void initState() {
    super.initState();
    _playing = _p.state.playing;
    _subs.add(_p.stream.playing.listen((v) {
      if (!mounted) return;
      setState(() => _playing = v);
      _kick();
    }));
    _kick();
  }

  @override
  void dispose() {
    if (BMControls.activeState == widget.state) BMControls.activeState = null;
    _hide?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _focus.dispose();
    super.dispose();
  }

  /// Show controls, then hide them after 3 idle seconds while playing.
  void _kick() {
    if (!mounted) return;
    if (!_visible) setState(() => _visible = true);
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && _p.state.playing && _drag == null) setState(() => _visible = false);
    });
  }

  void _toggle() {
    _p.playOrPause();
    _kick();
  }

  void _seekBy(int secs) {
    if (_live) return;
    final Duration cur = _p.state.position;
    final next = cur + Duration(seconds: secs);
    _p.seek(next < Duration.zero ? Duration.zero : next);
    _kick();
  }

  void _volBy(double d) {
    final double v = _p.state.volume;
    Services.playback.setVolume((v + d).clamp(0.0, 150.0).toDouble());
    _kick();
  }

  @override
  Widget build(BuildContext context) {
    final fs = widget.state.isFullscreen();
    BMControls.activeState = widget.state;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): _toggle,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _seekBy(-10),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _seekBy(10),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _volBy(5),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _volBy(-5),
        const SingleActivator(LogicalKeyboardKey.keyF): () => widget.state.toggleFullscreen(),
        const SingleActivator(LogicalKeyboardKey.keyM): () => Services.playback.toggleMute(),
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (widget.state.isFullscreen()) widget.state.exitFullscreen();
        },
      },
      child: Focus(
        focusNode: _focus,
        autofocus: fs,
        child: MouseRegion(
          onHover: (_) => _kick(),
          cursor: _visible ? SystemMouseCursors.basic : SystemMouseCursors.none,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              _focus.requestFocus();
              _toggle();
            },
            onDoubleTap: () => widget.state.toggleFullscreen(),
            child: Stack(
              children: [
                const Positioned.fill(child: ColoredBox(color: Colors.transparent)),
                Positioned(
                  top: 8,
                  right: 8 + widget.rightInset,
                  child: _fade(
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [VolumeButton(), SizedBox(width: 8), TrackMenu(), SizedBox(width: 8), PlayerMoreMenu()],
                    ),
                  ),
                ),
                Positioned(left: 0, right: 0, bottom: 0, child: _fade(_bar(fs))),
                const Positioned.fill(child: IgnorePointer(child: ChannelNumberBadge())),
                const Positioned.fill(child: StillWatchingOverlay()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fade(Widget child) => AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(ignoring: !_visible, child: child),
      );

  Widget _bar(bool fs) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 28, 8, 6),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xCC000000), Color(0x00000000)],
        ),
      ),
      child: LayoutBuilder(builder: (context, box) {
        final narrow = box.maxWidth < 360; // small player: drop the float button (P still works)
        return Row(
        children: [
          IconButton(
            tooltip: _playing ? 'Pause (Space)' : 'Play (Space)',
            color: Colors.white,
            onPressed: _toggle,
            icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
          ),
          const SizedBox(width: 4),
          Expanded(child: _live ? _liveBadge() : _seekBar()),
          if (!fs && !narrow)
            IconButton(
              tooltip: 'Float over other apps (P)',
              color: Colors.white,
              onPressed: () => PopOut.enter(),
              icon: const Icon(Icons.picture_in_picture_alt),
            ),
          IconButton(
            tooltip: fs ? 'Exit fullscreen (F)' : 'Fullscreen (F)',
            color: Colors.white,
            onPressed: () => widget.state.toggleFullscreen(),
            icon: Icon(fs ? Icons.fullscreen_exit : Icons.fullscreen),
          ),
        ],
      );
      }),
    );
  }

  Widget _liveBadge() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: const Color(0xFFD32F2F), borderRadius: BorderRadius.circular(4)),
          child: const Text('LIVE',
              style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
        ),
      ],
    );
  }

  Widget _seekBar() {
    const style = TextStyle(color: Colors.white, fontFamily: BMFonts.mono, fontSize: 12);
    return StreamBuilder<Duration>(
      stream: _p.stream.position,
      initialData: _p.state.position,
      builder: (context, snap) {
        final Duration dur = _p.state.duration;
        final pos = snap.data ?? Duration.zero;
        final maxMs = dur.inMilliseconds.toDouble();
        final ready = maxMs > 0;
        final val = ready ? (_drag ?? pos.inMilliseconds.toDouble()).clamp(0.0, maxMs).toDouble() : 0.0;
        return LayoutBuilder(builder: (context, box) {
          final showTimes = box.maxWidth > 200; // tiny player: just the seek bar
          return Row(
          children: [
            if (showTimes) Text(_time(Duration(milliseconds: val.round())), style: style),
            Expanded(
              child: Slider(
                value: val,
                max: ready ? maxMs : 1,
                onChangeStart: ready ? (v) => setState(() => _drag = v) : null,
                onChanged: ready
                    ? (v) {
                        setState(() => _drag = v);
                        _kick();
                      }
                    : null,
                onChangeEnd: ready
                    ? (v) {
                        _p.seek(Duration(milliseconds: v.round()));
                        setState(() => _drag = null);
                      }
                    : null,
              ),
            ),
            if (showTimes) Text(_time(dur), style: style),
          ],
        );
        });
      },
    );
  }
}
