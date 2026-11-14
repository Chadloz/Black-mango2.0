import 'package:flutter/material.dart';
import 'player_message.dart';
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
                const PlayerMessage(buttonsWidth: 210), // this player also has a close button up there
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
                TextSpan(text: item.name, style: TextStyle(fontWeight: FontWeight.w700, color: BMColors.text)),
                if (accountName.isNotEmpty)
                  TextSpan(text: '   $accountName', style: TextStyle(color: BMColors.mango)),
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
