import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A hue ring around a saturation / brightness square. Drag the ring to change the color,
/// drag in the square to make it paler or darker.
class ColorWheel extends StatefulWidget {
  final Color color;
  final ValueChanged<Color> onChanged;
  final double size;
  final Color outline;
  const ColorWheel({super.key, required this.color, required this.onChanged, required this.outline, this.size = 220});

  @override
  State<ColorWheel> createState() => _ColorWheelState();
}

class _ColorWheelState extends State<ColorWheel> {
  late HSVColor _hsv = HSVColor.fromColor(widget.color);
  int _drag = 0; // 1 = ring, 2 = square

  @override
  void didUpdateWidget(ColorWheel old) {
    super.didUpdateWidget(old);
    // A new color from outside (hex box, swatch, another slot). Keep the hue when it's a gray.
    if (widget.color.toARGB32() != _hsv.toColor().toARGB32()) {
      final h = HSVColor.fromColor(widget.color);
      _hsv = h.saturation == 0 || h.value == 0 ? h.withHue(_hsv.hue) : h;
    }
  }

  double get _outer => widget.size / 2;
  double get _ring => widget.size * 0.11;
  double get _half => (_outer - _ring - 10) / math.sqrt2; // half the square's side

  void _start(Offset p) {
    final q = p - Offset(_outer, _outer);
    if (q.dx.abs() <= _half + 8 && q.dy.abs() <= _half + 8) {
      _drag = 2;
    } else if (q.distance >= _outer - _ring - 8) {
      _drag = 1;
    } else {
      _drag = 0;
    }
    _move(p);
  }

  void _move(Offset p) {
    final q = p - Offset(_outer, _outer);
    if (_drag == 1) {
      var deg = math.atan2(q.dy, q.dx) * 180 / math.pi;
      if (deg < 0) deg += 360;
      _set(_hsv.withHue(deg % 360));
    } else if (_drag == 2) {
      final s = ((q.dx + _half) / (2 * _half)).clamp(0.0, 1.0);
      final v = (1 - (q.dy + _half) / (2 * _half)).clamp(0.0, 1.0);
      _set(_hsv.withSaturation(s).withValue(v));
    }
  }

  void _set(HSVColor h) {
    setState(() => _hsv = h);
    widget.onChanged(h.toColor());
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.precise,
      child: GestureDetector(
        onTapDown: (d) => _start(d.localPosition),
        onPanStart: (d) => _start(d.localPosition),
        onPanUpdate: (d) => _move(d.localPosition),
        child: CustomPaint(
          size: Size.square(widget.size),
          painter: _WheelPainter(_hsv, _ring, _half, widget.outline),
        ),
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  final HSVColor hsv;
  final double ring;
  final double half;
  final Color outline;
  _WheelPainter(this.hsv, this.ring, this.half, this.outline);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final hues = [for (var i = 0; i <= 12; i++) HSVColor.fromAHSV(1, (i * 30) % 360.0, 1, 1).toColor()];
    canvas.drawCircle(
      c,
      r - ring / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ring
        ..shader = SweepGradient(colors: hues).createShader(Rect.fromCircle(center: c, radius: r)),
    );

    final sq = Rect.fromCenter(center: c, width: half * 2, height: half * 2);
    final rr = RRect.fromRectAndRadius(sq, const Radius.circular(4));
    final pure = HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor();
    canvas.drawRRect(rr, Paint()..shader = LinearGradient(colors: [Colors.white, pure]).createShader(sq));
    canvas.drawRRect(
      rr,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0xFF000000)],
        ).createShader(sq),
    );
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = outline,
    );

    final a = hsv.hue * math.pi / 180;
    _thumb(canvas, c + Offset(math.cos(a), math.sin(a)) * (r - ring / 2), pure, ring / 2 + 1);
    _thumb(canvas, Offset(sq.left + hsv.saturation * sq.width, sq.top + (1 - hsv.value) * sq.height), hsv.toColor(), 8);
  }

  void _thumb(Canvas canvas, Offset p, Color fill, double rad) {
    canvas.drawCircle(p, rad, Paint()..color = fill);
    canvas.drawCircle(
      p,
      rad,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = Colors.white,
    );
    canvas.drawCircle(
      p,
      rad + 1.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x8A000000),
    );
  }

  @override
  bool shouldRepaint(_WheelPainter o) => o.hsv != hsv || o.outline != outline || o.half != half;
}
