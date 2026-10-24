import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../app/theme.dart';

// Christmas 2026 decorations. Snow falls behind the content (between lists and cards, never over
// text panels or the video); everything else stays in the top bar, the window's corners outside
// the video, and the present that pops up when you add an account. Still with reduced motion.

bool _still(BuildContext context) => MediaQuery.of(context).disableAnimations;

/// Gentle snowfall behind the content.
class Snowfall extends StatefulWidget {
  const Snowfall({super.key});

  @override
  State<Snowfall> createState() => _SnowfallState();
}

class _Flake {
  double x; // 0..1 across
  double y; // pixels from the top
  final double speed;
  final double sway;
  final double phase;
  final double r;
  final double alpha;
  _Flake(this.x, this.y, this.speed, this.sway, this.phase, this.r, this.alpha);
}

class _SnowfallState extends State<Snowfall> with SingleTickerProviderStateMixin {
  final _rnd = Random();
  final _time = ValueNotifier<double>(0);
  late final List<_Flake> _flakes = List.generate(46, (_) => _newFlake(top: false));
  Ticker? _ticker;
  Duration _last = Duration.zero;
  double _height = 800;

  _Flake _newFlake({required bool top}) => _Flake(
        _rnd.nextDouble(),
        top ? -8 : _rnd.nextDouble() * 800,
        14 + _rnd.nextDouble() * 24,
        6 + _rnd.nextDouble() * 14,
        _rnd.nextDouble() * pi * 2,
        1.2 + _rnd.nextDouble() * 2.2,
        0.35 + _rnd.nextDouble() * 0.45,
      );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_still(context)) {
      _ticker?.stop();
    } else {
      _ticker ??= createTicker(_tick);
      if (!_ticker!.isActive) _ticker!.start();
    }
  }

  void _tick(Duration now) {
    final dt = ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = now;
    for (var i = 0; i < _flakes.length; i++) {
      final f = _flakes[i];
      f.y += f.speed * dt;
      if (f.y > _height + 10) _flakes[i] = _newFlake(top: true);
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
        return CustomPaint(size: box.biggest, painter: _SnowPainter(_flakes, _time));
      }),
    );
  }
}

class _SnowPainter extends CustomPainter {
  final List<_Flake> flakes;
  final ValueNotifier<double> time;
  _SnowPainter(this.flakes, this.time) : super(repaint: time);

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final p = Paint();
    for (final f in flakes) {
      final x = f.x * size.width + sin(t * 0.8 + f.phase) * f.sway;
      p.color = Colors.white.withValues(alpha: f.alpha);
      canvas.drawCircle(Offset(x, f.y), f.r, p);
    }
  }

  @override
  bool shouldRepaint(_SnowPainter old) => false;
}

/// Snow piled along the top edge of the top bar.
class SnowCap extends StatelessWidget {
  const SnowCap({super.key});

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _SnowCapPainter(), size: Size.infinite);
}

class _SnowCapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rnd = Random(7); // the same drift every time
    final shadow = Paint()..color = const Color(0x55A9C6E8);
    final snow = Paint()..color = const Color(0xF2FFFFFF);
    final lumps = <(double, double)>[];
    for (var x = -6.0; x < size.width + 12; x += 9 + rnd.nextDouble() * 8) {
      lumps.add((x, 4 + rnd.nextDouble() * 5));
    }
    for (final (x, r) in lumps) {
      canvas.drawCircle(Offset(x, r * 0.35 + 1.5), r, shadow);
    }
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 3), snow);
    for (final (x, r) in lumps) {
      canvas.drawCircle(Offset(x, r * 0.35), r, snow);
    }
  }

  @override
  bool shouldRepaint(_SnowCapPainter old) => false;
}

/// Twinkling string lights along the bottom of the top bar.
class StringLights extends StatefulWidget {
  const StringLights({super.key});

  @override
  State<StringLights> createState() => _StringLightsState();
}

class _StringLightsState extends State<StringLights> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 6));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_still(context)) {
      _c.stop();
      _c.value = 0.25;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(painter: _LightsPainter(_c), size: Size.infinite),
      );
}

class _LightsPainter extends CustomPainter {
  final Animation<double> t;
  _LightsPainter(this.t) : super(repaint: t);

  static const _colors = [Color(0xFFE0393E), Color(0xFF3FAE5A), Color(0xFFF2C14E), Color(0xFF4FA3E0), Color(0xFFFFF4D6)];

  @override
  void paint(Canvas canvas, Size size) {
    const span = 72.0; // the wire sags between hooks this far apart
    const top = 2.0, sag = 7.0;
    final wire = Paint()
      ..color = const Color(0xFF2B3A2E)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    double wireY(double x) {
      final u = (x % span) / span;
      return top + sag * 4 * u * (1 - u);
    }

    final path = Path()..moveTo(0, wireY(0));
    for (var x = 2.0; x <= size.width; x += 2) {
      path.lineTo(x, wireY(x));
    }
    canvas.drawPath(path, wire);

    final rnd = Random(3);
    var i = 0;
    for (var x = 11.0; x < size.width - 4; x += 18, i++) {
      final y = wireY(x);
      final color = _colors[i % _colors.length];
      final speed = 1 + rnd.nextInt(3);
      final phase = rnd.nextDouble();
      final glow = 0.5 + 0.5 * sin(2 * pi * (t.value * speed + phase));
      final c = Offset(x, y + 6);
      canvas.drawCircle(
        c,
        6,
        Paint()
          ..color = color.withValues(alpha: 0.35 * glow)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawRect(Rect.fromCenter(center: Offset(x, y + 1.5), width: 3, height: 3), Paint()..color = const Color(0xFF55605A));
      canvas.drawOval(
        Rect.fromCenter(center: c, width: 5.5, height: 8),
        Paint()..color = Color.lerp(Color.lerp(color, Colors.black, 0.45)!, color, 0.35 + 0.65 * glow)!,
      );
    }
  }

  @override
  bool shouldRepaint(_LightsPainter old) => false;
}

/// Frost creeping in from the window's top corners (inside the top bar) and its bottom-left corner
/// (the sidebar). None of them reach the video.
class FrostCorners extends StatelessWidget {
  const FrostCorners({super.key});

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _FrostPainter(), size: Size.infinite);
}

class _FrostPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    _corner(canvas, Offset.zero, 0, 1);
    _corner(canvas, Offset(size.width, 0), pi / 2, 2);
    _corner(canvas, Offset(0, size.height), -pi / 2, 3);
  }

  /// Ice crystals growing from a corner, spreading over a quarter turn starting at [start].
  void _corner(Canvas canvas, Offset at, double start, int seed) {
    final rnd = Random(seed);
    final paint = Paint()
      ..color = const Color(0x66DDEEFF)
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;
    for (var k = 0; k < 6; k++) {
      final a = start + (k + 0.5) * (pi / 2) / 6 + (rnd.nextDouble() - 0.5) * 0.15;
      _branch(canvas, at, a, 26 + rnd.nextDouble() * 30, 3, rnd, paint);
    }
  }

  void _branch(Canvas canvas, Offset from, double a, double len, int depth, Random rnd, Paint paint) {
    final to = from + Offset(cos(a), sin(a)) * len;
    canvas.drawLine(from, to, paint);
    if (depth == 0) return;
    for (var i = 1; i <= 3; i++) {
      final p = Offset.lerp(from, to, i / 4)!;
      final side = len * (0.32 - i * 0.05);
      _branch(canvas, p, a + 0.75, side, depth - 1, rnd, paint);
      _branch(canvas, p, a - 0.75, side, depth - 1, rnd, paint);
    }
  }

  @override
  bool shouldRepaint(_FrostPainter old) => false;
}

/// The top bar's little winter scene: a snowman, an elf with a present, and a reindeer.
class WinterScene extends StatelessWidget {
  const WinterScene({super.key});

  @override
  Widget build(BuildContext context) =>
      IgnorePointer(child: CustomPaint(size: const Size(186, 58), painter: _ScenePainter()));
}

class _ScenePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final ground = size.height - 3;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, ground - 2, size.width, 5), const Radius.circular(3)),
      Paint()..color = const Color(0xE6FFFFFF),
    );
    _snowman(canvas, Offset(24, ground));
    _elf(canvas, Offset(74, ground));
    _reindeer(canvas, Offset(136, ground));
  }

  void _snowman(Canvas canvas, Offset base) {
    final snow = Paint()..color = const Color(0xFFF7FAFF);
    final edge = Paint()
      ..color = const Color(0xFFB8CBE0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final (dy, r) in [(-12.0, 12.0), (-31.0, 9.0), (-45.0, 7.0)]) {
      canvas.drawCircle(base + Offset(0, dy), r, snow);
      canvas.drawCircle(base + Offset(0, dy), r, edge);
    }
    final coal = Paint()..color = const Color(0xFF1E1E1E);
    canvas.drawCircle(base + const Offset(-2.5, -47), 1.2, coal);
    canvas.drawCircle(base + const Offset(2.5, -47), 1.2, coal);
    for (final dy in [-35.0, -30.0, -25.0]) {
      canvas.drawCircle(base + Offset(0, dy), 1.1, coal);
    }
    final nose = Path()
      ..moveTo(base.dx + 1, base.dy - 45)
      ..lineTo(base.dx + 9, base.dy - 44)
      ..lineTo(base.dx + 1, base.dy - 43)
      ..close();
    canvas.drawPath(nose, Paint()..color = const Color(0xFFF08A24));
    // Scarf and a knit beanie.
    final red = Paint()..color = const Color(0xFFD7263D);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: base + const Offset(0, -39), width: 16, height: 4), const Radius.circular(2)), red);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(base.dx + 3, base.dy - 39, 4, 10), const Radius.circular(2)), red);
    canvas.drawArc(Rect.fromCenter(center: base + const Offset(0, -50), width: 14, height: 12), pi, pi, true, Paint()..color = const Color(0xFF2E8B57));
    canvas.drawCircle(base + const Offset(0, -57), 2.4, snow);
    // Stick arms.
    final stick = Paint()
      ..color = const Color(0xFF6B4423)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(base + const Offset(-8, -33), base + const Offset(-19, -40), stick);
    canvas.drawLine(base + const Offset(8, -33), base + const Offset(19, -41), stick);
  }

  void _elf(Canvas canvas, Offset base) {
    final green = Paint()..color = const Color(0xFF2E8B57);
    final skin = Paint()..color = const Color(0xFFE8B68C);
    // Legs in striped stockings, curly shoes.
    for (final dx in [-3.5, 3.5]) {
      canvas.drawRect(Rect.fromLTWH(base.dx + dx - 1.5, base.dy - 12, 3, 10), Paint()..color = const Color(0xFFF2F2F2));
      for (var y = 0; y < 10; y += 3) {
        canvas.drawRect(Rect.fromLTWH(base.dx + dx - 1.5, base.dy - 12 + y.toDouble(), 3, 1.5), Paint()..color = const Color(0xFFD7263D));
      }
      canvas.drawOval(Rect.fromCenter(center: base + Offset(dx * 1.6, -1.5), width: 7, height: 3.5), Paint()..color = const Color(0xFF7A4A2A));
    }
    // Tunic with a belt.
    final tunic = Path()
      ..moveTo(base.dx - 6, base.dy - 30)
      ..lineTo(base.dx + 6, base.dy - 30)
      ..lineTo(base.dx + 10, base.dy - 12)
      ..lineTo(base.dx - 10, base.dy - 12)
      ..close();
    canvas.drawPath(tunic, green);
    canvas.drawRect(Rect.fromLTWH(base.dx - 8, base.dy - 20, 16, 2.6), Paint()..color = const Color(0xFF1E1E1E));
    canvas.drawRect(Rect.fromCenter(center: base + const Offset(0, -18.7), width: 3.4, height: 3.4), Paint()..color = const Color(0xFFF2C14E));
    // Head, pointy ears, and a hat that flops over with a bell.
    canvas.drawCircle(base + const Offset(0, -36), 6, skin);
    for (final s in [-1.0, 1.0]) {
      final ear = Path()
        ..moveTo(base.dx + s * 5, base.dy - 38)
        ..lineTo(base.dx + s * 10, base.dy - 41)
        ..lineTo(base.dx + s * 5.5, base.dy - 34)
        ..close();
      canvas.drawPath(ear, skin);
    }
    canvas.drawCircle(base + const Offset(-2, -36.5), 0.9, Paint()..color = const Color(0xFF1E1E1E));
    canvas.drawCircle(base + const Offset(2, -36.5), 0.9, Paint()..color = const Color(0xFF1E1E1E));
    final hat = Path()
      ..moveTo(base.dx - 7, base.dy - 40)
      ..quadraticBezierTo(base.dx, base.dy - 56, base.dx + 12, base.dy - 50)
      ..lineTo(base.dx + 7, base.dy - 40)
      ..close();
    canvas.drawPath(hat, Paint()..color = const Color(0xFFD7263D));
    canvas.drawRect(Rect.fromLTWH(base.dx - 7.5, base.dy - 42, 15, 3), Paint()..color = const Color(0xFFF7FAFF));
    canvas.drawCircle(base + const Offset(12.5, -49), 2.2, Paint()..color = const Color(0xFFF2C14E));
    // A present under one arm.
    final box = Rect.fromLTWH(base.dx + 7, base.dy - 26, 11, 10);
    canvas.drawRect(box, Paint()..color = const Color(0xFFD7263D));
    canvas.drawRect(Rect.fromLTWH(box.center.dx - 1, box.top, 2, box.height), Paint()..color = const Color(0xFFF2C14E));
    canvas.drawRect(Rect.fromLTWH(box.left, box.center.dy - 1, box.width, 2), Paint()..color = const Color(0xFFF2C14E));
  }

  void _reindeer(Canvas canvas, Offset base) {
    final fur = Paint()..color = const Color(0xFF8A5A33);
    final dark = Paint()..color = const Color(0xFF5E3B20);
    final legs = Paint()
      ..color = const Color(0xFF5E3B20)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (final dx in [-14.0, -8.0, 9.0, 15.0]) {
      canvas.drawLine(base + Offset(dx, -16), base + Offset(dx, -1), legs);
    }
    canvas.drawOval(Rect.fromCenter(center: base + const Offset(0, -20), width: 40, height: 16), fur);
    canvas.drawCircle(base + const Offset(-20, -23), 2.6, Paint()..color = const Color(0xFFF7FAFF)); // tail
    // Neck and head, looking right.
    final neck = Path()
      ..moveTo(base.dx + 12, base.dy - 26)
      ..lineTo(base.dx + 20, base.dy - 38)
      ..lineTo(base.dx + 26, base.dy - 34)
      ..lineTo(base.dx + 18, base.dy - 20)
      ..close();
    canvas.drawPath(neck, fur);
    canvas.drawOval(Rect.fromCenter(center: base + const Offset(27, -38), width: 15, height: 9), fur);
    canvas.drawCircle(base + const Offset(34, -38), 1.8, Paint()..color = const Color(0xFF1E1E1E)); // nose
    canvas.drawCircle(base + const Offset(25, -40), 1, Paint()..color = const Color(0xFF1E1E1E)); // eye
    canvas.drawOval(Rect.fromCenter(center: base + const Offset(21, -41), width: 6, height: 3), dark); // ear
    // Antlers.
    final antler = Paint()
      ..color = const Color(0xFFC9A26B)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final s in [0.0, 4.0]) {
      final root = base + Offset(23 + s, -42);
      canvas.drawLine(root, root + const Offset(-3, -10), antler);
      canvas.drawLine(root + const Offset(-1.5, -5), root + const Offset(-6, -8), antler);
      canvas.drawLine(root + const Offset(-2.4, -8), root + const Offset(1, -12), antler);
    }
    // A collar with a gold bell.
    canvas.drawLine(base + const Offset(14, -26), base + const Offset(20, -23),
        Paint()
          ..color = const Color(0xFFD7263D)
          ..strokeWidth = 3);
    canvas.drawCircle(base + const Offset(18, -21.5), 2, Paint()..color = const Color(0xFFF2C14E));
  }

  @override
  bool shouldRepaint(_ScenePainter old) => false;
}

/// The present: pops up from a bottom corner when you add an account (Christmas skins), its lid
/// bursts open, and it says Ho ho ho! with the account's name.
class Present {
  static void open(OverlayState overlay, String name) {
    late final OverlayEntry entry;
    entry = OverlayEntry(builder: (_) => _PresentPop(name: name, onDone: () => entry.remove()));
    overlay.insert(entry);
  }
}

class _PresentPop extends StatefulWidget {
  final String name;
  final VoidCallback onDone;
  const _PresentPop({required this.name, required this.onDone});

  @override
  State<_PresentPop> createState() => _PresentPopState();
}

class _PresentPopState extends State<_PresentPop> with SingleTickerProviderStateMixin {
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
          final fade = t < 0.1 ? t / 0.1 : (t > 0.82 ? (1 - t) / 0.18 : 1.0);
          final rise = Curves.easeOutBack.transform((t / 0.25).clamp(0.0, 1.0));
          final pop = Curves.easeOut.transform(((t - 0.25) / 0.2).clamp(0.0, 1.0));
          final present = Opacity(
            opacity: fade.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, 80 * (1 - rise)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: _left ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                children: [
                  Opacity(
                    opacity: pop,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 260),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: BMColors.surfaceHigh,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: BMColors.mango, width: 1.5),
                      ),
                      child: Text(
                        'Ho ho ho! ${widget.name} added',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: BMColors.text, fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  CustomPaint(size: const Size(84, 84), painter: _PresentPainter(pop)),
                ],
              ),
            ),
          );
          return Stack(
            children: [
              Positioned(left: _left ? 28 : null, right: _left ? null : 28, bottom: 20, child: present),
            ],
          );
        },
      ),
    );
  }
}

class _PresentPainter extends CustomPainter {
  final double open; // 0 closed, 1 lid off
  _PresentPainter(this.open);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    const box = Color(0xFFD7263D), ribbon = Color(0xFFF2C14E);
    // Sparkles once it's open.
    if (open > 0) {
      final spark = Paint()
        ..color = ribbon.withValues(alpha: (1 - open * 0.6))
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 7; i++) {
        final a = -pi / 2 + (i - 3) * 0.32;
        final r1 = 10 + 18 * open, r2 = 16 + 26 * open;
        final c = Offset(w / 2, h * 0.42);
        canvas.drawLine(c + Offset(cos(a), sin(a)) * r1, c + Offset(cos(a), sin(a)) * r2, spark);
      }
    }
    final body = RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.18, h * 0.45, w * 0.64, h * 0.5), const Radius.circular(5));
    canvas.drawRRect(body, Paint()..color = box);
    canvas.drawRect(Rect.fromLTWH(w * 0.46, h * 0.45, w * 0.08, h * 0.5), Paint()..color = ribbon);
    canvas.save();
    canvas.translate(w * 0.5 + open * 14, h * 0.38 - open * 26);
    canvas.rotate(open * 0.55);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: w * 0.72, height: h * 0.14), const Radius.circular(4)),
      Paint()..color = box,
    );
    canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: w * 0.08, height: h * 0.14), Paint()..color = ribbon);
    final bow = Paint()..color = ribbon;
    canvas.drawOval(Rect.fromCenter(center: Offset(-w * 0.08, -h * 0.1), width: w * 0.16, height: h * 0.1), bow);
    canvas.drawOval(Rect.fromCenter(center: Offset(w * 0.08, -h * 0.1), width: w * 0.16, height: h * 0.1), bow);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PresentPainter o) => o.open != open;
}
