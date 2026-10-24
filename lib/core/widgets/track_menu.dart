import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import '../../app/theme.dart';
import '../services.dart';
import 'mini_player.dart';
import '../../app/nav.dart';
import '../playback/vod_failover.dart';

const _langs = {
  'en': 'English', 'eng': 'English', 'es': 'Spanish', 'spa': 'Spanish', 'fr': 'French', 'fre': 'French',
  'fra': 'French', 'de': 'German', 'ger': 'German', 'deu': 'German', 'it': 'Italian', 'ita': 'Italian',
  'pt': 'Portuguese', 'por': 'Portuguese', 'ar': 'Arabic', 'ara': 'Arabic', 'ru': 'Russian', 'rus': 'Russian',
  'ja': 'Japanese', 'jpn': 'Japanese', 'ko': 'Korean', 'kor': 'Korean', 'zh': 'Chinese', 'chi': 'Chinese',
  'zho': 'Chinese', 'hi': 'Hindi', 'hin': 'Hindi', 'pl': 'Polish', 'pol': 'Polish', 'tr': 'Turkish',
  'tur': 'Turkish', 'nl': 'Dutch', 'dut': 'Dutch', 'nld': 'Dutch', 'sv': 'Swedish', 'swe': 'Swedish',
  'el': 'Greek', 'gre': 'Greek', 'ell': 'Greek', 'he': 'Hebrew', 'heb': 'Hebrew', 'ro': 'Romanian', 'rum': 'Romanian',
};

String _label(String? title, String? lang, int i) {
  final l = lang == null ? '' : (_langs[lang.toLowerCase()] ?? lang);
  final t = title ?? '';
  final parts = [l, t].where((s) => s.trim().isNotEmpty).toList();
  return parts.isEmpty ? 'Track ${i + 1}' : parts.join(' · ');
}

/// Volume: 0 to 150%, plus mute. Remembered between launches.
class VolumeButton extends StatelessWidget {
  const VolumeButton({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Services.playback.player;
    return StreamBuilder<double>(
      stream: p.stream.volume,
      initialData: p.state.volume,
      builder: (context, snap) {
        final v = (snap.data ?? 100).clamp(0.0, 150.0).toDouble();
        final icon = v == 0 ? Icons.volume_off : (v < 50 ? Icons.volume_down : Icons.volume_up);
        return MenuAnchor(
      consumeOutsideTap: true,
          menuChildren: [
            SizedBox(
              width: 300,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: v == 0 ? 'Unmute' : 'Mute',
                      onPressed: () => Services.playback.toggleMute(),
                      icon: Icon(icon),
                    ),
                    Expanded(
                      child: Slider(
                        value: v,
                        min: 0,
                        max: 150,
                        divisions: 30,
                        onChanged: (x) => Services.playback.setVolume(x),
                      ),
                    ),
                    SizedBox(
                      width: 46,
                      child: Text('${v.round()}%',
                          textAlign: TextAlign.right,
                          style: TextStyle(fontFamily: BMFonts.mono, fontSize: 12, color: BMColors.text)),
                    ),
                  ],
                ),
              ),
            ),
          ],
          builder: (context, ctrl, _) => IconButton.filledTonal(
            tooltip: 'Volume',
            onPressed: () => ctrl.isOpen ? ctrl.close() : ctrl.open(),
            icon: Icon(icon),
          ),
        );
      },
    );
  }
}

/// Shown over the video while the stream is playing in VLC instead.
class HandOffOverlay extends StatelessWidget {
  const HandOffOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Services.playback.handedOff,
      builder: (context, on, _) {
        if (!on) return const SizedBox.shrink();
        return Container(
          color: Colors.black87,
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.open_in_new, size: 40, color: BMColors.mango),
              const SizedBox(height: 12),
              const Text('Playing in VLC',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  final c = Services.playback.current.value;
                  if (c != null) Services.playback.play(c);
                },
                icon: const Icon(Icons.play_arrow),
                label: const Text('Resume here'),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The ⋯ menu on the video: open the stream in VLC, or copy its link.
class PlayerMoreMenu extends StatelessWidget {
  const PlayerMoreMenu({super.key});

  Future<void> _copy(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final cur = Services.playback.current.value;
    if (cur == null) return;
    final url = await Services.playback.urlFor(cur);
    await Clipboard.setData(ClipboardData(text: url));
    messenger.showSnackBar(const SnackBar(content: Text('Stream link copied. In VLC: File > Open Network, then paste.')));
  }

  Future<void> _vlc(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final cur = Services.playback.current.value;
    if (cur == null) return;
    final url = await Services.playback.urlFor(cur);
    // Only real stream links go to VLC: a "link" starting with a dash would be read as a VLC
    // option. (Security review, Oct 2026.)
    const streamSchemes = {'http', 'https', 'rtmp', 'rtmps', 'rtsp', 'rtp', 'udp', 'mms'};
    if (!streamSchemes.contains(Uri.tryParse(url)?.scheme.toLowerCase())) {
      messenger.showSnackBar(const SnackBar(content: Text('That link can\'t be opened in VLC.')));
      return;
    }
    await Clipboard.setData(ClipboardData(text: url)); // backup in case the launch fails
    final pos = Services.playback.player.state.position.inSeconds;
    final live = cur.kind == 'live';
    // Step aside (panel stays open) so one-connection accounts don't refuse VLC.
    await Services.playback.handOff();
    await Future.delayed(const Duration(milliseconds: 800)); // let the provider register the hang-up
    final vlcArgs = [if (!live && pos > 5) '--start-time=$pos', url];
    try {
      if (Platform.isWindows) {
        // VLC installs under Program Files (64-bit) or Program Files (x86).
        final exe = [Platform.environment['ProgramFiles'], Platform.environment['ProgramFiles(x86)']]
            .whereType<String>()
            .map((d) => '$d\\VideoLAN\\VLC\\vlc.exe')
            .firstWhere((p) => File(p).existsSync(), orElse: () => '');
        if (exe.isEmpty) throw Exception('VLC is not installed');
        await Process.start(exe, vlcArgs, mode: ProcessStartMode.detached);
      } else {
        // Running VLC's own program passes the link (and start time) reliably.
        // ("open --args" starts VLC, but the Mac version ignores the link.)
        const bin = '/Applications/VLC.app/Contents/MacOS/VLC';
        try {
          await Process.start(bin, vlcArgs, mode: ProcessStartMode.detached);
        } catch (e) {
          debugPrint('[vlc] direct launch failed ($e), trying open -a');
          final r = await Process.run('/usr/bin/open', ['-a', 'VLC', url]);
          if (r.exitCode != 0) throw Exception('${r.stderr}');
        }
      }
      messenger.showSnackBar(const SnackBar(content: Text('Opened in VLC.')));
    } catch (e) {
      debugPrint('[vlc] launch failed: $e');
      messenger.showSnackBar(const SnackBar(
          content: Text("Couldn't open VLC, so the link is copied. In VLC: File > Open Network, then paste.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      consumeOutsideTap: true,
      menuChildren: [
        if (VodFailover.lastSwitch.value != null &&
            Services.playback.current.value?.id == VodFailover.lastSwitch.value!.now.id)
          MenuItemButton(
            leadingIcon: const Icon(Icons.undo, size: 18),
            onPressed: () => Services.playback.undoVodSwitch(),
            child: Text('Back to ${VodFailover.lastSwitch.value!.originalAccount}'),
          ),
        if (Services.playback.current.value?.kind == 'movie')
          MenuItemButton(
            leadingIcon: const Icon(Icons.info_outline, size: 18),
            onPressed: () async {
              final cur = Services.playback.current.value;
              if (cur == null) return;
              if (PopOut.active.value) await PopOut.backToFull();
              AppNav.index.value = AppNav.movies;
              AppNav.select.value = cur;
            },
            child: const Text('Movie details'),
          ),
        if (Services.playback.current.value?.kind == 'episode')
          MenuItemButton(
            leadingIcon: const Icon(Icons.video_library_outlined, size: 18),
            onPressed: () async {
              final cur = Services.playback.current.value;
              if (cur == null) return;
              final page = await VodFailover.showPageFor(cur);
              if (page == null) return;
              if (PopOut.active.value) await PopOut.backToFull();
              AppNav.index.value = AppNav.shows;
              AppNav.select.value = page;
            },
            child: const Text('Show page & episodes'),
          ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.picture_in_picture_alt, size: 18),
          onPressed: () => PopOut.enter(),
          child: const Text('Mini player (always on top)'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.open_in_new, size: 18),
          onPressed: () => _vlc(context),
          child: const Text('Open in VLC'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.link, size: 18),
          onPressed: () => _copy(context),
          child: const Text('Copy stream link'),
        ),
      ],
      builder: (context, ctrl, _) => IconButton.filledTonal(
        tooltip: 'More',
        onPressed: () => ctrl.isOpen ? ctrl.close() : ctrl.open(),
        icon: const Icon(Icons.more_horiz),
      ),
    );
  }
}

/// Audio and subtitle track picker. Hidden when there's nothing to choose.
/// Subtitles on/off only shows or hides the loaded track (instant, no stall).
class TrackMenu extends StatelessWidget {
  const TrackMenu({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: Services.playback.trackTick,
        builder: (context, _, _) => _build(context),
      );

  Widget _build(BuildContext context) {
    final p = Services.playback.player;
    return StreamBuilder<Tracks>(
      stream: p.stream.tracks,
      initialData: p.state.tracks,
      builder: (context, snap) {
        final tracks = snap.data ?? p.state.tracks;
        final audio = tracks.audio.where((t) => t.id != 'auto' && t.id != 'no').toList();
        final subs = tracks.subtitle.where((t) => t.id != 'auto' && t.id != 'no').toList();
        return StreamBuilder<Track>(
          stream: p.stream.track,
          initialData: p.state.track,
          builder: (context, curSnap) {
            final cur = curSnap.data ?? p.state.track;
            return ValueListenableBuilder<bool>(
              valueListenable: Services.playback.subsVisible,
              builder: (context, visible, _) {
                final subsOn = visible && cur.subtitle.id != 'no';
                Widget mark(bool on) =>
                    on ? Icon(Icons.check, size: 18, color: BMColors.mango) : const SizedBox(width: 18);
                Widget header(String t) => Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                      child: Text(t,
                          style: TextStyle(
                              fontFamily: BMFonts.mono, fontSize: 11, letterSpacing: 1.5, color: BMColors.dim)),
                    );
                return MenuAnchor(
      consumeOutsideTap: true,
                  menuChildren: [
                    ...[
                      header('AUDIO'),
                      if (audio.isEmpty)
                        const MenuItemButton(onPressed: null, child: Text('No audio track found')),
                      for (var i = 0; i < audio.length; i++)
                        MenuItemButton(
                          leadingIcon: mark(cur.audio.id == audio[i].id ||
                              (cur.audio.id == 'auto' && Services.playback.activeAudioId == audio[i].id)),
                          onPressed: () => Services.playback.chooseAudio(audio[i]),
                          child: Text(_label(audio[i].title, audio[i].language, i)),
                        ),
                    ],
                    header('SUBTITLES'),
                    if (subs.isEmpty)
                      const MenuItemButton(onPressed: null, child: Text('None in this video')),
                    if (subs.isNotEmpty) ...[
                      MenuItemButton(
                        leadingIcon: mark(!subsOn),
                        onPressed: () => Services.playback.subsOff(),
                        child: const Text('Off'),
                      ),
                      for (var i = 0; i < subs.length; i++)
                        MenuItemButton(
                          leadingIcon: mark(subsOn &&
                              (cur.subtitle.id == subs[i].id ||
                                  (cur.subtitle.id == 'auto' && Services.playback.activeSubId == subs[i].id))),
                          onPressed: () => Services.playback.chooseSubtitle(subs[i]),
                          child: Text(_label(subs[i].title, subs[i].language, i)),
                        ),
                    ],
                  ],
                  builder: (context, ctrl, _) => IconButton.filledTonal(
                    tooltip: 'Audio & subtitles',
                    onPressed: () => ctrl.isOpen ? ctrl.close() : ctrl.open(),
                    icon: Icon(subsOn ? Icons.subtitles : Icons.subtitles_outlined),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
