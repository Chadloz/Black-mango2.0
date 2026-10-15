/// Info for a movie or show, plus episodes for shows.

class EpisodeInfo {
  final String id;
  final int season;
  final int number;
  final String title;
  final String ext;
  final String plot;
  final String duration;
  final String image;
  const EpisodeInfo({
    required this.id,
    required this.season,
    required this.number,
    required this.title,
    required this.ext,
    required this.plot,
    required this.duration,
    required this.image,
  });
}

class Details {
  String plot = '';
  String cast = '';
  String director = '';
  String genre = '';
  String year = '';
  String duration = '';
  String rating = '';
  String backdrop = '';
  String poster = '';
  final Map<int, List<EpisodeInfo>> seasons = {};
}

String _s(dynamic v) {
  if (v == null) return '';
  if (v is List) return v.isEmpty ? '' : '${v.first}'.trim();
  return '$v'.trim();
}

String _http(dynamic v) {
  final s = _s(v);
  return s.startsWith('http') ? s : '';
}

/// Fills [d] from an Xtream get_vod_info / get_series_info answer.
Details parseDetails(dynamic j, Details d, {required bool series}) {
  if (j is! Map) return d;
  final info = j['info'] is Map ? j['info'] as Map : <dynamic, dynamic>{};
  d.plot = _s(info['plot']).isNotEmpty ? _s(info['plot']) : _s(info['description']);
  d.cast = _s(info['cast']).isNotEmpty ? _s(info['cast']) : _s(info['actors']);
  d.director = _s(info['director']);
  d.genre = _s(info['genre']);
  final release = [info['releasedate'], info['releaseDate'], info['release_date'], info['year']]
      .map(_s)
      .firstWhere((x) => x.isNotEmpty, orElse: () => '');
  d.year = release.length >= 4 ? release.substring(0, 4) : release;
  d.duration = _s(info['duration']);
  if (d.duration.isEmpty && _s(info['episode_run_time']).isNotEmpty) d.duration = '${_s(info['episode_run_time'])} min';
  final r = double.tryParse(_s(info['rating']));
  d.rating = (r == null || r == 0) ? '' : r.toStringAsFixed(1);
  d.backdrop = _http(info['backdrop_path']);
  for (final k in ['movie_image', 'cover_big', 'cover']) {
    final p = _http(info[k]);
    if (p.isNotEmpty) {
      d.poster = p;
      break;
    }
  }

  if (series) {
    void addEp(dynamic e, int fallbackSeason) {
      if (e is! Map) return;
      final ei = e['info'] is Map ? e['info'] as Map : <dynamic, dynamic>{};
      final season = int.tryParse(_s(e['season'])) ?? fallbackSeason;
      final ep = EpisodeInfo(
        id: _s(e['id']),
        season: season,
        number: int.tryParse(_s(e['episode_num'])) ?? 0,
        title: _s(e['title']),
        ext: _s(e['container_extension']),
        plot: _s(ei['plot']),
        duration: _s(ei['duration']),
        image: _http(ei['movie_image']),
      );
      if (ep.id.isEmpty) return;
      d.seasons.putIfAbsent(season, () => []).add(ep);
    }

    final eps = j['episodes'];
    if (eps is Map) {
      eps.forEach((k, v) {
        final sn = int.tryParse('$k') ?? 1;
        if (v is List) {
          for (final e in v) {
            addEp(e, sn);
          }
        }
      });
    } else if (eps is List) {
      for (final e in eps) {
        if (e is List) {
          for (final x in e) {
            addEp(x, 1);
          }
        } else {
          addEp(e, 1);
        }
      }
    }
    for (final list in d.seasons.values) {
      list.sort((a, b) => a.number.compareTo(b.number));
    }
  }
  return d;
}
