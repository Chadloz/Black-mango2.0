import 'package:flutter/material.dart';
import '../../core/widgets/poster_browser.dart';

class SeriesScreen extends StatelessWidget {
  const SeriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PosterBrowser(kind: 'series', noun: 'shows', playKinds: {'episode', 'series'});
  }
}
