import 'package:flutter/material.dart';
import 'theme.dart';
import 'shell.dart';
import 'skins.dart';

class BlackMangoApp extends StatefulWidget {
  const BlackMangoApp({super.key});

  @override
  State<BlackMangoApp> createState() => _BlackMangoAppState();
}

class _BlackMangoAppState extends State<BlackMangoApp> {
  @override
  void initState() {
    super.initState();
    Skins.current.addListener(_onSkin);
  }

  @override
  void dispose() {
    Skins.current.removeListener(_onSkin);
    super.dispose();
  }

  /// A new skin: rebuild the theme, then every widget (even ones that normally never rebuild),
  /// so the whole app repaints in the new colors without losing your place.
  void _onSkin() {
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      void mark(Element e) {
        e.markNeedsBuild();
        e.visitChildren(mark);
      }

      if (mounted) (context as Element).visitChildren(mark);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Black Mango',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const Shell(),
    );
  }
}
