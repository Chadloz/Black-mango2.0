import 'dart:convert';
import 'dart:io' show gzip;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import '../core/prefs.dart';

/// The colors a skin sets, in the order the skin editor lists them.
/// Simple mode edits the first three and works out the rest.
enum SkinSlot {
  background('Background', 'Behind everything'),
  surface('Panels', 'Top bar, sidebar and cards'),
  accent('Accent', 'Highlights, the selected item, progress bars'),
  surfaceHigh('Raised panels', 'Search boxes and menus'),
  border('Borders', 'Lines between things'),
  text('Text', 'Main text'),
  dim('Dim text', 'Secondary text and icons'),
  controls('Player buttons', 'Play, pause and the other buttons over the video');

  final String label;
  final String hint;
  const SkinSlot(this.label, this.hint);

  static const simple = [background, surface, accent];
}

/// Where a texture can go. Text, dim text, borders and player buttons are thin letters and
/// lines, so a texture wouldn't show on them.
enum TextureArea {
  background('Background', 'Behind everything'),
  panels('Panels', 'Top bar, sidebar, and the bar under the player'),
  cards('Cards', 'Account cards and the tiles behind posters and logos'),
  raised('Search boxes', 'The search boxes in Live TV, Movies and Shows'),
  accent('Accent highlights', 'The selected category and sidebar item, the playing channel, filled buttons');

  final String label;
  final String hint;
  const TextureArea(this.label, this.hint);
}

/// One area's texture: a built-in tile or your own picture, how strong, how big, and its tint.
class SkinTexture {
  final String name; // a built-in one (Skins.textures) or 'picture'
  final double strength; // 0..1
  final double size; // 0.5..3: a bigger (over 1) or finer (under 1) pattern
  final Color? tint; // null: the light and dark specks as they are
  final String pictureFile; // 'picture': its file name in the app's skins folder
  final bool fill; // 'picture': fill the area (a photo) or repeat it (a pattern)

  const SkinTexture({
    required this.name,
    this.strength = 0.4,
    this.size = 1,
    this.tint,
    this.pictureFile = '',
    this.fill = true,
  });

  bool get isPicture => name == 'picture';

  SkinTexture copyWith({String? name, double? strength, double? size, Color? tint, bool clearTint = false, String? pictureFile, bool? fill}) =>
      SkinTexture(
        name: name ?? this.name,
        strength: strength ?? this.strength,
        size: size ?? this.size,
        tint: clearTint ? null : (tint ?? this.tint),
        pictureFile: pictureFile ?? this.pictureFile,
        fill: fill ?? this.fill,
      );

  static double _r(double v) => double.parse(v.toStringAsFixed(2));

  /// [withFile]: your own saved skins only (a shared skin never names a file).
  Map<String, dynamic> toJson({bool withFile = false}) => {
        'name': name,
        'strength': _r(strength),
        'size': _r(size),
        if (tint != null) 'tint': hexOf(tint!),
        if (isPicture) 'fill': fill,
        if (withFile && pictureFile.isNotEmpty) 'pictureFile': pictureFile,
      };

  /// Null if it isn't a usable texture. A picture needs a [trusted] file name (your own saved
  /// skins, or a picture SkinFile has just saved), so a shared skin can't point at a path.
  static SkinTexture? fromJson(Object? m, {bool trusted = false}) {
    if (m is! Map) return null;
    final name = '${m['name'] ?? ''}';
    final file = trusted ? '${m['pictureFile'] ?? ''}' : '';
    if (name == 'picture') {
      if (!Skin._safeFile.hasMatch(file)) return null;
    } else if (!Skins.textures.contains(name)) {
      return null;
    }
    double val(Object? v, double d, double lo, double hi) => v is num ? v.toDouble().clamp(lo, hi) : d;
    final tint = m['tint'];
    return SkinTexture(
      name: name,
      strength: val(m['strength'], 0.4, 0, 1),
      size: val(m['size'], 1, 0.5, 3),
      tint: tint == null ? null : parseHex('$tint'),
      pictureFile: name == 'picture' ? file : '',
      fill: m['fill'] != false,
    );
  }
}

/// A skin fills Black Mango's color slots, and can add its own logo, title font and
/// decorations. Picked any time in Settings > Skins; the whole app follows.
class Skin {
  final String id;
  final String name;
  final String group; // shown above the cards: 'Classic', 'Halloween', 'My skins'
  final Color background; // behind everything
  final Color surface; // panels: top bar, sidebar, cards
  final Color surfaceHigh; // raised panels: search boxes, menus
  final Color border;
  final Color accent; // highlights, the selected item, progress bars (Black Mango's orange)
  final Color text;
  final Color dim; // secondary text and icons
  final Color controls; // player buttons over the video
  final bool halloween; // cobwebs, fog, bats, lit pumpkins, the Boo! ghost
  final String logo;
  final String? titleFont; // the wordmark and screen titles; null = the normal font
  final bool custom; // made in the skin editor or imported: listed under My skins
  final Map<TextureArea, SkinTexture> textures; // each area's texture, if it has one
  final String holiday; // a holiday drop's decorations: '' or 'thanksgiving' (Christmas next)
  final String exclusive; // a collected drop's label, like 'Thanksgiving 2026'; '' for everything else

  const Skin({
    required this.id,
    required this.name,
    required this.group,
    required this.background,
    required this.surface,
    required this.surfaceHigh,
    required this.border,
    required this.accent,
    required this.text,
    required this.dim,
    this.controls = const Color(0xFFFFFFFF),
    this.halloween = false,
    this.logo = Skins.normalLogo,
    this.titleFont,
    this.custom = false,
    this.textures = const {},
    this.holiday = '',
    this.exclusive = '',
  });

  Color color(SkinSlot s) => switch (s) {
        SkinSlot.background => background,
        SkinSlot.surface => surface,
        SkinSlot.surfaceHigh => surfaceHigh,
        SkinSlot.border => border,
        SkinSlot.accent => accent,
        SkinSlot.text => text,
        SkinSlot.dim => dim,
        SkinSlot.controls => controls,
      };

  Skin withColor(SkinSlot s, Color c) => copyWith(
        background: s == SkinSlot.background ? c : null,
        surface: s == SkinSlot.surface ? c : null,
        surfaceHigh: s == SkinSlot.surfaceHigh ? c : null,
        border: s == SkinSlot.border ? c : null,
        accent: s == SkinSlot.accent ? c : null,
        text: s == SkinSlot.text ? c : null,
        dim: s == SkinSlot.dim ? c : null,
        controls: s == SkinSlot.controls ? c : null,
      );

  bool get drippingFont => titleFont == Skins.drippingFont;
  bool get pumpkinLogo => logo == Skins.halloweenLogo;

  /// A changed copy. Copies are never exclusive: a drop's decorations, logo and title font
  /// stay with the drop (the Halloween extras carry over, since anyone can switch those on).
  Skin copyWith({
    String? id,
    String? name,
    String? group,
    Color? background,
    Color? surface,
    Color? surfaceHigh,
    Color? border,
    Color? accent,
    Color? text,
    Color? dim,
    Color? controls,
    bool? halloween,
    bool? drippingFont,
    bool? pumpkinLogo,
    bool? custom,
    Map<TextureArea, SkinTexture>? textures,
  }) =>
      Skin(
        id: id ?? this.id,
        name: name ?? this.name,
        group: group ?? this.group,
        background: background ?? this.background,
        surface: surface ?? this.surface,
        surfaceHigh: surfaceHigh ?? this.surfaceHigh,
        border: border ?? this.border,
        accent: accent ?? this.accent,
        text: text ?? this.text,
        dim: dim ?? this.dim,
        controls: controls ?? this.controls,
        halloween: halloween ?? this.halloween,
        logo: (pumpkinLogo ?? this.pumpkinLogo) ? Skins.halloweenLogo : Skins.normalLogo,
        titleFont: (drippingFont ?? this.drippingFont) ? Skins.drippingFont : null,
        custom: custom ?? this.custom,
        textures: textures ?? this.textures,
      );

  /// The same skin with one area's texture set, or removed (null).
  Skin withTexture(TextureArea a, SkinTexture? t) {
    final m = Map<TextureArea, SkinTexture>.of(textures);
    if (t == null) {
      m.remove(a);
    } else {
      m[a] = t;
    }
    return copyWith(textures: m);
  }

  bool get hasPicture => textures.values.any((t) => t.isPicture);

  /// What goes in a skin file or skin code: colors, switches and textures, never file paths.
  /// (A skin file adds your own pictures itself; see SkinFile. [withFiles]: your saved skins.)
  Map<String, dynamic> toJson({bool withFiles = false}) => {
        'name': name,
        'colors': {for (final s in SkinSlot.values) s.name: hexOf(color(s))},
        'decorations': halloween,
        'drippingFont': drippingFont,
        'pumpkinLogo': pumpkinLogo,
        if (textures.isNotEmpty)
          'textures': {for (final e in textures.entries) e.key.name: e.value.toJson(withFile: withFiles)},
      };

  static final _safeFile = RegExp(r'^[A-Za-z0-9_\-]+\.(png|jpg|gif|webp)$');

  /// A skin from a file or skin code. Missing colors come from Black Mango's own skin.
  /// Returns null if it isn't a skin at all. Only your own saved skins ([trusted]) may name
  /// a picture file; anything else needs its picture saved first (SkinFile does that).
  static Skin? fromJson(Object? raw, {required String id, bool trusted = false}) {
    if (raw is! Map) return null;
    final colors = raw['colors'];
    if (colors is! Map) return null;
    var s = Skins.builtIn.first.copyWith(
      id: id,
      name: _cleanName('${raw['name'] ?? ''}'),
      group: 'My skins',
      custom: true,
      halloween: raw['decorations'] == true,
      drippingFont: raw['drippingFont'] == true,
      pumpkinLogo: raw['pumpkinLogo'] == true,
    );
    var found = 0;
    for (final slot in SkinSlot.values) {
      final c = parseHex('${colors[slot.name] ?? ''}');
      if (c != null) {
        s = s.withColor(slot, c);
        found++;
      }
    }
    final tx = <TextureArea, SkinTexture>{};
    final areas = raw['textures'];
    if (areas is Map) {
      for (final a in TextureArea.values) {
        final t = SkinTexture.fromJson(areas[a.name], trusted: trusted);
        if (t != null) tx[a] = t;
      }
    } else if (raw['texture'] is Map) {
      // Test build 7 part 2 kept one texture for the background and panels.
      final old = Map<String, Object?>.from(raw['texture'] as Map)..['pictureFile'] = raw['pictureFile'];
      final t = SkinTexture.fromJson(old, trusted: trusted);
      if (t != null) {
        tx[TextureArea.background] = t;
        if (!t.isPicture || !t.fill) tx[TextureArea.panels] = t;
      }
    }
    if (tx.isNotEmpty) s = s.copyWith(textures: tx);
    return found == 0 ? null : s;
  }

  static String _cleanName(String n) {
    final t = n.replaceAll(RegExp(r'[\r\n\t]'), ' ').trim();
    if (t.isEmpty) return 'My skin';
    return t.length > 40 ? t.substring(0, 40).trim() : t;
  }
}

/// #RRGGBB for a color (no alpha).
String hexOf(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// #RRGGBB, RRGGBB, or #RGB. Null if it isn't a color.
Color? parseHex(String s) {
  var h = s.trim().replaceFirst('#', '').replaceFirst(RegExp(r'^0x', caseSensitive: false), '');
  if (h.length == 3) h = h.split('').map((x) => '$x$x').join();
  if (h.length == 8) h = h.substring(2); // AARRGGBB: alpha ignored
  if (h.length != 6 || !RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(h)) return null;
  return Color(0xFF000000 | int.parse(h, radix: 16));
}

class Skins {
  static const normalLogo = 'assets/brand/logo.png';
  static const halloweenLogo = 'assets/brand/logo_halloween.png'; // the jack-o'-lantern mango
  static const drippingFont = 'Nosifer'; // dripping titles
  static const textures = ['grain', 'carbon', 'metal', 'paper']; // assets/textures/<name>.png
  static const thanksgivingLogo = 'assets/brand/logo_thanksgiving.png'; // the mango turkey
  static const harvestFont = 'BerkshireSwash'; // Thanksgiving titles
  static const christmasLogo = 'assets/brand/logo_christmas.png'; // Santa hat and a candy cane
  static const christmasFont = 'MountainsOfChristmas'; // Christmas titles

  /// Named sets a pack file can use (their art and code are built into the app).
  static const packLogos = {
    'normal': normalLogo,
    'halloween': halloweenLogo,
    'thanksgiving': thanksgivingLogo,
    'christmas': christmasLogo,
  };
  static const packFonts = {'dripping': drippingFont, 'harvest': harvestFont, 'christmas': christmasFont};
  static const holidayDecorations = {'thanksgiving', 'christmas'}; // beyond 'halloween', which has its own switch

  /// Holiday packs this app knows: the ones bundled in assets/packs, plus any the drop feed
  /// carries. Keyed by pack id.
  static final packs = <String, SkinPack>{};

  /// At startup, before load(): the packs bundled with the app.
  static Future<void> loadBundledPacks() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      for (final path in manifest.listAssets()) {
        if (!path.startsWith('assets/packs/') || !path.endsWith('.json')) continue;
        final p = SkinPack.fromJson(jsonDecode(await rootBundle.loadString(path)));
        if (p != null) packs[p.id] = p;
      }
    } catch (e) {
      debugPrint('[skins] bundled packs not loaded: $e');
    }
  }

  static const builtIn = <Skin>[
    Skin(
      id: 'black_mango',
      name: 'Black Mango',
      group: 'Classic',
      background: Color(0xFF0B0B0B),
      surface: Color(0xFF151515),
      surfaceHigh: Color(0xFF1E1E1E),
      border: Color(0xFF2A2A2A),
      accent: Color(0xFFFF8C00),
      text: Color(0xFFEDEDED),
      dim: Color(0xFF8A8A8A),
    ),
    Skin(
      id: 'pumpkin_patch',
      name: 'Pumpkin Patch',
      group: 'Halloween',
      background: Color(0xFF0D0A0F),
      surface: Color(0xFF17121C),
      surfaceHigh: Color(0xFF211A28),
      border: Color(0xFF2E2438),
      accent: Color(0xFFFF7518),
      text: Color(0xFFF2E9E4),
      dim: Color(0xFF9A8AA6),
      halloween: true,
      logo: halloweenLogo,
      titleFont: drippingFont,
    ),
    Skin(
      id: 'witching_hour',
      name: 'Witching Hour',
      group: 'Halloween',
      background: Color(0xFF0B0814),
      surface: Color(0xFF151026),
      surfaceHigh: Color(0xFF1E1735),
      border: Color(0xFF2C2348),
      accent: Color(0xFFA970FF),
      text: Color(0xFFEDE7FF),
      dim: Color(0xFF8C84A8),
      halloween: true,
      logo: halloweenLogo,
      titleFont: drippingFont,
    ),
    Skin(
      id: 'blood_moon',
      name: 'Blood Moon',
      group: 'Halloween',
      background: Color(0xFF0A0505),
      surface: Color(0xFF160A0A),
      surfaceHigh: Color(0xFF211010),
      border: Color(0xFF331616),
      accent: Color(0xFFD7263D),
      text: Color(0xFFF5E6E6),
      dim: Color(0xFFA07E7E),
      halloween: true,
      logo: halloweenLogo,
      titleFont: drippingFont,
    ),
    Skin(
      id: 'graveyard_fog',
      name: 'Graveyard Fog',
      group: 'Halloween',
      background: Color(0xFF0B0F0E),
      surface: Color(0xFF141A19),
      surfaceHigh: Color(0xFF1C2422),
      border: Color(0xFF26322F),
      accent: Color(0xFF7CFF4F),
      text: Color(0xFFE6F0EC),
      dim: Color(0xFF7F918B),
      halloween: true,
      logo: halloweenLogo,
      titleFont: drippingFont,
    ),
  ];

  /// Skins you made or imported (Settings > Skins > My skins). Kept in Prefs, so backups carry them.
  static List<Skin> mine = [];

  /// Holiday packs you collected. They're yours for good, listed under My skins with a badge.
  static List<Skin> collected = [];

  static Set<String> get collectedPacks => Prefs.getSet('skins.collected');

  /// The packs you collected, as they were when you got them (pack id -> pack file).
  static Map<String, Object?> _packData() {
    try {
      final m = jsonDecode(Prefs.getStr('skins.packdata') ?? '{}');
      return m is Map ? Map<String, Object?>.from(m) : {};
    } catch (_) {
      return {};
    }
  }

  static void _loadCollected() {
    final data = _packData();
    collected = [
      for (final id in collectedPacks) ...?(SkinPack.fromJson(data[id]) ?? packs[id])?.skins,
    ];
  }

  /// Keeps a holiday pack for good, with its colors as they are now.
  static Future<void> collect(SkinPack p) async {
    final data = _packData()..[p.id] = p.raw;
    await Prefs.setStr('skins.packdata', jsonEncode(data));
    await Prefs.setSet('skins.collected', collectedPacks..add(p.id));
    _loadCollected();
    mineChanged.value++;
  }

  /// Debug builds only (Settings > Skins): forget collected packs, to test a drop again.
  static Future<void> forgetCollected() async {
    await Prefs.setSet('skins.collected', <String>{});
    await Prefs.setStr('skins.packdata', null);
    _loadCollected();
    if (byId(Prefs.getStr('skin')) == null) await pick(builtIn.first);
    mineChanged.value++;
  }

  /// Bumps when My skins changes, so the Skins page can refresh.
  static final mineChanged = ValueNotifier<int>(0);

  static List<Skin> get all => [...builtIn, ...collected, ...mine];

  /// The skin in use. The app rebuilds everything when it changes.
  static final current = ValueNotifier<Skin>(builtIn.first);
  static Skin get skin => current.value;

  static Skin? byId(String? id) {
    for (final s in all) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// At startup (after Prefs): your skins, then the skin you picked last time.
  static void load() {
    mine = _readMine();
    _loadCollected();
    current.value = byId(Prefs.getStr('skin')) ?? builtIn.first;
  }

  static Future<void> pick(Skin s) async {
    current.value = s;
    await Prefs.setStr('skin', s.id);
  }

  /// Shows a skin everywhere without saving it (the editor, while you pick colors).
  static void preview(Skin s) => current.value = s;

  /// Back to the skin you saved.
  static void endPreview() => current.value = byId(Prefs.getStr('skin')) ?? builtIn.first;

  /// Adds or updates one of your skins.
  static Future<void> save(Skin s) async {
    final i = mine.indexWhere((m) => m.id == s.id);
    mine = [...mine];
    if (i >= 0) {
      mine[i] = s;
    } else {
      mine.add(s);
    }
    await _writeMine();
  }

  static Future<void> remove(String id) async {
    mine = mine.where((m) => m.id != id).toList();
    await _writeMine();
    if (Prefs.getStr('skin') == id) await pick(builtIn.first);
    onRemoved?.call();
  }

  /// Set by SkinTextures: tidies away pictures no skin uses any more.
  static void Function()? onRemoved;

  static String newId() => 'mine_${DateTime.now().microsecondsSinceEpoch}';

  /// "Witching Hour" is taken: "Witching Hour 2", and so on.
  static String uniqueName(String want, {String? exceptId}) {
    final base = want.trim().isEmpty ? 'My skin' : want.trim();
    bool taken(String n) => all.any((s) => s.id != exceptId && s.name.toLowerCase() == n.toLowerCase());
    if (!taken(base)) return base;
    for (var i = 2;; i++) {
      if (!taken('$base $i')) return '$base $i';
    }
  }

  static List<Skin> _readMine() {
    final raw = Prefs.getStr('skins.mine');
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return [
        for (final m in list)
          if (m is Map && m['id'] is String) Skin.fromJson(m, id: m['id'] as String, trusted: true),
      ].whereType<Skin>().toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _writeMine() async {
    await Prefs.setStr('skins.mine', jsonEncode([
      for (final s in mine) {'id': s.id, ...s.toJson(withFiles: true)},
    ]));
    mineChanged.value++;
  }
}

/// A holiday pack file (assets/packs/<id>.json, or carried by the drop feed): a name, the
/// built-in decorations, logo and title font it uses, and its skins' colors. Everything named
/// must already be in the app; anything it doesn't know is left out (an older app shows the
/// colors without the newer decorations).
class SkinPack {
  final String id;
  final String name;
  final List<Skin> skins;
  final Map<String, Object?> raw; // the file itself, kept with your collected packs
  SkinPack(this.id, this.name, this.skins, this.raw);

  static final _safeId = RegExp(r'^[A-Za-z0-9_\-]{1,48}$');

  static SkinPack? fromJson(Object? j) {
    if (j is! Map || j['format'] != 'black-mango-pack') return null;
    final id = '${j['id'] ?? ''}';
    final name = '${j['name'] ?? ''}'.trim();
    final list = j['skins'];
    if (!_safeId.hasMatch(id) || name.isEmpty || list is! List) return null;
    final skins = <Skin>[];
    for (final m in list) {
      if (m is! Map) continue;
      final sid = '${m['id'] ?? ''}';
      if (!_safeId.hasMatch(sid) || sid.startsWith('mine_') || Skins.builtIn.any((b) => b.id == sid)) continue;
      final base = Skin.fromJson(m, id: sid);
      if (base == null) continue;
      String pick(String key) => '${m[key] ?? j[key] ?? ''}';
      final deco = pick('decorations');
      skins.add(Skin(
        id: sid,
        name: base.name,
        group: name,
        background: base.background,
        surface: base.surface,
        surfaceHigh: base.surfaceHigh,
        border: base.border,
        accent: base.accent,
        text: base.text,
        dim: base.dim,
        controls: base.controls,
        halloween: deco == 'halloween',
        holiday: Skins.holidayDecorations.contains(deco) ? deco : '',
        logo: Skins.packLogos[pick('logo')] ?? Skins.normalLogo,
        titleFont: Skins.packFonts[pick('font')],
        textures: base.textures,
        exclusive: name,
      ));
    }
    if (skins.isEmpty) return null;
    return SkinPack(id, name, skins, Map<String, Object?>.from(j));
  }
}

/// A skin as one line of text to paste anywhere (chat, text, email). Black Mango spots it in
/// Settings > Skins > Paste skin code, and in Add Account's quick paste box.
class SkinCode {
  static const prefix = 'BMSKIN1:';
  static final _re = RegExp(r'BMSKIN1:([A-Za-z0-9_\-=]+)');

  static String encode(Skin s) => prefix + base64Url.encode(gzip.encode(utf8.encode(jsonEncode(s.toJson()))));

  /// The first skin code in [text], as a new skin of yours (not saved yet). Null if there isn't one.
  static Skin? find(String text) {
    final m = _re.firstMatch(text);
    if (m == null) return null;
    try {
      final text = utf8.decode(gzip.decode(base64Url.decode(base64Url.normalize(m.group(1)!))));
      return Skin.fromJson(jsonDecode(text), id: Skins.newId());
    } catch (_) {
      return null;
    }
  }
}
