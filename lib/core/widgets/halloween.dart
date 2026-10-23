import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../app/theme.dart';

/// Cobweb corners and a faint fog along the bottom, laid over the app in Halloween skins.
/// Never takes clicks.
class HalloweenDecor extends StatelessWidget {
  const HalloweenDecor({super.key});

  @override
  Widget build(BuildContext context) {
    final web = BMColors.dim.withAlpha(90);
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(left: 0, bottom: 0, child: CustomPaint(size: const Size(130, 130), painter: _Cobweb(web))),
          Positioned(
            right: 0,
            top: 73, // just under the top bar
            child: Transform.flip(flipX: true, flipY: true, child: CustomPaint(size: const Size(100, 100), painter: _Cobweb(web))),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 110,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.white.withAlpha(18), Colors.white.withAlpha(0)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A corner web: spokes out from the bottom-left corner, with sagging threads between them.
class _Cobweb extends CustomPainter {
  final Color color;
  _Cobweb(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final o = Offset(0, size.height);
    final angles = [0.0, 0.32, 0.68, 1.05, 1.5708];
    final ends = [for (final a in angles) o + Offset(cos(a) * size.width, -sin(a) * size.height)];
    for (final e in ends) {
      canvas.drawLine(o, e, p);
    }
    for (final r in [0.28, 0.52, 0.76, 0.98]) {
      final path = Path();
      for (var i = 0; i < ends.length; i++) {
        final pt = Offset.lerp(o, ends[i], r)!;
        if (i == 0) {
          path.moveTo(pt.dx, pt.dy);
        } else {
          final prev = Offset.lerp(o, ends[i - 1], r)!;
          final mid = Offset.lerp(prev, pt, 0.5)!;
          final sag = Offset.lerp(mid, o, 0.12)!; // threads sag toward the corner
          path.quadraticBezierTo(sag.dx, sag.dy, pt.dx, pt.dy);
        }
      }
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(_Cobweb old) => old.color != color;
}

/// Three little bats for the top bar, in the skin's accent color.
class Bats extends StatelessWidget {
  const Bats({super.key});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size(84, 34), painter: _Bats(BMColors.mango.withAlpha(220)));
}

class _Bats extends CustomPainter {
  final Color color;
  _Bats(this.color);

  void _bat(Canvas c, Offset at, double s, Paint p) {
    final path = Path()
      ..moveTo(at.dx, at.dy)
      ..quadraticBezierTo(at.dx + 4 * s, at.dy - 6 * s, at.dx + 9 * s, at.dy - 2 * s)
      ..quadraticBezierTo(at.dx + 10 * s, at.dy - 5 * s, at.dx + 12 * s, at.dy - 4 * s)
      ..lineTo(at.dx + 13 * s, at.dy - 6 * s)
      ..lineTo(at.dx + 14 * s, at.dy - 4 * s)
      ..quadraticBezierTo(at.dx + 16 * s, at.dy - 5 * s, at.dx + 17 * s, at.dy - 2 * s)
      ..quadraticBezierTo(at.dx + 22 * s, at.dy - 6 * s, at.dx + 26 * s, at.dy)
      ..quadraticBezierTo(at.dx + 21 * s, at.dy - 1 * s, at.dx + 19 * s, at.dy + 3 * s)
      ..quadraticBezierTo(at.dx + 16 * s, at.dy + 0 * s, at.dx + 13 * s, at.dy + 4 * s)
      ..quadraticBezierTo(at.dx + 10 * s, at.dy + 0 * s, at.dx + 7 * s, at.dy + 3 * s)
      ..quadraticBezierTo(at.dx + 5 * s, at.dy - 1 * s, at.dx, at.dy)
      ..close();
    c.drawPath(path, p);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    _bat(canvas, const Offset(2, 22), 1.0, p);
    _bat(canvas, const Offset(34, 14), 0.8, p);
    _bat(canvas, const Offset(60, 8), 0.6, p);
  }

  @override
  bool shouldRepaint(_Bats old) => old.color != color;
}

/// A lit jack-o'-lantern with a candle flicker, for beside the mango in the top bar.
class Pumpkin extends StatefulWidget {
  final double size;
  const Pumpkin({super.key, this.size = 22});

  @override
  State<Pumpkin> createState() => _PumpkinState();
}

class _PumpkinState extends State<Pumpkin> {
  final _rand = Random();
  double _glow = 1;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(Duration(milliseconds: 110 + _rand.nextInt(60)), (_) {
      if (mounted) setState(() => _glow = 0.6 + _rand.nextDouble() * 0.4);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(widget.size, widget.size * 0.9), painter: _Pumpkin(_glow));
}

class _Pumpkin extends CustomPainter {
  final double glow;
  _Pumpkin(this.glow);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final body = Rect.fromLTWH(0, h * 0.18, w, h * 0.82);
    final orange = Paint()..color = const Color(0xFFFF7518);
    final rib = Paint()..color = const Color(0xFFD95A0B);
    // Lobes: outer ones darker, the middle one in front.
    canvas.drawOval(Rect.fromLTWH(body.left, body.top + 1, w * 0.5, body.height - 1), rib);
    canvas.drawOval(Rect.fromLTWH(body.left + w * 0.5, body.top + 1, w * 0.5, body.height - 1), rib);
    canvas.drawOval(Rect.fromLTWH(body.left + w * 0.18, body.top, w * 0.64, body.height), orange);
    // Stem.
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.45, 0, w * 0.12, h * 0.26), const Radius.circular(2)),
      Paint()..color = const Color(0xFF5B7F2A),
    );
    // Carved face, lit from inside: glow halo, then the bright cut-outs.
    final face = Path()
      ..moveTo(w * 0.22, h * 0.52)
      ..lineTo(w * 0.32, h * 0.38)
      ..lineTo(w * 0.42, h * 0.52)
      ..close()
      ..moveTo(w * 0.58, h * 0.52)
      ..lineTo(w * 0.68, h * 0.38)
      ..lineTo(w * 0.78, h * 0.52)
      ..close()
      ..moveTo(w * 0.2, h * 0.64)
      ..lineTo(w * 0.32, h * 0.72)
      ..lineTo(w * 0.4, h * 0.65)
      ..lineTo(w * 0.5, h * 0.74)
      ..lineTo(w * 0.6, h * 0.65)
      ..lineTo(w * 0.68, h * 0.72)
      ..lineTo(w * 0.8, h * 0.64)
      ..lineTo(w * 0.7, h * 0.86)
      ..lineTo(w * 0.3, h * 0.86)
      ..close();
    canvas.drawPath(
      face,
      Paint()
        ..color = const Color(0xFFFFB347).withAlpha((140 * glow).round())
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );
    canvas.drawPath(face, Paint()..color = Color.lerp(const Color(0xFF8A3A00), const Color(0xFFFFE08A), glow)!);
  }

  @override
  bool shouldRepaint(_Pumpkin old) => old.glow != glow;
}

/// The Boo! ghost: a cute sheet ghost that floats up from a random corner when you add an
/// account (Halloween skins), says Boo! with the account's name, and fades away.
class Ghost {
  static void boo(OverlayState overlay, String name) {
    late final OverlayEntry entry;
    entry = OverlayEntry(builder: (_) => _GhostPop(name: name, onDone: () => entry.remove()));
    overlay.insert(entry);
  }
}

class _GhostPop extends StatefulWidget {
  final String name;
  final VoidCallback onDone;
  const _GhostPop({required this.name, required this.onDone});

  @override
  State<_GhostPop> createState() => _GhostPopState();
}

class _GhostPopState extends State<_GhostPop> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  final int _corner = Random().nextInt(4); // 0 bottom-left, 1 bottom-right, 2 top-left, 3 top-right

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) widget.onDone();
      })
      ..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = _corner == 0 || _corner == 2;
    final bottom = _corner < 2;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          final fade = t < 0.15 ? t / 0.15 : (t > 0.8 ? (1 - t) / 0.2 : 1.0);
          final rise = 70 * Curves.easeOut.transform(t);
          final sway = sin(t * pi * 3) * 6;
          final ghost = Opacity(
            opacity: fade.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(sway, -rise),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: left ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                children: [
                  Container(
                    constraints: const BoxConstraints(maxWidth: 260),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: BMColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: BMColors.mango, width: 1.5),
                    ),
                    child: Text(
                      'Boo! ${widget.name} added',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: BMColors.text, fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 6),
                  CustomPaint(size: const Size(58, 68), painter: _Sheet()),
                ],
              ),
            ),
          );
          return Stack(
            children: [
              Positioned(
                left: left ? 28 : null,
                right: left ? null : 28,
                bottom: bottom ? 24 : null,
                top: bottom ? null : 110,
                child: ghost,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A cute sheet ghost: rounded top, wavy hem, two eyes and a little "o" mouth.
class _Sheet extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final sheet = Path()
      ..moveTo(0, h * 0.5)
      ..arcToPoint(Offset(w, h * 0.5), radius: Radius.circular(w / 2))
      ..lineTo(w, h * 0.92);
    // Wavy hem, right to left.
    const waves = 4;
    for (var i = 0; i < waves; i++) {
      final x0 = w - i * w / waves;
      final x1 = x0 - w / waves;
      sheet.quadraticBezierTo((x0 + x1) / 2, i.isEven ? h * 0.78 : h * 1.04, x1, h * 0.92);
    }
    sheet.close();
    canvas.drawShadow(sheet, Colors.black, 4, true);
    canvas.drawPath(sheet, Paint()..color = const Color(0xFFF7F4FF));
    final ink = Paint()..color = const Color(0xFF1A1420);
    canvas.drawOval(Rect.fromCenter(center: Offset(w * 0.36, h * 0.4), width: w * 0.11, height: h * 0.13), ink);
    canvas.drawOval(Rect.fromCenter(center: Offset(w * 0.64, h * 0.4), width: w * 0.11, height: h * 0.13), ink);
    canvas.drawOval(Rect.fromCenter(center: Offset(w * 0.5, h * 0.56), width: w * 0.12, height: h * 0.1), ink);
    final blush = Paint()..color = const Color(0x55FF8FB1);
    canvas.drawOval(Rect.fromCenter(center: Offset(w * 0.24, h * 0.5), width: w * 0.12, height: h * 0.06), blush);
    canvas.drawOval(Rect.fromCenter(center: Offset(w * 0.76, h * 0.5), width: w * 0.12, height: h * 0.06), blush);
  }

  @override
  bool shouldRepaint(_Sheet old) => false;
}
