import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../app/skins.dart';
import 'halloween.dart';

/// The Black Mango logo (assets/brand/logo.png) at a given height.
class BrandLogo extends StatelessWidget {
  final double height;
  const BrandLogo({super.key, this.height = 40});

  @override
  Widget build(BuildContext context) => Image.asset(
        Skins.skin.logo, // Halloween skins: the jack-o'-lantern mango
        height: height,
        filterQuality: FilterQuality.medium,
        semanticLabel: 'Black Mango',
      );
}

/// Logo centered above the wordmark: the top bar's brand block.
class BrandStack extends StatelessWidget {
  final double logoHeight;
  final double wordSize;
  const BrandStack({super.key, this.logoHeight = 40, this.wordSize = 16});

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Halloween skins: a lit jack-o'-lantern on each side of the mango.
          if (Skins.skin.halloween)
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Pumpkin(size: 20),
                const SizedBox(width: 6),
                BrandLogo(height: logoHeight),
                const SizedBox(width: 6),
                const Pumpkin(size: 20),
              ],
            )
          else
            BrandLogo(height: logoHeight),
          const SizedBox(height: 1),
          Wordmark(size: wordSize),
        ],
      );
}

/// "Black" in white, "Mango" in mango orange.
class Wordmark extends StatelessWidget {
  final double size;
  const Wordmark({super.key, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: 'Black ', style: TextStyle(color: BMColors.text)),
        TextSpan(text: 'Mango', style: TextStyle(color: BMColors.mango)),
      ]),
      // The skin's title font (Halloween: dripping Nosifer, which runs wide and has one weight).
      style: Skins.skin.titleFont == null
          ? TextStyle(fontFamily: BMFonts.ui, fontWeight: FontWeight.w800, fontSize: size, letterSpacing: -0.5)
          : TextStyle(fontFamily: BMFonts.title, fontWeight: FontWeight.w400, fontSize: size * 0.8),
    );
  }
}
