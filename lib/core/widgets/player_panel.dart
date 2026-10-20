import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../app/theme.dart';
import '../services.dart';
import '../storage/database.dart';
import 'track_menu.dart';
import 'player_controls.dart';

class PlayerPanel extends StatelessWidget {
  final Item item;
  final String accountName;
  const PlayerPanel({super.key, required this.item, required this.accountName});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Video(
                  controller: Services.playback.controller,
                  // mpv draws subtitles itself (libass), including image-based ones.
                  subtitleViewConfiguration: const SubtitleViewConfiguration(visible: false),
                  controls: (state) => BMControls(state: state, rightInset: 48),
                ),
                const Positioned.fill(child: HandOffOverlay()),
                Positioned(
                  top: 12,
                  left: 12,
                  // Reconnect status first; otherwise a short note (like a channel getting extra buffer).
                  child: ListenableBuilder(
                    listenable: Listenable.merge([Services.playback.reconnecting, Services.playback.playerNote]),
                    builder: (context, _) {
                      final msg = Services.playback.reconnecting.value ?? Services.playback.playerNote.value;
                      return msg == null
                          ? const SizedBox.shrink()
                          : Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
                              child: Text(msg, style: const TextStyle(color: BMColors.mango, fontWeight: FontWeight.w600)),
                            );
                    },
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton.filledTonal(
                    tooltip: 'Close',
                    onPressed: () => Services.playback.stop(),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            height: 40,
            color: BMColors.surface,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: item.name, style: const TextStyle(fontWeight: FontWeight.w700, color: BMColors.text)),
                if (accountName.isNotEmpty)
                  TextSpan(text: '   $accountName', style: const TextStyle(color: BMColors.mango)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
