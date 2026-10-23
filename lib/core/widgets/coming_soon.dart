import 'package:flutter/material.dart';
import '../../app/theme.dart';

/// Placeholder for sections that aren't built yet.
class ComingSoon extends StatelessWidget {
  final IconData icon;
  final String title;
  final String note;

  const ComingSoon({super.key, required this.icon, required this.title, required this.note});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: BMColors.mango),
          const SizedBox(height: 16),
          Text(title, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: BMColors.text)),
          const SizedBox(height: 8),
          Text(note, style: TextStyle(color: BMColors.dim)),
        ],
      ),
    );
  }
}
