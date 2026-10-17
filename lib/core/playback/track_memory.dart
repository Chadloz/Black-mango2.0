import 'dart:convert';
import 'dart:io';
import '../prefs.dart';
import '../storage/database.dart';
import 'vod_failover.dart';

/// Per-show audio and subtitle choices.
///
/// Settings is the everyday default. Changing tracks while watching is remembered
/// for that whole show (every episode, any account), for that movie, or for that
/// live channel. The Track menu can always change anything on the fly.
class TrackMemory {
  static final _epRe = RegExp(r'^(.*?)\s{3}S\d+ E\d+');

  static String? _key(Item? i) {
    if (i == null) return null;
    if (i.kind == 'episode') {
      final show = _epRe.firstMatch(i.name)?.group(1) ?? i.name;
      final k = VodFailover.parse(show);
      return k.title.isEmpty ? null : 'tracks.s.${k.title}';
    }
    if (i.kind == 'movie') {
      final k = VodFailover.parse(i.name);
      return k.title.isEmpty ? null : 'tracks.m.${k.title}.${k.year ?? ''}';
    }
    if (i.kind == 'live') return 'tracks.l.${i.name.toLowerCase().trim()}';
    return null;
  }

  static Map<String, dynamic> load(Item? i) {
    final k = _key(i);
    if (k == null) return const {};
    try {
      final v = jsonDecode(Prefs.getStr(k) ?? '{}');
      return v is Map<String, dynamic> ? v : const {};
    } catch (_) {
      return const {};
    }
  }

  static void save(Item? i, {String? audio, String? sub, bool? subsOn}) {
    final k = _key(i);
    if (k == null) return;
    final m = Map<String, dynamic>.from(load(i));
    if (audio != null && audio.isNotEmpty) m['a'] = audio;
    if (sub != null && sub.isNotEmpty) m['s'] = sub;
    if (subsOn != null) m['on'] = subsOn;
    Prefs.setStr(k, jsonEncode(m));
  }

  /// Your Mac's language, e.g. "en" from "en_US".
  static String macLang() {
    final l = Platform.localeName.split(RegExp(r'[_\-.]')).first.toLowerCase();
    return l.isEmpty ? 'en' : l;
  }

  static const _alias = {
    'en': 'eng', 'ja': 'jpn', 'es': 'spa', 'fr': 'fre,fra', 'de': 'ger,deu', 'it': 'ita', 'pt': 'por',
    'ru': 'rus', 'ar': 'ara', 'zh': 'chi,zho', 'ko': 'kor', 'hi': 'hin', 'tr': 'tur', 'nl': 'dut,nld',
    'pl': 'pol', 'sv': 'swe', 'el': 'gre,ell', 'he': 'heb', 'vi': 'vie', 'th': 'tha', 'id': 'ind',
  };

  /// Files label languages either way ("ja" or "jpn"), so ask the player for both.
  static String expand(String codes) {
    final out = <String>[];
    for (final c in codes.split(',').map((s) => s.trim().toLowerCase()).where((s) => s.isNotEmpty)) {
      out.add(c);
      final three = _alias[c];
      if (three != null) out.addAll(three.split(','));
      _alias.forEach((two, threes) {
        if (threes.split(',').contains(c)) out.add(two);
      });
    }
    return out.toSet().join(',');
  }
}
