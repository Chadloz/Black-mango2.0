import 'dart:math';
import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../app/skins.dart';
import '../../app/skin_drops.dart';

/// A holiday drop arrived: a gift box wiggles, pops its lid, and the pack's skins come out.
/// Use it now switches to the first one (or click any of them); Later keeps them in My skins.
class DropReveal extends StatefulWidget {
  final Drop drop;
  const DropReveal({super.key, required this.drop});

  static Future<void> show(BuildContext context, Drop drop) => showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.all(24),
          child: DropReveal(drop: drop),
        ),
      );

  @override
  State<DropReveal> createState() => _DropRevealState();
}

class _DropRevealState extends State<DropReveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final List<Skin> _skins = widget.drop.pack?.skins ?? const [];

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  String _day(DateTime d) => '${_months[d.month - 1]} ${d.day}';

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
    final still = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    if (still) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _use(Skin s) async {
    await Skins.pick(s);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final look = _skins.isEmpty ? Skins.skin : _skins.first;
    return Container(
      constraints: const BoxConstraints(maxWidth: 680),
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
      decoration: BoxDecoration(
        color: look.background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: look.accent, width: 2),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 24)],
      ),
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          final cardsIn = Curves.easeOutBack.transform(((t - 0.55) / 0.45).clamp(0.0, 1.0));
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.drop.giveaway ? 'A gift for you' : 'A drop for you',
                  style: TextStyle(fontFamily: BMFonts.mono, fontSize: 11, letterSpacing: 1.5, color: look.dim)),
              const SizedBox(height: 6),
              Text(
                widget.drop.name,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: look.titleFont ?? BMFonts.ui,
                  fontSize: look.titleFont != null ? 30 : 28,
                  fontWeight: look.titleFont != null ? FontWeight.w400 : FontWeight.w700,
                  color: look.text,
                ),
              ),
              SizedBox(
                height: 170,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (t < 0.85)
                      Opacity(
                        opacity: (1 - ((t - 0.6) / 0.25)).clamp(0.0, 1.0),
                        child: CustomPaint(size: const Size(150, 150), painter: _Gift(t, look.accent, const Color(0xFFF2C14E))),
                      ),
                    Opacity(
                      opacity: cardsIn.clamp(0.0, 1.0),
                      child: Transform.scale(
                        scale: 0.6 + 0.4 * cardsIn,
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          alignment: WrapAlignment.center,
                          children: [for (final s in _skins) _MiniCard(skin: s, onTap: () => _use(s))],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Opacity(
                opacity: cardsIn.clamp(0.0, 1.0),
                child: Text(
                  widget.drop.giveaway
                      ? 'Yours to keep, in Settings > Skins > My skins. Only people with the code get these.'
                      : 'Yours to keep, in Settings > Skins > My skins. Only people who opened Black Mango '
                          'between ${_day(widget.drop.start)} and ${_day(widget.drop.end)} get these.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: look.dim, fontSize: 13),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(foregroundColor: look.text),
                    child: const Text('Later'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _skins.isEmpty ? null : () => _use(_skins.first),
                    style: FilledButton.styleFrom(
                      backgroundColor: look.accent,
                      foregroundColor: look.accent.computeLuminance() > 0.18 ? Colors.black : Colors.white,
                    ),
                    child: const Text('Use it now'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One skin from the pack, in its own colors. Click to use it.
class _MiniCard extends StatelessWidget {
  final Skin skin;
  final VoidCallback onTap;
  const _MiniCard({required this.skin, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 180,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: skin.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: skin.accent, width: 1.5),
        ),
        child: Row(
          children: [
            Image.asset(skin.logo, height: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(skin.name,
                      maxLines: 2,
                      style: TextStyle(
                        fontFamily: skin.titleFont ?? BMFonts.ui,
                        fontSize: 14,
                        color: skin.text,
                      )),
                  const SizedBox(height: 6),
                  Row(children: [
                    for (final c in [skin.background, skin.accent, skin.text])
                      Container(
                        width: 12,
                        height: 12,
                        margin: const EdgeInsets.only(right: 4),
                        decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: skin.border)),
                      ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The gift box: drops in and wiggles (0 to 0.35), the lid pops off (0.35 to 0.6),
/// a burst of light (0.4 to 0.8).
class _Gift extends CustomPainter {
  final double t;
  final Color box;
  final Color ribbon;
  _Gift(this.t, this.box, this.ribbon);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final drop = Curves.bounceOut.transform((t / 0.25).clamp(0.0, 1.0));
    final wiggle = t > 0.2 && t < 0.38 ? sin((t - 0.2) * 70) * 0.08 : 0.0;
    final open = Curves.easeOut.transform(((t - 0.35) / 0.25).clamp(0.0, 1.0));
    final burst = ((t - 0.4) / 0.4).clamp(0.0, 1.0);

    canvas.save();
    canvas.translate(w / 2, h * 0.62 - (1 - drop) * 60);
    canvas.rotate(wiggle);

    // Light bursting out of the open box.
    if (burst > 0) {
      final glow = Paint()
        ..color = ribbon.withValues(alpha: (1 - burst) * 0.7)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 12; i++) {
        final a = -pi / 2 + (i - 5.5) * 0.22;
        final len = 30 + 70 * burst;
        canvas.drawLine(Offset(cos(a) * 20, -h * 0.12 + sin(a) * 20), Offset(cos(a) * len, -h * 0.12 + sin(a) * len), glow);
      }
    }

    // Box.
    final body = RRect.fromRectAndRadius(Rect.fromLTWH(-w * 0.3, -h * 0.12, w * 0.6, h * 0.42), const Radius.circular(6));
    canvas.drawRRect(body, Paint()..color = box);
    canvas.drawRect(Rect.fromLTWH(-w * 0.05, -h * 0.12, w * 0.1, h * 0.42), Paint()..color = ribbon);
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.black26,
    );

    // Lid with bow, flying up and off.
    canvas.save();
    canvas.translate(open * 34, -open * 90);
    canvas.rotate(open * 0.7);
    final lid = RRect.fromRectAndRadius(Rect.fromLTWH(-w * 0.34, -h * 0.24, w * 0.68, h * 0.13), const Radius.circular(5));
    final lidPaint = Paint()..color = box.withValues(alpha: 1 - open * 0.6);
    canvas.drawRRect(lid, lidPaint);
    canvas.drawRect(Rect.fromLTWH(-w * 0.05, -h * 0.24, w * 0.1, h * 0.13), Paint()..color = ribbon.withValues(alpha: 1 - open * 0.6));
    final bow = Paint()..color = ribbon.withValues(alpha: 1 - open * 0.6);
    canvas.drawOval(Rect.fromCenter(center: Offset(-w * 0.09, -h * 0.29), width: w * 0.17, height: h * 0.11), bow);
    canvas.drawOval(Rect.fromCenter(center: Offset(w * 0.09, -h * 0.29), width: w * 0.17, height: h * 0.11), bow);
    canvas.drawCircle(Offset(0, -h * 0.27), w * 0.04, bow);
    canvas.restore();

    canvas.restore();
  }

  @override
  bool shouldRepaint(_Gift o) => o.t != t || o.box != box;
}
