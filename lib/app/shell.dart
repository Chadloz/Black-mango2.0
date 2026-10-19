import 'package:flutter/material.dart';
import 'theme.dart';
import 'nav.dart';
import '../core/widgets/wordmark.dart';
import '../features/home/home_screen.dart';
import '../features/live/live_screen.dart';
import '../features/movies/movies_screen.dart';
import '../features/series/series_screen.dart';
import '../features/favorites/favorites_screen.dart';
import '../features/accounts/accounts_screen.dart';
import '../features/settings/settings_screen.dart';

/// One row in the sidebar: either a section header or a navigation item.
class _NavEntry {
  final String? header;
  final IconData? icon;
  final IconData? selectedIcon;
  final String? label;
  const _NavEntry.header(String this.header) : icon = null, selectedIcon = null, label = null;
  const _NavEntry.item(IconData this.icon, IconData this.selectedIcon, String this.label) : header = null;
  bool get isHeader => header != null;
}

/// The main window: top bar, collapsible sidebar, selected section.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;
  bool _expanded = true;

  @override
  void initState() {
    super.initState();
    AppNav.index.addListener(_onNav);
  }

  @override
  void dispose() {
    AppNav.index.removeListener(_onNav);
    super.dispose();
  }

  void _onNav() => setState(() => _index = AppNav.index.value);

  // Sidebar layout. Items appear in the same order as _screens below.
  static const _nav = [
    _NavEntry.item(Icons.home_outlined, Icons.home, 'Home'),
    _NavEntry.header('CONTENT'),
    _NavEntry.item(Icons.live_tv_outlined, Icons.live_tv, 'Live TV'),
    _NavEntry.item(Icons.movie_outlined, Icons.movie, 'Movies'),
    _NavEntry.item(Icons.video_library_outlined, Icons.video_library, 'Shows'),
    _NavEntry.item(Icons.star_outline, Icons.star, 'Favorites'),
    _NavEntry.header('MANAGE'),
    _NavEntry.item(Icons.person_outline, Icons.person, 'Accounts'),
    _NavEntry.item(Icons.settings_outlined, Icons.settings, 'Settings'),
  ];

  // IndexedStack keeps each section alive when you switch away and back.
  static const _screens = [
    HomeScreen(),
    LiveScreen(),
    MoviesScreen(),
    SeriesScreen(),
    FavoritesScreen(),
    AccountsScreen(),
    SettingsScreen(),
  ];

  List<_NavEntry> get _items => _nav.where((e) => !e.isHeader).toList();

  @override
  Widget build(BuildContext context) {
    final current = _items[_index].label!;
    return Scaffold(
      body: Column(
        children: [
          _TopBar(section: current, onMenu: () => setState(() => _expanded = !_expanded)),
          const Divider(height: 1),
          Expanded(
            child: Row(
              children: [
                _Sidebar(
                  entries: _nav,
                  selected: _index,
                  expanded: _expanded,
                  onSelect: (i) => AppNav.index.value = i,
                ),
                const VerticalDivider(width: 1),
                Expanded(child: IndexedStack(index: _index, children: _screens)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final String section;
  final VoidCallback onMenu;
  const _TopBar({required this.section, required this.onMenu});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72, // logo above the wordmark
      color: BMColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          IconButton(
            onPressed: onMenu,
            tooltip: 'Menu',
            icon: const Icon(Icons.menu, color: BMColors.text),
          ),
          const SizedBox(width: 8),
          const BrandStack(),
          const Spacer(),
          Text(
            section.toUpperCase(),
            style: const TextStyle(fontFamily: BMFonts.mono, fontSize: 12, letterSpacing: 2, color: BMColors.dim),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final List<_NavEntry> entries;
  final int selected;
  final bool expanded;
  final ValueChanged<int> onSelect;
  const _Sidebar({required this.entries, required this.selected, required this.expanded, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    int itemIndex = 0;
    for (final e in entries) {
      if (e.isHeader) {
        children.add(expanded
            ? Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Text(e.header!, style: const TextStyle(fontFamily: BMFonts.mono, fontSize: 11, letterSpacing: 2, color: BMColors.dim)),
              )
            : const Padding(
                padding: EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                child: Divider(height: 1),
              ));
        continue;
      }
      final i = itemIndex++;
      children.add(_SidebarItem(entry: e, selected: i == selected, expanded: expanded, onTap: () => onSelect(i)));
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: expanded ? 232 : 72,
      color: BMColors.surface,
      child: ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: children),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final _NavEntry entry;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;
  const _SidebarItem({required this.entry, required this.selected, required this.expanded, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final row = Container(
      height: 48,
      decoration: BoxDecoration(
        color: selected ? const Color(0x22FF8C00) : Colors.transparent,
        border: Border(left: BorderSide(color: selected ? BMColors.mango : Colors.transparent, width: 3)),
      ),
      padding: EdgeInsets.symmetric(horizontal: expanded ? 16 : 0),
      child: Row(
        mainAxisAlignment: expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
        children: [
          Icon(selected ? entry.selectedIcon : entry.icon, color: selected ? BMColors.mango : BMColors.dim, size: 22),
          if (expanded) ...[
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                entry.label!,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? BMColors.mango : BMColors.text,
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ],
      ),
    );
    final tappable = InkWell(onTap: onTap, child: row);
    return expanded ? tappable : Tooltip(message: entry.label!, child: tappable);
  }
}
