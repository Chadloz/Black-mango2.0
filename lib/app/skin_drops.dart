import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import '../core/prefs.dart';
import 'skins.dart';

/// One drop from the feed: a pack you can collect between two dates (your local days).
/// A giveaway drop has a code: only people who paste the code collect it.
class Drop {
  final String id;
  final String name;
  final String packId;
  final DateTime start; // first day, 00:00
  final DateTime end; // last day, 23:59:59
  final String codeHash; // giveaways: sha256 of the code (see tool/giveaway_code.py); '' for everyone
  final Object? packData; // the pack file, when the feed carries it (surprise packs need no app update)
  const Drop(this.id, this.name, this.packId, this.start, this.end, {this.codeHash = '', this.packData});

  bool get giveaway => codeHash.isNotEmpty;
  bool open(DateTime now) => !now.isBefore(start) && !now.isAfter(end);

  /// The pack: the one the feed carries, else the one bundled with the app.
  SkinPack? get pack => SkinPack.fromJson(packData) ?? Skins.packs[packId];

  static DateTime? _day(Object? v) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch('${v ?? ''}'.trim());
    if (m == null) return null;
    return DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }

  static Drop? fromJson(Object? m) {
    if (m is! Map) return null;
    final s = _day(m['start']);
    final e = _day(m['end']);
    final id = '${m['id'] ?? ''}';
    final packId = '${m['pack'] ?? id}';
    if (s == null || e == null || id.isEmpty) return null;
    final name = '${m['name'] ?? Skins.packs[packId]?.name ?? packId}';
    return Drop(id, name, packId, s, e.add(const Duration(hours: 23, minutes: 59, seconds: 59)),
        codeHash: '${m['code'] ?? ''}'.toLowerCase(), packData: m['packData']);
  }
}

/// Holiday, surprise and giveaway skin drops. The drop list is drops/drops.json in the repo; the
/// Skin drops workflow adds each drop's pack file (assets/packs) and publishes it next to the
/// update feed. When Black Mango is open during a drop's window, the pack is collected for good
/// and a reveal shows it. Giveaways are collected by pasting their code instead. The time comes
/// from the feed server's clock when there is one, so a computer's wrong date doesn't matter much.
/// Exclusive is soft (the app is open source); that's fine for a perk.
class SkinDrops {
  static const feed = 'https://raw.githubusercontent.com/Chadloz/Black-mango2.0/updates/drops.json';

  /// A drop just collected, waiting for the shell to show its reveal.
  static final pending = ValueNotifier<Drop?>(null);

  static Timer? _timer;

  /// After startup: a check shortly after the app opens, then every 6 hours.
  static void start() {
    Timer(const Duration(seconds: 6), check);
    _timer ??= Timer.periodic(const Duration(hours: 6), (_) => check());
  }

  /// The drop list and the time by the feed server's clock. Falls back to the last list and this
  /// computer's clock when offline ([fresh] false then).
  static Future<(List<Drop>, DateTime, bool)> _fetch() async {
    var now = DateTime.now();
    String? body;
    var fresh = false;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.parse(feed));
      final res = await req.close().timeout(const Duration(seconds: 15));
      final text = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 15));
      final date = res.headers.value(HttpHeaders.dateHeader);
      if (date != null) {
        try {
          now = HttpDate.parse(date).toLocal();
        } catch (_) {}
      }
      if (res.statusCode == 200) {
        body = text;
        fresh = true;
        await Prefs.setStr('drops.feed', text); // for the next time we're offline
      } else {
        debugPrint('[drops] feed answered ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('[drops] feed not reachable: $e');
    } finally {
      client.close(force: true);
    }
    body ??= Prefs.getStr('drops.feed');
    return (body == null ? <Drop>[] : parse(body), now, fresh);
  }

  static Future<void> check() async {
    final (drops, now, _) = await _fetch();
    for (final d in drops) {
      if (d.giveaway || !d.open(now) || Skins.collectedPacks.contains(d.packId)) continue;
      final p = d.pack;
      if (p == null) continue;
      await Skins.collect(p);
      debugPrint('[drops] collected ${p.id} (${d.id})');
      pending.value = d;
      return; // one reveal at a time; the next check picks up any other
    }
  }

  static List<Drop> parse(String body) {
    try {
      final j = jsonDecode(body);
      final list = j is Map ? j['drops'] : null;
      if (list is! List) return [];
      return [for (final m in list) Drop.fromJson(m)].whereType<Drop>().toList();
    } catch (_) {
      return [];
    }
  }

  /// Giveaway codes are compared as hashes: capitals, no spaces. tool/giveaway_code.py makes the same.
  static String hashOf(String code) =>
      sha256.convert(utf8.encode('black-mango-giveaway:${code.replaceAll(RegExp(r'\s+'), '').toUpperCase()}')).toString();

  /// Redeems a giveaway code. Returns null when it worked (the reveal shows), or what went wrong.
  static Future<String?> redeem(String code) async {
    if (code.trim().isEmpty) return 'Type or paste the code first.';
    final (drops, now, fresh) = await _fetch();
    final h = hashOf(code);
    Drop? d;
    for (final x in drops) {
      if (x.giveaway && x.codeHash == h) d = x;
    }
    if (d == null) {
      return fresh
          ? 'That code doesn\'t match a giveaway. Check the spelling and try again.'
          : 'Black Mango couldn\'t check the code. Check your connection and try again.';
    }
    if (!d.open(now)) return 'That code is for ${d.name}, and it isn\'t open right now.';
    if (Skins.collectedPacks.contains(d.packId)) return 'You already have ${d.name}. It\'s in My skins.';
    final p = d.pack;
    if (p == null) return 'This version of Black Mango can\'t open that pack yet. Update it and try again.';
    await Skins.collect(p);
    pending.value = d;
    return null;
  }

  /// Debug builds (Settings > Skins): collect a pack now and show its reveal, as a real drop would.
  static Future<void> test(SkinPack p) async {
    final now = DateTime.now();
    await Skins.collect(p);
    pending.value = Drop(p.id, p.name, p.id, now, now.add(const Duration(days: 25)));
  }
}
