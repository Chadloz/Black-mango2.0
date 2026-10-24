import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../app/theme.dart';

const _leafColors = [Color(0xFFD9481E), Color(0xFFE8731C), Color(0xFFF0A029), Color(0xFFA63A1E), Color(0xFFC9822B)];

/// A few leaves drifting down behind everything (they show between lists and cards, never over
/// text panels or the video). Still when the system asks for reduced motion.
class FallingLeaves extends StatefulWidget {
  const FallingLeaves({super.key});

  @override
  State<FallingLeaves> createState() => _FallingLeavesState();
}

class _Leaf {
  double x; // 0..1 across
  double y; // pixels from the top
  final double speed; // pixels per second
  final double sway; // pixels
  final double phase;
  final double spin; // radians per second
  final double size;
  final Color color;
  _Leaf(this.x, this.y, this.speed, this.sway, this.phase, this.spin, this.size, this.color);
}

class _FallingLeavesState extends State<FallingLeaves> with SingleTickerProviderStateMixin {
  final _rnd = Random();
  final _time = ValueNotifier<double>(0);
  late final List<_Leaf> _leaves = List.generate(9, (_) => _newLeaf(top: false));
  Ticker? _ticker;
  Duration _last = Duration.zero;
  double _height = 800;

  _Leaf _newLeaf({required bool top}) => _Leaf(
        _rnd.nextDouble(),
        top ? -30 : _rnd.nextDouble() * 800,
        18 + _rnd.nextDouble() * 22,
        16 + _rnd.nextDouble() * 26,
        _rnd.nextDouble() * pi * 2,
        (_rnd.nextDouble() - 0.5) * 1.6,
        13 + _rnd.nextDouble() * 11,
        _leafColors[_rnd.nextInt(_leafColors.length)],
      );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.of(context).disableAnimations;
    if (still) {
      _ticker?.stop();
    } else {
      _ticker ??= createTicker(_tick);
      if (!_ticker!.isActive) _ticker!.start();
    }
  }

  void _tick(Duration now) {
    final dt = ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = now;
    for (var i = 0; i < _leaves.length; i++) {
      final l = _leaves[i];
      l.y += l.speed * dt;
      if (l.y > _height + 30) _leaves[i] = _newLeaf(top: true);
    }
    _time.value = now.inMicroseconds / 1e6;
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: LayoutBuilder(builder: (context, box) {
        _height = box.maxHeight.isFinite ? box.maxHeight : 800;
        return CustomPaint(size: box.biggest, painter: _LeavesPainter(_leaves, _time));
      }),
    );
  }
}

class _LeavesPainter extends CustomPainter {
  final List<_Leaf> leaves;
  final ValueNotifier<double> time;
  _LeavesPainter(this.leaves, this.time) : super(repaint: time);

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    for (final l in leaves) {
      final x = l.x * size.width + sin(t * 0.9 + l.phase) * l.sway;
      canvas.save();
      canvas.translate(x, l.y);
      canvas.rotate(t * l.spin + l.phase);
      paintLeaf(canvas, l.size, l.color.withValues(alpha: 0.55));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_LeavesPainter old) => false;
}

/// A simple autumn leaf, centered on the origin, pointing up.
void paintLeaf(Canvas canvas, double s, Color c) {
  final leaf = Path()
    ..moveTo(0, -s * 0.6)
    ..cubicTo(s * 0.45, -s * 0.35, s * 0.42, s * 0.2, 0, s * 0.42)
    ..cubicTo(-s * 0.42, s * 0.2, -s * 0.45, -s * 0.35, 0, -s * 0.6)
    ..close();
  canvas.drawPath(leaf, Paint()..color = c);
  final vein = Paint()
    ..color = Color.lerp(c, Colors.black, 0.35)!
    ..strokeWidth = max(1.0, s * 0.06)
    ..style = PaintingStyle.stroke;
  canvas.drawLine(Offset(0, -s * 0.5), Offset(0, s * 0.6), vein); // midrib and stem
  canvas.drawLine(Offset(0, -s * 0.1), Offset(s * 0.2, -s * 0.28), vein);
  canvas.drawLine(Offset(0, -s * 0.1), Offset(-s * 0.2, -s * 0.28), vein);
  canvas.drawLine(Offset(0, s * 0.12), Offset(s * 0.22, -s * 0.02), vein);
  canvas.drawLine(Offset(0, s * 0.12), Offset(-s * 0.22, -s * 0.02), vein);
}

/// The top bar's harvest: a bundle of wheat, two acorns, three pumpkins (orange, white, green)
/// and a pumpkin pie.
class HarvestBar extends StatelessWidget {
  const HarvestBar({super.key});

  @override
  Widget build(BuildContext context) =>
      IgnorePointer(child: CustomPaint(size: const Size(212, 56), painter: _Harvest(BMColors.border)));
}

class _Harvest extends CustomPainter {
  final Color shadow;
  _Harvest(this.shadow);

  @override
  void paint(Canvas canvas, Size size) {
    final ground = size.height - 4;
    _wheat(canvas, Offset(14, ground));
    _acorn(canvas, Offset(40, ground - 5), 9);
    _acorn(canvas, Offset(52, ground - 3), 7, tilt: 0.5);
    _pumpkin(canvas, Offset(84, ground), 20, 15, const Color(0xFFE8731C), const Color(0xFF4E7A3A));
    _pumpkin(canvas, Offset(118, ground), 16, 10, const Color(0xFFEDE3CC), const Color(0xFF7A8F4A));
    _pumpkin(canvas, Offset(145, ground), 11, 10, const Color(0xFF4E7A3A), const Color(0xFF6B4A2A), stripes: true);
    _pie(canvas, Offset(186, ground), 22);
  }

  void _wheat(Canvas canvas, Offset base) {
    final stem = Paint()
      ..color = const Color(0xFFC9A24A)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    final grain = Paint()..color = const Color(0xFFE3B95A);
    for (final lean in [-0.28, 0.0, 0.26]) {
      final top = base + Offset(lean * 40, -44);
      final path = Path()
        ..moveTo(base.dx, base.dy)
        ..quadraticBezierTo(base.dx + lean * 10, base.dy - 26, top.dx, top.dy);
      canvas.drawPath(path, stem);
      for (var i = 0; i < 5; i++) {
        final p = top + Offset(-lean * 4 * i, 3.4 * i);
        for (final side in [-1.0, 1.0]) {
          canvas.save();
          canvas.translate(p.dx + side * 2.2, p.dy);
          canvas.rotate(side * 0.5 + lean);
          canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 3.4, height: 6.4), grain);
          canvas.restore();
        }
      }
    }
    // A little ribbon around the bundle.
    canvas.drawLine(base + const Offset(-4, -12), base + const Offset(4, -12),
        Paint()
          ..color = const Color(0xFFB0412B)
          ..strokeWidth = 3);
  }

  void _acorn(Canvas canvas, Offset c, double r, {double tilt = 0}) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(tilt);
    canvas.drawOval(Rect.fromCenter(center: Offset(0, r * 0.25), width: r * 1.3, height: r * 1.6), Paint()..color = const Color(0xFFB9772F));
    canvas.drawArc(Rect.fromCenter(center: Offset(0, -r * 0.2), width: r * 1.6, height: r * 1.1), pi, pi, true,
        Paint()..color = const Color(0xFF6B4423));
    canvas.drawLine(Offset(0, -r * 0.75), Offset(r * 0.2, -r * 1.05),
        Paint()
          ..color = const Color(0xFF6B4423)
          ..strokeWidth = 1.6);
    canvas.restore();
  }

  void _pumpkin(Canvas canvas, Offset base, double rx, double ry, Color body, Color stemColor, {bool stripes = false}) {
    final c = Offset(base.dx, base.dy - ry);
    final shade = Color.lerp(body, Colors.black, 0.22)!;
    // Ribs: three overlapping lobes, darker at the sides.
    canvas.drawOval(Rect.fromCenter(center: c + Offset(-rx * 0.38, 0), width: rx * 1.25, height: ry * 2), Paint()..color = shade);
    canvas.drawOval(Rect.fromCenter(center: c + Offset(rx * 0.38, 0), width: rx * 1.25, height: ry * 2), Paint()..color = shade);
    canvas.drawOval(Rect.fromCenter(center: c, width: rx * 1.1, height: ry * 2), Paint()..color = body);
    if (stripes) {
      final s = Paint()
        ..color = const Color(0xFFA9C47E)
        ..strokeWidth = 1.4
        ..style = PaintingStyle.stroke;
      for (final dx in [-0.55, 0.0, 0.55]) {
        canvas.drawLine(c + Offset(rx * dx, -ry * 0.8), c + Offset(rx * dx, ry * 0.8), s);
      }
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: c + Offset(1, -ry - 2), width: 3.4, height: 6), const Radius.circular(1.5)),
      Paint()..color = stemColor,
    );
  }

  void _pie(Canvas canvas, Offset base, double r) {
    final tin = Path()
      ..moveTo(base.dx - r, base.dy - 8)
      ..lineTo(base.dx + r, base.dy - 8)
      ..lineTo(base.dx + r * 0.82, base.dy)
      ..lineTo(base.dx - r * 0.82, base.dy)
      ..close();
    canvas.drawPath(tin, Paint()..color = const Color(0xFFB8875A)); // crust side
    canvas.drawOval(Rect.fromCenter(center: Offset(base.dx, base.dy - 8), width: r * 2, height: 9), Paint()..color = const Color(0xFFD9A066));
    canvas.drawOval(Rect.fromCenter(center: Offset(base.dx, base.dy - 8.5), width: r * 1.7, height: 6.5), Paint()..color = const Color(0xFFC8661E));
    // Crimped edge.
    final crimp = Paint()..color = const Color(0xFFE6B57E);
    for (var i = 0; i < 9; i++) {
      final a = pi + i * pi / 8;
      canvas.drawCircle(Offset(base.dx + cos(a) * r * 0.95, base.dy - 8 + sin(a) * 4.2), 1.6, crimp);
    }
    // A dollop of cream.
    canvas.drawCircle(Offset(base.dx, base.dy - 10), 2.6, Paint()..color = const Color(0xFFFFF6E5));
  }

  @override
  bool shouldRepaint(_Harvest o) => o.shadow != shadow;
}

/// The Gobble! turkey: struts in from a bottom corner when you add an account (Thanksgiving
/// skins), says Gobble! with the account's name, and heads off.
class Turkey {
  static void gobble(OverlayState overlay, String name) {
    late final OverlayEntry entry;
    entry = OverlayEntry(builder: (_) => _TurkeyPop(name: name, onDone: () => entry.remove()));
    overlay.insert(entry);
  }
}

class _TurkeyPop extends StatefulWidget {
  final String name;
  final VoidCallback onDone;
  const _TurkeyPop({required this.name, required this.onDone});

  @override
  State<_TurkeyPop> createState() => _TurkeyPopState();
}

class _TurkeyPopState extends State<_TurkeyPop> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  final bool _left = Random().nextBool();

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800))
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
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          final fade = t < 0.12 ? t / 0.12 : (t > 0.82 ? (1 - t) / 0.18 : 1.0);
          final walk = 60 * Curves.easeOut.transform((t / 0.35).clamp(0.0, 1.0));
          final bob = sin(t * pi * 10).abs() * 3;
          final turkey = Opacity(
            opacity: fade.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(_left ? walk - 60 : 60 - walk, -bob),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: _left ? CrossAxisAlignment.start : CrossAxisAlignment.end,
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
                      'Gobble! ${widget.name} added',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: BMColors.text, fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Transform.flip(
                    flipX: !_left,
                    child: CustomPaint(size: const Size(78, 74), painter: _TurkeyPainter()),
                  ),
                ],
              ),
            ),
          );
          return Stack(
            children: [
              Positioned(left: _left ? 28 : null, right: _left ? null : 28, bottom: 20, child: turkey),
            ],
          );
        },
      ),
    );
  }
}

/// A round cartoon turkey facing right: a fan of tail feathers, a brown body, a little head with
/// a beak and a red wattle, and two legs.
class _TurkeyPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final tail = Offset(w * 0.42, h * 0.58);
    const bands = [Color(0xFFF3D9A4), Color(0xFF8B2E16), Color(0xFFE8731C), Color(0xFF7A4520)];
    const lengths = [1.0, 0.86, 0.72, 0.55];
    for (var b = 0; b < bands.length; b++) {
      final paint = Paint()
        ..color = bands[b]
        ..strokeWidth = w * 0.13 * (0.7 + 0.3 * lengths[b])
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 7; i++) {
        final a = pi + 0.25 + i * (pi - 0.5) / 6;
        final len = h * 0.5 * lengths[b];
        canvas.drawLine(tail, tail + Offset(cos(a) * len, sin(a) * len), paint);
      }
    }
    final legs = Paint()
      ..color = const Color(0xFFE3A12F)
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(w * 0.4, h * 0.82), Offset(w * 0.38, h * 0.97), legs);
    canvas.drawLine(Offset(w * 0.52, h * 0.82), Offset(w * 0.54, h * 0.97), legs);
    canvas.drawOval(Rect.fromCenter(center: Offset(w * 0.47, h * 0.66), width: w * 0.42, height: h * 0.38),
        Paint()..color = const Color(0xFF6B3E1E));
    canvas.drawOval(Rect.fromCenter(center: Offset(w * 0.5, h * 0.7), width: w * 0.24, height: h * 0.2),
        Paint()..color = const Color(0xFF8A5530));
    // Neck and head.
    canvas.drawOval(Rect.fromCenter(center: Offset(w * 0.66, h * 0.44), width: w * 0.16, height: h * 0.22),
        Paint()..color = const Color(0xFF8A5530));
    canvas.drawCircle(Offset(w * 0.69, h * 0.33), w * 0.08, Paint()..color = const Color(0xFF8A5530));
    canvas.drawCircle(Offset(w * 0.71, h * 0.31), w * 0.018, Paint()..color = const Color(0xFF1A120C));
    final beak = Path()
      ..moveTo(w * 0.76, h * 0.32)
      ..lineTo(w * 0.84, h * 0.345)
      ..lineTo(w * 0.76, h * 0.37)
      ..close();
    canvas.drawPath(beak, Paint()..color = const Color(0xFFF0A029));
    canvas.drawOval(Rect.fromCenter(center: Offset(w * 0.765, h * 0.42), width: w * 0.05, height: h * 0.1),
        Paint()..color = const Color(0xFFD7263D));
  }

  @override
  bool shouldRepaint(_TurkeyPainter old) => false;
}
