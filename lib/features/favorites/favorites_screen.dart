import 'package:flutter/material.dart';
import '../../core/widgets/coming_soon.dart';

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoon(icon: Icons.star, title: 'Favorites', note: 'Starred channels, movies, and shows will show up here.');
  }
}
