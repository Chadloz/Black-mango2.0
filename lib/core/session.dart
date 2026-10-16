import 'dart:convert';
import 'package:flutter/widgets.dart';
import '../app/nav.dart';
import 'prefs.dart';
import 'services.dart';
import 'storage/database.dart';

/// Remembers what was playing and which screen was open, and restores it on launch.
/// Live channels resume playing; movies and episodes come back paused at your spot.
/// Closing the video yourself (the X) clears it, so it isn't restored.
class Session {
  static void start() {
    Services.playback.current.addListener(_saveItem);
    AppNav.index.addListener(() => Prefs.setInt('session.screen', AppNav.index.value));
    WidgetsBinding.instance.addPostFrameCallback((_) => _restore());
  }

  static void _saveItem() {
    final i = Services.playback.current.value;
    if (i == null) {
      Prefs.setStr('session.item', null);
      return;
    }
    Prefs.setStr(
      'session.item',
      jsonEncode({
        'id': i.id,
        'accountId': i.accountId,
        'kind': i.kind,
        'name': i.name,
        'category': i.category,
        'logo': i.logo,
        'streamId': i.streamId,
        'ext': i.ext,
        'url': i.url,
        'genre': i.genre,
        'country': i.country,
        'language': i.language,
      }),
    );
  }

  static Future<void> _restore() async {
    final screen = Prefs.getInt('session.screen');
    if (screen != null) AppNav.index.value = screen;
    final raw = Prefs.getStr('session.item');
    if (raw == null) return;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      String s(String k) => (m[k] ?? '') as String;
      final item = Item(
        id: (m['id'] ?? 0) as int,
        accountId: s('accountId'),
        kind: s('kind'),
        name: s('name'),
        nameLower: s('name').toLowerCase(),
        category: s('category'),
        logo: s('logo'),
        streamId: s('streamId'),
        ext: s('ext'),
        url: s('url'),
        position: 0,
        genre: s('genre'),
        country: s('country'),
        language: s('language'),
      );
      if (await Services.accounts.get(item.accountId) == null) return;
      await Services.playback.play(item, autoplay: item.kind == 'live');
      debugPrint('[session] restored ${item.kind}: ${item.name}');
    } catch (e) {
      debugPrint('[session] could not restore: $e');
    }
  }
}
