import 'package:flutter/material.dart';
import 'theme.dart';
import '../features/live/live_screen.dart';
import '../features/movies/movies_screen.dart';
import '../features/series/series_screen.dart';
import '../features/settings/settings_screen.dart';

/// The main window: sidebar on the left, the selected section on the right.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;

  // IndexedStack keeps each section alive when you switch away and back.
  static const _screens = [
    LiveScreen(),
    MoviesScreen(),
    SeriesScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelType: NavigationRailLabelType.all,
            leading: const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: _Logo(),
            ),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.live_tv_outlined),
                selectedIcon: Icon(Icons.live_tv),
                label: Text('Live TV'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.movie_outlined),
                selectedIcon: Icon(Icons.movie),
                label: Text('Movies'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.video_library_outlined),
                selectedIcon: Icon(Icons.video_library),
                label: Text('Series'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: Text('Settings'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: IndexedStack(index: _index, children: _screens)),
        ],
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return const Text.rich(
      TextSpan(children: [
        TextSpan(text: 'B', style: TextStyle(color: BMColors.text, fontWeight: FontWeight.w800, fontSize: 22)),
        TextSpan(text: 'M', style: TextStyle(color: BMColors.mango, fontWeight: FontWeight.w800, fontSize: 22)),
      ]),
    );
  }
}
