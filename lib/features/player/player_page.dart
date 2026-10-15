import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../core/services.dart';

/// Full-window player for movies and episodes. Back stops playback.
class PlayerPage extends StatelessWidget {
  final String title;
  const PlayerPage({super.key, required this.title});

  Future<void> _back(BuildContext context) async {
    await Services.playback.stop();
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: Video(controller: Services.playback.controller)),
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Row(
              children: [
                IconButton.filledTonal(
                  tooltip: 'Back',
                  onPressed: () => _back(context),
                  icon: const Icon(Icons.arrow_back),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      shadows: [Shadow(blurRadius: 8, color: Colors.black)],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
