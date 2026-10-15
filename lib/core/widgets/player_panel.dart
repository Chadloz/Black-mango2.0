import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../app/theme.dart';
import '../services.dart';
import '../storage/database.dart';

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
                Video(controller: Services.playback.controller),
                Positioned(
                  top: 12,
                  left: 12,
                  child: ValueListenableBuilder<String?>(
                    valueListenable: Services.playback.reconnecting,
                    builder: (context, msg, _) => msg == null
                        ? const SizedBox.shrink()
                        : Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
                            child: Text(msg, style: const TextStyle(color: BMColors.mango, fontWeight: FontWeight.w600)),
                          ),
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
