import 'package:flutter/material.dart';
import '../../core/widgets/coming_soon.dart';

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoon(icon: Icons.person, title: 'Accounts', note: 'Add Xtream, Stalker, or M3U accounts, plus free channel sources.');
  }
}
