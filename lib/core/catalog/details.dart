import 'dart:convert';
import '../storage/database.dart';

// Info for a movie or show, plus episodes for shows.

class EpisodeInfo {
  final String id;
  final int season;
  final int number;
  final String title;
  final String ext;
  final String plot;
  final String duration;
  final String image;
  final String? extra; // provider-specific play info (Stalker: the season's command and episode number)
  const EpisodeInfo({
    required this.id,
    required this.season,
    required this.number,
    required this.title,
    required this.ext,
    required this.plot,
    required this.duration,
    required this.image,
    this.extra,
  });
}

/// The playable item for one episode of [show]. Shared by the episode list, failover, and next episode.
Item episodeItemFor(Item show, EpisodeInfo ep, {String fallbackTitle = ''}) {
  final title = ep.title.isNotEmpty ? ep.title : fallbackTitle;
  final label = 'S${ep.season} E${ep.number}${title.isEmpty ? '' : '  $title'}';
  return Item(
    id: -(int.tryParse(ep.id) ?? ep.id.hashCode.abs()),
    accountId: show.accountId,
    kind: 'episode',
    name: '${show.name}   $label',
    nameLower: '',
    category: show.category,
    logo: ep.image.isNotEmpty ? ep.image : show.logo,
    streamId: ep.id,
    ext: ep.ext,
    url: '',
    position: 0,
    genre: show.genre,
    country: show.country,
    language: show.language,
    extra: ep.extra,
  );
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

/// Fills [d] from a Stalker title's saved info ([x] is its extra info) and, for shows,
/// its season rows (each lists its episode numbers; an episode plays as season command + number).
Details parseStalkerDetails(Map<String, dynamic> x, List<Map> seasonRows, Details d, {required bool series}) {
  d.plot = _s(x['plot']);
  d.cast = _s(x['cast']);
  d.director = _s(x['director']);
  d.genre = _s(x['genre']);
  final y = _s(x['year']);
  d.year = y.length >= 4 ? y.substring(0, 4) : y;
  final r = double.tryParse(_s(x['rating']));
  d.rating = (r == null || r == 0) ? '' : r.toStringAsFixed(1);
  final mins = int.tryParse(_s(x['minutes']));
  if (mins != null && mins >= 10) d.duration = '$mins min';
  if (series) {
    for (final s in seasonRows) {
      final sid = _s(s['id']);
      final cmd = _s(s['cmd']);
      if (sid.isEmpty || cmd.isEmpty) continue;
      // "8625:3" is season 3; otherwise take the number from the name ("Season 3").
      final sn = int.tryParse(sid.split(':').last) ??
          int.tryParse(RegExp(r'(\d+)').firstMatch(_s(s['name']))?.group(1) ?? '') ??
          1;
      final eps = s['series'] is List ? (s['series'] as List) : const [];
      for (final e in eps) {
        final n = int.tryParse('$e');
        if (n == null) continue;
        d.seasons.putIfAbsent(sn, () => []).add(EpisodeInfo(
              id: '$sid:$n',
              season: sn,
              number: n,
              title: '',
              ext: '',
              plot: '',
              duration: '',
              image: '',
              extra: jsonEncode({'cmd': cmd, 'series': '$n'}),
            ));
      }
    }
    for (final list in d.seasons.values) {
      list.sort((a, b) => a.number.compareTo(b.number));
    }
  }
  return d;
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
