import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../app/skins.dart';
import '../../app/skin_textures.dart';

/// A category pill (Live TV, Movies, Shows, Favorites). Drawn by hand rather than with a
/// ChoiceChip, so the selected one can carry the skin's accent texture.
class SkinPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const SkinPill({super.key, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8, top: 3, bottom: 3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.center,
            decoration: SkinTextures.decorate(
              TextureArea.accent,
              selected ? BMColors.mango.withAlpha(0x33) : Colors.transparent,
              on: selected,
              radius: BorderRadius.circular(999),
              border: Border.all(color: selected ? BMColors.mango : BMColors.border),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? BMColors.mango : BMColors.text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
