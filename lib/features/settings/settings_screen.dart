import 'package:flutter/material.dart';
import '../../core/widgets/coming_soon.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoon(icon: Icons.settings, title: 'Settings', note: 'Accounts and preferences are coming next.');
  }
}
