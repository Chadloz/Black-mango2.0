import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../app/nav.dart';
import '../../core/services.dart';
import '../../core/storage/database.dart';
import '../../core/widgets/wordmark.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<WatchEntry> _continue = [];
  List<WatchEntry> _channels = [];
  List<Item> _favs = [];
  Map<String, String> _acctNames = {};
  bool _hasAccounts = true;
  bool _loading = true;
  final _subs = <StreamSubscription>[];

  @override
  void initState() {
    super.initState();
    _subs.add(Services.history.watchAll().listen((_) => _reload()));
    _subs.add(Services.favorites.watchKeys().listen((_) => _reload()));
    _subs.add(Services.accounts.watchAll().listen((list) {
      if (!mounted) return;
      setState(() {
        _acctNames = {for (final a in list) a.id: a.name};
        _hasAccounts = list.isNotEmpty;
      });
      _reload();
    }));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  Future<void> _reload() async {
    final cont = await Services.history.continueWatching();
    final chans = await Services.history.recentChannels();
    final favs = await Services.favorites.items();
    if (!mounted) return;
    setState(() {
      _continue = cont;
      _channels = chans;
      _favs = favs;
      _loading = false;
    });
  }

  Future<void> _play(Item item, int screen) async {
    final messenger = ScaffoldMessenger.of(context);
    AppNav.index.value = screen;
    try {
      await Services.playback.play(item);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not play: $e')));
    }
  }

  void _openFav(Item item) {
    if (item.kind == 'live') {
      _play(item, AppNav.live);
      return;
    }
    AppNav.select.value = item;
    AppNav.index.value = item.kind == 'movie' ? AppNav.movies : AppNav.shows;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (!_hasAccounts) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandLogo(height: 140),
            const SizedBox(height: 16),
            Text('Welcome to Black Mango', style: BMFonts.titleStyle(26)),
            const SizedBox(height: 8),
            Text('Add an account or a free channel pack to get started.', style: TextStyle(color: BMColors.dim)),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => AppNav.index.value = AppNav.accounts,
              icon: const Icon(Icons.add),
              label: const Text('Add an account'),
            ),
          ],
        ),
      );
    }
    if (_continue.isEmpty && _channels.isEmpty && _favs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.home, size: 56, color: BMColors.mango),
            SizedBox(height: 16),
            Text('Nothing here yet', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: BMColors.text)),
            SizedBox(height: 8),
            Text('Watch something or star a favorite and it shows up here.', style: TextStyle(color: BMColors.dim)),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        if (_continue.isNotEmpty)
          _Row(
            title: 'Continue Watching',
            height: 290,
            children: [
              for (final e in _continue)
                _Card(
                  title: e.name,
                  subtitle: _left(e),
                  art: e.logo,
                  poster: true,
                  progress: e.durationMs > 0 ? e.positionMs / e.durationMs : null,
                  onTap: () => _play(Services.history.toItem(e), e.kind == 'movie' ? AppNav.movies : AppNav.shows),
                ),
            ],
          ),
        if (_channels.isNotEmpty)
          _Row(
            title: 'Recent Channels',
            height: 190,
            children: [
              for (final e in _channels)
                _Card(
                  title: e.name,
                  subtitle: _acctNames[e.accountId] ?? '',
                  art: e.logo,
                  poster: false,
                  onTap: () => _play(Services.history.toItem(e), AppNav.live),
                ),
            ],
          ),
        if (_favs.isNotEmpty)
          _Row(
            title: 'Favorites',
            height: 290,
            onSeeAll: () => AppNav.index.value = AppNav.favorites,
            children: [
              for (final it in _favs.take(20))
                _Card(
                  title: it.name,
                  subtitle: it.kind == 'live' ? 'Channel' : (it.kind == 'movie' ? 'Movie' : 'Show'),
                  art: it.logo,
                  poster: it.kind != 'live',
                  onTap: () => _openFav(it),
                ),
            ],
          ),
      ],
    );
  }

  String _left(WatchEntry e) {
    if (e.durationMs <= 0) return 'In progress';
    final mins = ((e.durationMs - e.positionMs) / 60000).ceil();
    return mins >= 60 ? '${mins ~/ 60} hr ${mins % 60} min left' : '$mins min left';
  }
}

class _Row extends StatelessWidget {
  final String title;
  final double height;
  final List<Widget> children;
  final VoidCallback? onSeeAll;
  const _Row({required this.title, required this.height, required this.children, this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title, style: BMFonts.titleStyle(20)),
              const Spacer(),
              if (onSeeAll != null) TextButton(onPressed: onSeeAll, child: const Text('See all')),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: height,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: children.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, i) => children[i],
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final String subtitle;
  final String art;
  final bool poster;
  final double? progress;
  final VoidCallback onTap;
  const _Card({required this.title, required this.subtitle, required this.art, required this.poster, required this.onTap, this.progress});

  @override
  Widget build(BuildContext context) {
    final fallback = Center(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Text(title,
            textAlign: TextAlign.center, maxLines: 4, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: BMColors.dim, fontSize: 13)),
      ),
    );
    return SizedBox(
      width: 150,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      color: BMColors.surfaceHigh,
                      padding: poster ? EdgeInsets.zero : const EdgeInsets.all(18),
                      child: art.startsWith('http')
                          ? Image.network(art,
                              fit: poster ? BoxFit.cover : BoxFit.contain,
                              cacheWidth: 300,
                              errorBuilder: (_, _, _) => fallback)
                          : fallback,
                    ),
                    if (progress != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          value: progress!.clamp(0.0, 1.0),
                          minHeight: 4,
                          backgroundColor: Colors.black54,
                          color: BMColors.mango,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(title,
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: BMColors.text)),
            if (subtitle.isNotEmpty)
              Text(subtitle,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: BMColors.mango, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
