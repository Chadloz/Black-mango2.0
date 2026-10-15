import 'package:flutter/material.dart';
import '../../core/widgets/coming_soon.dart';

class SeriesScreen extends StatelessWidget {
  const SeriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoon(icon: Icons.video_library, title: 'Series', note: 'Your shows will show up here.');
  }
}
