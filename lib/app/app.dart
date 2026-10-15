import 'package:flutter/material.dart';
import 'theme.dart';
import 'shell.dart';

class BlackMangoApp extends StatelessWidget {
  const BlackMangoApp({super.key});

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
