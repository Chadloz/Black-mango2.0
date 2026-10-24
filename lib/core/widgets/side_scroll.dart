import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A sideways row that works with a mouse, not just a trackpad: a scrollbar you can drag
/// (or click along), and the mouse wheel slides the row left and right.
///
/// [wheelAnywhere] true: the wheel slides it anywhere over the row (category strips, which sit
/// above a list). False: only over the scrollbar along its bottom edge (Home's rows), so
/// scrolling the page with the wheel never gets stuck on a row.
class SideScroll extends StatefulWidget {
  final Widget Function(ScrollController controller) builder;
  final bool wheelAnywhere;
  const SideScroll({super.key, required this.builder, this.wheelAnywhere = true});

  /// Room to leave under the row's contents for the scrollbar.
  static const barSpace = 12.0;

  @override
  State<SideScroll> createState() => _SideScrollState();
}

class _SideScrollState extends State<SideScroll> {
  final _c = ScrollController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _wheel(PointerSignalEvent e) {
    if (e is! PointerScrollEvent || !_c.hasClients) return;
    // A sideways wheel or Shift+wheel already moves the row by itself.
    final delta = e.scrollDelta.dy;
    if (delta == 0 || _c.position.maxScrollExtent <= 0) return;
    if (!widget.wheelAnywhere) {
      final box = context.findRenderObject();
      if (box is! RenderBox || e.localPosition.dy < box.size.height - SideScroll.barSpace - 6) return;
    }
    // Claim the wheel, so a scrolling page around the row doesn't move too.
    GestureBinding.instance.pointerSignalResolver.register(e, (_) {
      if (!_c.hasClients) return;
      _c.jumpTo((_c.offset + delta).clamp(0.0, _c.position.maxScrollExtent));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _wheel,
      child: Scrollbar(
        controller: _c,
        thumbVisibility: true,
        interactive: true,
        thickness: 6,
        radius: const Radius.circular(3),
        child: widget.builder(_c),
      ),
    );
  }
}
