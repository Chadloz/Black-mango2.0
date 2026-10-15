import 'package:flutter/material.dart';
import '../../core/widgets/coming_soon.dart';

class MoviesScreen extends StatelessWidget {
  const MoviesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoon(icon: Icons.movie, title: 'Movies', note: 'Your movie library will show up here.');
  }
}
