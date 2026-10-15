import 'package:flutter/material.dart';
import '../../core/widgets/coming_soon.dart';

class LiveScreen extends StatelessWidget {
  const LiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoon(icon: Icons.live_tv, title: 'Live TV', note: 'Add an account in Settings to load channels.');
  }
}
