import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// Picks a color from anywhere on screen, outside Black Mango's window too.
/// Mac: Apple's own screen sampler (the magnifier from the system color panel); no permission
/// needed. Windows: the screen Black Mango is on freezes, a magnifier follows the mouse, click.
/// The native halves live in macos/Runner/MainFlutterWindow.swift and windows/runner/flutter_window.cpp.
class Eyedropper {
  static const _ch = MethodChannel('blackmango/eyedropper');

  static bool get supported => Platform.isMacOS || Platform.isWindows;

  /// The color picked, or null if cancelled.
  static Future<Color?> pick(BuildContext context) async {
    if (Platform.isMacOS) {
      final v = await _ch.invokeMethod<int>('pick');
      return v == null ? null : Color(0xFF000000 | v);
    }
    if (Platform.isWindows) return _windows(Navigator.of(context, rootNavigator: true));
    return null;
  }

  static Future<Color?> _windows(NavigatorState nav) async {
    final m = await _ch.invokeMapMethod<String, Object?>('capture');
    if (m == null) return null;
    final w = m['width'] as int;
    final h = m['height'] as int;
    final bgra = m['bytes'] as Uint8List;
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(bgra, w, h, ui.PixelFormat.bgra8888, done.complete);
    final image = await done.future;

    // Cover the whole screen with the frozen copy, then put the window back as it was.
    final full = await windowManager.isFullScreen();
    final maximized = await windowManager.isMaximized();
    final onTop = await windowManager.isAlwaysOnTop();
    final bounds = await windowManager.getBounds();
    try {
      await windowManager.setAlwaysOnTop(true);
      if (!full) await windowManager.setFullScreen(true);
      return await nav.push<Color>(PageRouteBuilder<Color>(
        opaque: true,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, a1, a2) => _FrozenScreen(image: image, bgra: bgra, width: w, height: h),
      ));
    } finally {
      if (!full) await windowManager.setFullScreen(false);
      if (!onTop) await windowManager.setAlwaysOnTop(false);
      if (!full && !maximized) await windowManager.setBounds(bounds);
      image.dispose();
    }
  }
}

/// Windows: the frozen screen. Click to pick, right-click, Esc or Cancel to stop.
class _FrozenScreen extends StatefulWidget {
  final ui.Image image;
  final Uint8List bgra;
  final int width;
  final int height;
  const _FrozenScreen({required this.image, required this.bgra, required this.width, required this.height});

  @override
  State<_FrozenScreen> createState() => _FrozenScreenState();
}

class _FrozenScreenState extends State<_FrozenScreen> {
  Offset? _pos;
  Size _size = Size.zero;

  /// The screen pixel under a point of the window (the window covers the screen, so it's a ratio).
  (int, int) _pixel(Offset p) {
    final x = (_size.width == 0 ? 0 : p.dx / _size.width * widget.width).floor().clamp(0, widget.width - 1);
    final y = (_size.height == 0 ? 0 : p.dy / _size.height * widget.height).floor().clamp(0, widget.height - 1);
    return (x, y);
  }

  Color _colorAt(Offset p) {
    final (x, y) = _pixel(p);
    final i = (y * widget.width + x) * 4;
    final b = widget.bgra;
    return Color.fromARGB(255, b[i + 2], b[i + 1], b[i]);
  }

  void _cancel() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _cancel},
      child: Focus(
        autofocus: true,
        child: Material(
          color: Colors.black,
          child: LayoutBuilder(builder: (context, box) {
            _size = box.biggest;
            final pos = _pos;
            return MouseRegion(
              cursor: SystemMouseCursors.precise,
              onHover: (e) => setState(() => _pos = e.localPosition),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) => Navigator.of(context).pop(_colorAt(d.localPosition)),
                onSecondaryTap: _cancel,
                child: Stack(
                  children: [
                    Positioned.fill(child: RawImage(image: widget.image, fit: BoxFit.fill)),
                    if (pos != null) _loupe(pos),
                    Positioned(
                      top: 16,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
                          decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(10)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('Click anywhere to pick a color.', style: TextStyle(color: Colors.white, fontSize: 14)),
                              const SizedBox(width: 12),
                              TextButton(onPressed: _cancel, child: const Text('Cancel')),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _loupe(Offset pos) {
    const size = 132.0;
    final (x, y) = _pixel(pos);
    final c = _colorAt(pos);
    final hex = '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
    // Beside the pointer, flipped near the right and bottom edges.
    var left = pos.dx + 24;
    var top = pos.dy + 24;
    if (left + size > _size.width) left = pos.dx - 24 - size;
    if (top + size + 28 > _size.height) top = pos.dy - 24 - size - 28;
    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: Column(
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8)],
              ),
              child: ClipOval(child: CustomPaint(painter: _Loupe(widget.image, x, y))),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(6)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 12, height: 12, decoration: BoxDecoration(color: c, border: Border.all(color: Colors.white54))),
                  const SizedBox(width: 6),
                  Text(hex, style: const TextStyle(color: Colors.white, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 11 x 11 screen pixels around the pointer, blown up, with the center one outlined.
class _Loupe extends CustomPainter {
  final ui.Image image;
  final int x;
  final int y;
  _Loupe(this.image, this.x, this.y);

  static const _n = 11;

  @override
  void paint(Canvas canvas, Size size) {
    final src = Rect.fromLTWH((x - _n ~/ 2).toDouble(), (y - _n ~/ 2).toDouble(), _n.toDouble(), _n.toDouble());
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
    canvas.drawImageRect(image, src, Offset.zero & size, Paint()..filterQuality = FilterQuality.none);
    final cell = size.width / _n;
    final grid = Paint()
      ..color = const Color(0x33FFFFFF)
      ..strokeWidth = 1;
    for (var i = 1; i < _n; i++) {
      canvas.drawLine(Offset(i * cell, 0), Offset(i * cell, size.height), grid);
      canvas.drawLine(Offset(0, i * cell), Offset(size.width, i * cell), grid);
    }
    canvas.drawRect(
      Rect.fromLTWH((_n ~/ 2) * cell, (_n ~/ 2) * cell, cell, cell),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_Loupe o) => o.x != x || o.y != y || o.image != image;
}
