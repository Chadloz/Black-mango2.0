import 'package:flutter/material.dart';
import '../../app/theme.dart';
import 'mini_player.dart';

/// A list's scroll controller that keeps your spot. When the window shrinks to the floating
/// player (or a layout switch rebuilds the list), the list comes back where you left it; only
/// your own scrolling moves it. Also: jump to the top or bottom, and back to where you were.
class KeepScrollController extends ScrollController {
  final int screen; // the screen this list is on (AppNav index), for the keyboard shortcuts
  double _saved = 0;
  double? _before; // where you were before the last jump

  KeepScrollController({required this.screen}) {
    _byScreen[screen] = this;
    addListener(_remember);
  }

  static final _byScreen = <int, KeepScrollController>{};

  /// The list on that screen, if it has one.
  static KeepScrollController? on(int screen) => _byScreen[screen];

  void _remember() {
    if (positions.length != 1 || PopOut.active.value) return; // the floating window squeezes the list
    _saved = position.pixels;
  }

  @override
  ScrollPosition createScrollPosition(ScrollPhysics physics, ScrollContext context, ScrollPosition? oldPosition) {
    return ScrollPositionWithSingleContext(
      physics: physics,
      context: context,
      initialPixels: _saved, // a rebuilt list starts where you were
      keepScrollOffset: false,
      oldPosition: oldPosition,
      debugLabel: debugLabel,
    );
  }

  bool toTop() {
    if (positions.length != 1) return false;
    _before = position.pixels;
    jumpTo(0);
    return true;
  }

  bool toBottom() {
    if (positions.length != 1) return false;
    _before = position.pixels;
    jumpTo(position.maxScrollExtent);
    // Long lists only know their real end once it's built: settle on it next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (positions.length == 1) jumpTo(position.maxScrollExtent);
    });
    return true;
  }

  /// Back to where you were before the last jump (press again to go back the other way).
  bool back() {
    if (positions.length != 1 || _before == null) return false;
    final here = position.pixels;
    jumpTo(_before!.clamp(0.0, position.maxScrollExtent));
    _before = here;
    return true;
  }

  @override
  void dispose() {
    if (_byScreen[screen] == this) _byScreen.remove(screen);
    super.dispose();
  }
}

/// Two small buttons over a list: to the top and to the bottom.
class JumpButtons extends StatelessWidget {
  final KeepScrollController controller;
  const JumpButtons({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    Widget b(IconData icon, String tip, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Material(
            color: BMColors.surfaceHigh,
            shape: CircleBorder(side: BorderSide(color: BMColors.border)),
            child: IconButton(
              tooltip: tip,
              visualDensity: VisualDensity.compact,
              onPressed: onTap,
              icon: Icon(icon, size: 20, color: BMColors.text),
            ),
          ),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        b(Icons.vertical_align_top, 'Jump to the top (Home)', controller.toTop),
        b(Icons.vertical_align_bottom, 'Jump to the bottom (End)', controller.toBottom),
      ],
    );
  }
}
