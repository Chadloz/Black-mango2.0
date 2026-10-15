import 'package:flutter/material.dart';
import '../../core/widgets/poster_browser.dart';

class MoviesScreen extends StatelessWidget {
  const MoviesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PosterBrowser(kind: 'movie', noun: 'movies', playKinds: {'movie'});
  }
}
