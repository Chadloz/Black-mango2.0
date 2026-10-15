import 'package:flutter/material.dart';
import '../../app/theme.dart';

/// "Black" in white, "Mango" in mango orange.
class Wordmark extends StatelessWidget {
  final double size;
  const Wordmark({super.key, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      const TextSpan(children: [
        TextSpan(text: 'Black ', style: TextStyle(color: BMColors.text)),
        TextSpan(text: 'Mango', style: TextStyle(color: BMColors.mango)),
      ]),
      style: TextStyle(fontFamily: BMFonts.ui, fontWeight: FontWeight.w800, fontSize: size, letterSpacing: -0.5),
    );
  }
}
