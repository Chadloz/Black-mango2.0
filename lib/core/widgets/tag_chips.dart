import 'package:flutter/material.dart';
import '../../app/theme.dart';

/// Small outlined tags (4K, HDR, DE, US...) from a provider's name. Shows at most [max].
class TagChips extends StatelessWidget {
  final List<String> tags;
  final double size;
  final int max;
  const TagChips(this.tags, {super.key, this.size = 9.5, this.max = 4});

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 4,
      runSpacing: 3,
      children: [
        for (final t in tags.take(max))
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              border: Border.all(color: BMColors.border),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              t,
              style: TextStyle(fontSize: size, height: 1.3, fontWeight: FontWeight.w700, color: BMColors.dim, fontFamily: BMFonts.mono),
            ),
          ),
      ],
    );
  }
}
