import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../app/nav.dart';
import '../../core/services.dart';
import '../../core/storage/database.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<Item> _items = [];
  Map<String, String> _acctNames = {};
  String _filter = 'all'; // all | live | movie | series
  bool _loading = true;
  StreamSubscription<Set<String>>? _favSub;
  StreamSubscription<List<Account>>? _acctSub;

  @override
  void initState() {
    super.initState();
    _favSub = Services.favorites.watchKeys().listen((_) => _reload());
    _acctSub = Services.accounts.watchAll().listen((list) {
      if (!mounted) return;
      setState(() => _acctNames = {for (final a in list) a.id: a.name});
      _reload();
    });
  }

  @override
  void dispose() {
    _favSub?.cancel();
    _acctSub?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    final items = await Services.favorites.items();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _open(Item item) async {
    if (item.kind == 'live') {
      final messenger = ScaffoldMessenger.of(context);
      AppNav.index.value = AppNav.live;
      try {
        await Services.playback.play(item);
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text('Could not play: $e')));
      }
      return;
    }
    AppNav.select.value = item;
    AppNav.index.value = item.kind == 'movie' ? AppNav.movies : AppNav.shows;
  }

  @override
  Widget build(BuildContext context) {
    if (!_loading && _items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star, size: 56, color: BMColors.mango),
            SizedBox(height: 16),
            Text('No favorites yet', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: BMColors.text)),
            SizedBox(height: 8),
            Text('Tap the star on any channel, movie, or show.', style: TextStyle(color: BMColors.dim)),
          ],
        ),
      );
    }
    final counts = {
      'all': _items.length,
      'live': _items.where((i) => i.kind == 'live').length,
      'movie': _items.where((i) => i.kind == 'movie').length,
      'series': _items.where((i) => i.kind == 'series').length,
    };
    final shown = _filter == 'all' ? _items : _items.where((i) => i.kind == _filter).toList();
    const labels = {'all': 'All', 'live': 'Channels', 'movie': 'Movies', 'series': 'Shows'};
    return Column(
      children: [
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            children: [
              for (final k in labels.keys)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('${labels[k]} (${counts[k]})'),
                    selected: _filter == k,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _filter = k),
                    selectedColor: BMColors.mango.withAlpha(0x33),
                    labelStyle: TextStyle(color: _filter == k ? BMColors.mango : BMColors.text),
                    side: BorderSide(color: _filter == k ? BMColors.mango : BMColors.border),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 170,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 0.56,
            ),
            itemCount: shown.length,
            itemBuilder: (context, i) {
              final it = shown[i];
              return _FavTile(
                item: it,
                accountName: _acctNames[it.accountId] ?? '',
                onOpen: () => _open(it),
                onUnfav: () => Services.favorites.toggle(it),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FavTile extends StatelessWidget {
  final Item item;
  final String accountName;
  final VoidCallback onOpen;
  final VoidCallback onUnfav;
  const _FavTile({required this.item, required this.accountName, required this.onOpen, required this.onUnfav});

  @override
  Widget build(BuildContext context) {
    final isLive = item.kind == 'live';
    final kindLabel = isLive ? 'Channel' : (item.kind == 'movie' ? 'Movie' : 'Show');
    final fallback = Center(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Text(item.name,
            textAlign: TextAlign.center, maxLines: 4, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: BMColors.dim, fontSize: 13)),
      ),
    );
    final art = item.logo.startsWith('http')
        ? Image.network(
            item.logo,
            fit: isLive ? BoxFit.contain : BoxFit.cover,
            cacheWidth: 340,
            errorBuilder: (_, _, _) => fallback,
          )
        : fallback;
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    color: BMColors.surfaceHigh,
                    padding: isLive ? const EdgeInsets.all(18) : EdgeInsets.zero,
                    child: art,
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: IconButton.filledTonal(
                    tooltip: 'Remove from favorites',
                    onPressed: onUnfav,
                    icon: Icon(Icons.star, color: BMColors.mango, size: 18),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(item.name,
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: BMColors.text)),
          Text(accountName.isEmpty ? kindLabel : '$kindLabel   $accountName',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: BMColors.mango, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
