import 'dart:convert';

class M3uEntry {
  final String name;
  final String group;
  final String logo;
  final String url;
  const M3uEntry(this.name, this.group, this.logo, this.url);
}

final _attrRe = RegExp(r'([\w-]+)="([^"]*)"');

// The display name is everything after the first comma that isn't inside quotes.
String _extinfName(String line) {
  var inQuote = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') inQuote = !inQuote;
    if (ch == ',' && !inQuote) return line.substring(i + 1).trim();
  }
  return '';
}

List<M3uEntry> parseM3u(String text) {
  final out = <M3uEntry>[];
  String? name;
  var group = '';
  var logo = '';
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#EXTINF')) {
      name = _extinfName(line);
      group = '';
      logo = '';
      for (final m in _attrRe.allMatches(line)) {
        final k = m.group(1)!.toLowerCase();
        if (k == 'group-title') group = m.group(2)!;
        if (k == 'tvg-logo') logo = m.group(2)!;
        if (k == 'tvg-name' && (name == null || name.isEmpty)) name = m.group(2)!;
      }
    } else if (line.startsWith('#EXTGRP:')) {
      if (group.isEmpty) group = line.substring(8).trim();
    } else if (!line.startsWith('#') && name != null) {
      out.add(M3uEntry(name.isEmpty ? 'Unknown' : name, group, logo, line));
      name = null;
    }
  }
  return out;
}

/// Xtream-style links reveal the type: /movie/... and /series/...
String kindFromUrl(String url) {
  final l = url.toLowerCase();
  if (l.contains('/movie/')) return 'movie';
  if (l.contains('/series/')) return 'series';
  return 'live';
}
