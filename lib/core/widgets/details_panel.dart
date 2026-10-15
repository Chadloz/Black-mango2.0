import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../services.dart';
import '../storage/database.dart';
import '../catalog/details.dart';

/// Right-side info panel for a movie or show: poster, info, Play, and episodes.
class DetailsPanel extends StatefulWidget {
  final Item item;
  final String accountName;
  final VoidCallback onClose;
  final VoidCallback onPlayed;
  final VoidCallback? onBackToVideo;
  const DetailsPanel({
    super.key,
    required this.item,
    required this.accountName,
    required this.onClose,
    required this.onPlayed,
    this.onBackToVideo,
  });

  @override
  State<DetailsPanel> createState() => _DetailsPanelState();
}

class _DetailsPanelState extends State<DetailsPanel> {
  Details? _d;
  String? _err;
  bool _loading = true;
  int? _season;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Services.catalog.details(widget.item);
      if (!mounted) return;
      final seasons = d.seasons.keys.toList()..sort();
      setState(() {
        _d = d;
        _season = seasons.isEmpty ? null : seasons.first;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = '$e';
        _loading = false;
      });
    }
  }

  bool get _canPlayDirect => widget.item.kind == 'movie' || widget.item.url.isNotEmpty;

  Future<void> _playItem() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Services.playback.play(widget.item);
      widget.onPlayed();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not play: $e')));
    }
  }

  Future<void> _playEp(EpisodeInfo ep) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Services.playback.playEpisode(widget.item, ep);
      widget.onPlayed();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not play: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final poster = (d != null && d.poster.isNotEmpty) ? d.poster : widget.item.logo;
    final meta = [
      if (d != null && d.year.isNotEmpty) d.year,
      if (d != null && d.duration.isNotEmpty) d.duration,
      if (d != null && d.rating.isNotEmpty) '★ ${d.rating}',
      if (d != null && d.genre.isNotEmpty) d.genre else if (widget.item.genre.isNotEmpty) widget.item.genre,
    ].join('   ·   ');
    final placeholder = Container(
      color: BMColors.surfaceHigh,
      alignment: Alignment.center,
      child: const Icon(Icons.movie, color: BMColors.dim, size: 40),
    );
    final seasons = d == null ? <int>[] : (d.seasons.keys.toList()..sort());
    final episodes = (d == null || _season == null) ? <EpisodeInfo>[] : (d.seasons[_season] ?? <EpisodeInfo>[]);

    return Container(
      color: BMColors.background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (d != null && d.backdrop.isNotEmpty)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 280,
              child: Opacity(
                opacity: 0.25,
                child: Image.network(d.backdrop, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
              ),
            ),
          ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 150,
                      height: 225,
                      child: poster.startsWith('http')
                          ? Image.network(poster, fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder)
                          : placeholder,
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 32),
                        Text(widget.item.name,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: BMColors.text)),
                        const SizedBox(height: 8),
                        if (meta.isNotEmpty) Text(meta, style: const TextStyle(fontSize: 13, color: BMColors.dim)),
                        if (widget.accountName.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(widget.accountName,
                                style: const TextStyle(fontSize: 12, color: BMColors.mango, fontWeight: FontWeight.w600)),
                          ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (_canPlayDirect)
                              FilledButton.icon(
                                onPressed: _playItem,
                                icon: const Icon(Icons.play_arrow),
                                label: const Text('Play'),
                              ),
                            if (widget.onBackToVideo != null)
                              OutlinedButton.icon(
                                onPressed: widget.onBackToVideo,
                                icon: const Icon(Icons.ondemand_video),
                                label: const Text('Back to video'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (_loading) const LinearProgressIndicator(),
              if (_err != null)
                Text("Couldn't load details: $_err", style: const TextStyle(color: BMColors.dim)),
              if (d != null && d.plot.isNotEmpty)
                Text(d.plot, style: const TextStyle(fontSize: 15, height: 1.5, color: BMColors.text)),
              if (d != null && d.cast.isNotEmpty) _kv('Cast', d.cast),
              if (d != null && d.director.isNotEmpty) _kv('Director', d.director),
              if (seasons.isNotEmpty) ...[
                const SizedBox(height: 24),
                Row(
                  children: [
                    const Text('Episodes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: BMColors.text)),
                    const Spacer(),
                    DropdownButton<int>(
                      value: _season,
                      underline: const SizedBox.shrink(),
                      items: [for (final s in seasons) DropdownMenuItem(value: s, child: Text('Season $s'))],
                      onChanged: (v) => setState(() => _season = v),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (final ep in episodes) _EpisodeRow(ep: ep, onTap: () => _playEp(ep)),
              ],
              if (d != null && !_loading && widget.item.kind == 'series' && seasons.isEmpty && !_canPlayDirect)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Text('No episodes found for this show.', style: TextStyle(color: BMColors.dim)),
                ),
            ],
          ),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton.filledTonal(tooltip: 'Close', onPressed: widget.onClose, icon: const Icon(Icons.close)),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: '$k: ', style: const TextStyle(color: BMColors.dim)),
          TextSpan(text: v, style: const TextStyle(color: BMColors.text)),
        ]),
        style: const TextStyle(fontSize: 13),
      ),
    );
  }
}

class _EpisodeRow extends StatelessWidget {
  final EpisodeInfo ep;
  final VoidCallback onTap;
  const _EpisodeRow({required this.ep, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final thumbFallback = Container(
      color: BMColors.surfaceHigh,
      alignment: Alignment.center,
      child: Text('${ep.number}', style: const TextStyle(fontFamily: BMFonts.mono, color: BMColors.dim, fontSize: 18)),
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 128,
                height: 72,
                child: ep.image.isNotEmpty
                    ? Image.network(ep.image, fit: BoxFit.cover, cacheWidth: 256, errorBuilder: (_, _, _) => thumbFallback)
                    : thumbFallback,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${ep.number}.  ${ep.title.isEmpty ? 'Episode ${ep.number}' : ep.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, color: BMColors.text),
                  ),
                  if (ep.duration.isNotEmpty)
                    Text(ep.duration, style: const TextStyle(fontSize: 12, color: BMColors.dim)),
                  if (ep.plot.isNotEmpty)
                    Text(ep.plot,
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: BMColors.dim, height: 1.4)),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 22),
              child: Icon(Icons.play_circle_outline, color: BMColors.mango),
            ),
          ],
        ),
      ),
    );
  }
}
