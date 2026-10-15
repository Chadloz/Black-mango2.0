import 'package:flutter/material.dart';
import '../../core/widgets/coming_soon.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoon(icon: Icons.home, title: 'Home', note: 'Recent, Live TV, Movies, and Shows rows will show up here.');
  }
}
