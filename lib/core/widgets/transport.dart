import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../hotkeys.dart';
import '../services.dart';
import '../storage/database.dart';

/// Remote-style buttons: ⏮ ↺ −30 −15 ⏯ +15 +30 ⏭, adapting to what's playing.
/// Episodes: previous/next episode. Live TV: previous/next channel. Movies: skips only.
/// [full] = the big player (±30 included). [width] lets a narrow player drop extras.
class TransportButtons extends StatelessWidget {
  const TransportButtons({super.key, required this.full, this.width = 9999, this.iconSize = 24});
  final bool full;
  final double width;
  final double iconSize;

  Widget _btn(String tip, VoidCallback onTap, {IconData? icon, Widget? child}) => IconButton(
        tooltip: tip,
        color: BMColors.controls,
        iconSize: iconSize,
        visualDensity: VisualDensity.compact,
        onPressed: onTap,
        icon: child ?? Icon(icon),
      );

  @override
  Widget build(BuildContext context) {
    final pb = Services.playback;
    return ValueListenableBuilder<Item?>(
      valueListenable: pb.current,
      builder: (context, cur, _) {
        final kind = cur?.kind ?? '';
        final live = kind == 'live';
        final ep = kind == 'episode';
        final vod = kind == 'movie' || ep;
        // A narrow full player drops the extras first, so the time bar keeps its room.
        final show30 = vod && full && width >= 760;
        final show15 = vod && (!full || width >= 560);
        final showRestart = vod && (!full || width >= 480);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (live) _btn('Previous channel (←)', () => Hotkeys.events.add(HK.channelPrev), icon: Icons.skip_previous),
            if (ep) _btn('Previous episode (←)', () => pb.prevEpisode(), icon: Icons.skip_previous),
            if (showRestart) _btn('Start over (R)', () => pb.restartCurrent(), icon: Icons.restart_alt),
            if (show30) _btn('Back 30 seconds (Shift+Page Down)', () => pb.skip(-30), icon: Icons.replay_30),
            if (show15) _btn('Back 15 seconds (Page Down)', () => pb.skip(-15), child: _Fifteen(back: true, size: iconSize)),
            StreamBuilder<bool>(
              stream: pb.player.stream.playing,
              initialData: pb.player.state.playing,
              builder: (context, s) {
                final playing = s.data ?? false;
                return _btn(playing ? 'Pause (Space)' : 'Play (Space)', () => pb.player.playOrPause(),
                    icon: playing ? Icons.pause : Icons.play_arrow);
              },
            ),
            if (show15) _btn('Forward 15 seconds (Page Up)', () => pb.skip(15), child: _Fifteen(back: false, size: iconSize)),
            if (show30) _btn('Forward 30 seconds (Shift+Page Up)', () => pb.skip(30), icon: Icons.forward_30),
            if (live) _btn('Next channel (→)', () => Hotkeys.events.add(HK.channelNext), icon: Icons.skip_next),
            if (ep) _btn('Next episode (→)', () => pb.nextEpisode(), icon: Icons.skip_next),
          ],
        );
      },
    );
  }
}

/// A "15" inside a circular arrow (there's no built-in 15-second icon).
class _Fifteen extends StatelessWidget {
  const _Fifteen({required this.back, required this.size});
  final bool back;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform(
            alignment: Alignment.center,
            transform: back ? Matrix4.identity() : Matrix4.diagonal3Values(-1, 1, 1),
            child: Icon(Icons.replay, size: size, color: BMColors.controls),
          ),
          Padding(
            padding: EdgeInsets.only(top: size * 0.14),
            child: Text('15',
                style: TextStyle(color: BMColors.controls, fontSize: size * 0.3, fontWeight: FontWeight.w700, height: 1)),
          ),
        ],
      ),
    );
  }
}

/// Compact time bar for the mini player and floating window.
class MiniTimeBar extends StatefulWidget {
  const MiniTimeBar({super.key});

  @override
  State<MiniTimeBar> createState() => _MiniTimeBarState();
}

class _MiniTimeBarState extends State<MiniTimeBar> {
  double? _drag;

  String _t(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final pl = Services.playback.player;
    return StreamBuilder<Duration>(
      stream: pl.stream.position,
      initialData: pl.state.position,
      builder: (context, ps) {
        final dur = pl.state.duration;
        final total = dur.inMilliseconds.toDouble();
        final raw = _drag ?? (ps.data ?? Duration.zero).inMilliseconds.toDouble();
        final pos = total <= 0 ? 0.0 : raw.clamp(0.0, total).toDouble();
        const style = TextStyle(color: Colors.white, fontSize: 11, fontFamily: BMFonts.mono);
        return Row(
          children: [
            Text(_t(Duration(milliseconds: pos.round())), style: style),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                  activeTrackColor: BMColors.mango,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: BMColors.mango,
                ),
                child: Slider(
                  value: pos,
                  max: total <= 0 ? 1 : total,
                  onChanged: total <= 0 ? null : (v) => setState(() => _drag = v),
                  onChangeEnd: (v) {
                    pl.seek(Duration(milliseconds: v.round()));
                    setState(() => _drag = null);
                  },
                ),
              ),
            ),
            Text(_t(dur), style: style),
          ],
        );
      },
    );
  }
}

/// "Up next · 7s" card with Play now / Cancel when an episode ends.
class UpNextCard extends StatelessWidget {
  const UpNextCard({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final pb = Services.playback;
    return AnimatedBuilder(
      animation: Listenable.merge([pb.upNext, pb.upNextIn]),
      builder: (context, _) {
        final n = pb.upNext.value;
        if (n == null) return const SizedBox.shrink();
        final i = n.name.indexOf('   ');
        final label = i >= 0 ? n.name.substring(i + 3) : n.name;
        return Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: EdgeInsets.fromLTRB(0, 0, compact ? 8 : 20, compact ? 64 : 84),
            child: Material(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: EdgeInsets.all(compact ? 8 : 14),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: compact ? 230 : 340),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Up next · ${pb.upNextIn.value}s',
                          style: TextStyle(color: BMColors.mango, fontSize: 12, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.white, fontSize: compact ? 12 : 14)),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FilledButton(onPressed: () => pb.playUpNext(), child: const Text('Play now')),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () => pb.cancelUpNext(),
                            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
