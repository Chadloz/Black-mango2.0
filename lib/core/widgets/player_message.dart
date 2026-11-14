import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../services.dart';

/// The message at the top left of a player: reconnect status first, otherwise a short note
/// (like a channel getting extra buffer, or "Added to favorites").
///
/// Long messages wrap onto more lines. They used to be one line that ran off the right edge,
/// which cut the 458 message off mid-sentence (test build 8). On a wide player the message
/// stops short of the buttons at the top right; on a small one it uses the full width. Clicks
/// pass straight through it. Goes directly inside the player's Stack.
class PlayerMessage extends StatelessWidget {
  /// Room to leave on the right for the player's top-right buttons, when the player is wide.
  final double buttonsWidth;
  const PlayerMessage({super.key, this.buttonsWidth = 170});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (context, box) => Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: EdgeInsets.fromLTRB(12, 12, box.maxWidth > 520 ? buttonsWidth : 12, 0),
              child: ListenableBuilder(
                listenable: Listenable.merge([Services.playback.reconnecting, Services.playback.playerNote]),
                builder: (context, _) {
                  final msg = Services.playback.reconnecting.value ?? Services.playback.playerNote.value;
                  if (msg == null) return const SizedBox.shrink();
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      msg,
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: BMColors.mango, fontWeight: FontWeight.w600),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
