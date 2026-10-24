import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'skins.dart';
import 'skin_textures.dart';

/// Simple mode: you pick background, panels and accent; this works out the rest.
class SkinMath {
  static bool isDark(Color c) => c.computeLuminance() < 0.4;

  /// Lighter on a dark skin, darker on a light one.
  static Color _shift(Color c, double by, bool dark) {
    final h = HSLColor.fromColor(c);
    return h.withLightness((h.lightness + (dark ? by : -by)).clamp(0.0, 1.0)).toColor();
  }

  static Skin derive(Skin s) {
    final dark = isDark(s.background);
    final text = Color.lerp(dark ? const Color(0xFFF2F2F2) : const Color(0xFF141414), s.accent, 0.06)!;
    return s.copyWith(
      surfaceHigh: _shift(s.surface, 0.04, dark),
      border: _shift(s.surface, 0.08, dark),
      text: text,
      dim: Color.lerp(text, s.background, 0.42)!,
    );
  }
}

/// One readability problem the check found: a color ([slot]) or a texture ([area]).
class SkinIssue {
  final SkinSlot? slot;
  final TextureArea? area;
  final String what;
  const SkinIssue(this.slot, this.what) : area = null;
  const SkinIssue.texture(TextureArea this.area, this.what) : slot = null;
}

/// Readability check before saving (contrast as in the WCAG guidelines:
/// 4.5 for text, 3 for secondary text, highlights and buttons).
class SkinCheck {
  static double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  static bool _textOk(Skin s, Color c) => contrast(c, s.background) >= 4.5 && contrast(c, s.surface) >= 4.5;
  static bool _dimOk(Skin s, Color c) => contrast(c, s.background) >= 3 && contrast(c, s.surface) >= 3;
  static bool _accentOk(Skin s, Color c) => contrast(c, s.background) >= 3;
  static bool _controlsOk(Color c) => contrast(c, Colors.black) >= 3; // video is mostly dark behind them

  static List<SkinIssue> issues(Skin s) => [
        if (!_textOk(s, s.text)) const SkinIssue(SkinSlot.text, 'Text on the background and panels'),
        if (!_dimOk(s, s.dim)) const SkinIssue(SkinSlot.dim, 'Dim text on the background and panels'),
        if (!_accentOk(s, s.accent)) const SkinIssue(SkinSlot.accent, 'Highlights on the background'),
        if (!_controlsOk(s.controls)) const SkinIssue(SkinSlot.controls, 'Player buttons over the video'),
        for (final a in TextureArea.values)
          if (!_textureOk(s, a)) SkinIssue.texture(a, 'Text on the ${a.label.toLowerCase()} texture'),
      ];

  /// The color an area's text sits on, and that text's color.
  static (Color, Color) _areaColors(Skin s, TextureArea a) => switch (a) {
        TextureArea.background => (s.background, s.text),
        TextureArea.panels => (s.surface, s.text),
        TextureArea.cards => (s.surface, s.text),
        TextureArea.raised => (s.surfaceHigh, s.text),
        TextureArea.accent => (Color.alphaBlend(s.accent.withAlpha(0x33), s.background), s.accent),
      };

  /// A texture lightens and darkens what's under it. Text must stay readable on both the lighter
  /// and the darker spots (roughly: specks cover about a third of the strength on average).
  static bool _textureOk(Skin s, TextureArea a, {double? strength}) {
    final t = s.textures[a];
    if (t == null) return true;
    final k = (strength ?? t.strength) * 0.33;
    final (under, ink) = _areaColors(s, a);
    final light = Color.alphaBlend((t.tint ?? Colors.white).withValues(alpha: k), under);
    final dark = Color.alphaBlend(Colors.black.withValues(alpha: k), under);
    final need = a == TextureArea.accent ? 3.0 : 4.5;
    return contrast(ink, light) >= need && contrast(ink, dark) >= need;
  }

  /// Slots with a problem, for the warning marks in the editor.
  static Set<SkinSlot> weak(Skin s) => {for (final i in issues(s)) if (i.slot != null) i.slot!};

  /// Texture areas with a problem.
  static Set<TextureArea> weakAreas(Skin s) => {for (final i in issues(s)) if (i.area != null) i.area!};

  /// Nudges only the colors that fail, as little as it takes, keeping their hue.
  static Skin autoFix(Skin s) {
    final lighter = SkinMath.isDark(s.background);
    var out = s;
    if (!_textOk(out, out.text)) out = out.copyWith(text: _push(out.text, lighter, (c) => _textOk(out, c)));
    if (!_dimOk(out, out.dim)) out = out.copyWith(dim: _push(out.dim, lighter, (c) => _dimOk(out, c)));
    if (!_accentOk(out, out.accent)) out = out.copyWith(accent: _push(out.accent, lighter, (c) => _accentOk(out, c)));
    if (!_controlsOk(out.controls)) out = out.copyWith(controls: _push(out.controls, true, _controlsOk));
    // Textures: turn the strength down until the text reads well (the texture and colors stay).
    for (final a in TextureArea.values) {
      final t = out.textures[a];
      if (t == null || _textureOk(out, a)) continue;
      var st = t.strength;
      while (st > 0.06 && !_textureOk(out, a, strength: st)) {
        st *= 0.85;
      }
      out = out.withTexture(a, t.copyWith(strength: math.max(0.05, st)));
    }
    return out;
  }

  static Color _push(Color c, bool lighter, bool Function(Color) ok) {
    var h = HSLColor.fromColor(c);
    for (var i = 0; i < 60 && !ok(h.toColor()); i++) {
      h = h.withLightness((h.lightness + (lighter ? 0.02 : -0.02)).clamp(0.0, 1.0));
      if (i > 30) h = h.withSaturation(h.saturation * 0.9); // very saturated colors may need to give a little
    }
    final c2 = h.toColor();
    if (ok(c2)) return c2;
    return lighter ? Colors.white : Colors.black;
  }
}

/// Skin files: one skin per .json file, to share or keep.
class SkinFile {
  static const format = 'black-mango-skin';
  static const _type = XTypeGroup(
    label: 'Black Mango skin',
    extensions: ['json'],
    uniformTypeIdentifiers: ['public.json'],
  );

  /// Saves where you pick. Returns the file name, or null if cancelled.
  static Future<String?> export(Skin s) async {
    final safe = s.name.replaceAll(RegExp(r'[^A-Za-z0-9 _\-]'), '').trim();
    final loc = await getSaveLocation(
      suggestedName: '${safe.isEmpty ? 'skin' : safe}.blackmango-skin.json',
      acceptedTypeGroups: const [_type],
    );
    if (loc == null) return null;
    var path = loc.path;
    if (!path.toLowerCase().endsWith('.json')) path = '$path.json';
    final data = <String, dynamic>{'format': format, 'version': 2, ...s.toJson()};
    // Your own pictures travel inside the file: each area names one of them ("picture": "p1").
    final pictures = <String, String>{};
    final keys = <String, String>{}; // picture file -> its key in this file
    final areas = data['textures'];
    if (areas is Map) {
      for (final a in TextureArea.values) {
        final t = s.textures[a];
        final entry = areas[a.name];
        if (t == null || !t.isPicture || entry is! Map) continue;
        var key = keys[t.pictureFile];
        if (key == null) {
          final bytes = await SkinTextures.readPicture(t.pictureFile);
          if (bytes == null) continue;
          key = 'p${keys.length + 1}';
          keys[t.pictureFile] = key;
          pictures[key] = base64.encode(bytes);
        }
        entry['picture'] = key;
      }
    }
    if (pictures.isNotEmpty) data['pictures'] = pictures;
    await File(path).writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    return path.split(Platform.pathSeparator).last;
  }

  /// Opens a skin file as a new skin of yours (not saved yet). Null if cancelled.
  /// Throws a plain-language message if the file isn't a skin.
  static Future<Skin?> pick() async {
    final f = await openFile(acceptedTypeGroups: const [_type]);
    if (f == null) return null;
    Object? data;
    try {
      data = jsonDecode(await f.readAsString());
    } catch (_) {
      throw 'That file isn\'t a Black Mango skin.';
    }
    if (data is! Map || data['format'] != format) {
      throw data is Map && data['accounts'] != null
          ? 'That\'s a Black Mango backup, not a skin. Import it in Settings > Backup.'
          : 'That file isn\'t a Black Mango skin.';
    }
    final parsed = Skin.fromJson(data, id: Skins.newId());
    if (parsed == null) throw 'That skin file has no colors in it.';
    var s = parsed;
    // Pictures: saved into the app's own folder first, then given to the areas that use them.
    final areas = data['textures'];
    final pictures = data['pictures'];
    if (areas is Map && pictures is Map) {
      final saved = <String, String>{}; // key in the file -> saved file name
      for (final a in TextureArea.values) {
        final entry = areas[a.name];
        if (entry is! Map || entry['name'] != 'picture') continue;
        final key = '${entry['picture'] ?? ''}';
        final b64 = pictures[key];
        if (b64 is! String) continue;
        try {
          final file = saved[key] ??= await SkinTextures.savePicture(s.id, base64.decode(b64));
          final t = SkinTexture.fromJson({...entry, 'pictureFile': file}, trusted: true);
          if (t != null) s = s.withTexture(a, t);
        } catch (e) {
          debugPrint('[skins] picture in skin file skipped: $e');
        }
      }
    }
    return s;
  }
}

/// A picture you picked in the skin editor: shown so you can click colors out of it, and read
/// for a suggested skin.
class SkinPicture {
  final Uint8List bytes; // the file as picked
  final Uint8List rgba; // decoded, at most 480 pixels wide, for clicking and the palette
  final int width;
  final int height;
  final List<Color> palette; // its main colors, most common first
  SkinPicture._(this.bytes, this.rgba, this.width, this.height, this.palette);

  static const _types = XTypeGroup(
    label: 'Pictures',
    extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp'],
    uniformTypeIdentifiers: ['public.png', 'public.jpeg', 'com.compuserve.gif', 'org.webmproject.webp'],
  );

  /// Opens a picture. Null if cancelled; throws a plain-language message if it can't be used.
  static Future<SkinPicture?> pick() async {
    final f = await openFile(acceptedTypeGroups: const [_types]);
    if (f == null) return null;
    final bytes = await f.readAsBytes();
    if (SkinTextures.kindOf(bytes) == null) throw 'That picture isn\'t a PNG, JPEG, GIF or WebP.';
    if (bytes.length > SkinTextures.maxBytes) throw 'That picture is over 12 MB. Pick a smaller one.';
    try {
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 480);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      final w = img.width, h = img.height;
      img.dispose();
      codec.dispose();
      if (data == null) throw 'x';
      final rgba = data.buffer.asUint8List();
      return SkinPicture._(bytes, rgba, w, h, _palette(rgba, w, h));
    } catch (_) {
      throw 'Black Mango couldn\'t read that picture.';
    }
  }

  /// The color at a spot, as fractions of the picture's width and height.
  Color colorAt(double fx, double fy) {
    final x = (fx * width).floor().clamp(0, width - 1);
    final y = (fy * height).floor().clamp(0, height - 1);
    final i = (y * width + x) * 4;
    return Color.fromARGB(255, rgba[i], rgba[i + 1], rgba[i + 2]);
  }

  static double _d2(List<double> a, List<double> b) {
    final r = a[0] - b[0], g = a[1] - b[1], bl = a[2] - b[2];
    return r * r + g * g + bl * bl;
  }

  /// Six main colors (k-means on a sample of the pixels), most common first.
  static List<Color> _palette(Uint8List rgba, int w, int h, {int k = 6}) {
    final pts = <List<double>>[];
    final step = math.max(1, (w * h / 6000).floor());
    for (var i = 0; i < w * h; i += step) {
      final o = i * 4;
      if (rgba[o + 3] < 128) continue;
      pts.add([rgba[o].toDouble(), rgba[o + 1].toDouble(), rgba[o + 2].toDouble()]);
    }
    if (pts.isEmpty) return [];
    // Start from spread-out colors, so small bright areas get a say.
    final cents = <List<double>>[List.of(pts[pts.length ~/ 2])];
    while (cents.length < k) {
      var best = -1.0;
      var bi = 0;
      for (var i = 0; i < pts.length; i++) {
        var d = double.infinity;
        for (final c in cents) {
          d = math.min(d, _d2(pts[i], c));
        }
        if (d > best) {
          best = d;
          bi = i;
        }
      }
      if (best <= 0) break;
      cents.add(List.of(pts[bi]));
    }
    final counts = List<int>.filled(cents.length, 0);
    for (var it = 0; it < 10; it++) {
      final sums = List.generate(cents.length, (_) => [0.0, 0.0, 0.0]);
      counts.fillRange(0, counts.length, 0);
      for (final p in pts) {
        var bj = 0;
        var bd = double.infinity;
        for (var j = 0; j < cents.length; j++) {
          final d = _d2(p, cents[j]);
          if (d < bd) {
            bd = d;
            bj = j;
          }
        }
        counts[bj]++;
        sums[bj][0] += p[0];
        sums[bj][1] += p[1];
        sums[bj][2] += p[2];
      }
      for (var j = 0; j < cents.length; j++) {
        if (counts[j] > 0) cents[j] = [sums[j][0] / counts[j], sums[j][1] / counts[j], sums[j][2] / counts[j]];
      }
    }
    final order = List.generate(cents.length, (j) => j)..sort((a, b) => counts[b].compareTo(counts[a]));
    return [
      for (final j in order)
        if (counts[j] > 0) Color.fromARGB(255, cents[j][0].round(), cents[j][1].round(), cents[j][2].round()),
    ];
  }

  /// A dark skin in the picture's colors: background and panels from its darkest common color,
  /// the accent from its most vivid one, the rest worked out, then made readable.
  Skin suggest(Skin base) {
    if (palette.isEmpty) return base;
    final n = palette.length;
    // Share of the picture, roughly: palette is most common first.
    double share(int i) => (n - i) / (n * (n + 1) / 2);
    final idx = List.generate(n, (i) => i);
    final byDark = [...idx]..sort((a, b) => palette[a].computeLuminance().compareTo(palette[b].computeLuminance()));
    final bgIdx = byDark.firstWhere((i) => share(i) >= 0.12, orElse: () => byDark.first);
    final h = HSLColor.fromColor(palette[bgIdx]);
    final light = math.min(h.lightness, 0.07);
    final bg = h.withLightness(light).withSaturation(math.min(h.saturation, 0.45)).toColor();
    final panels = h.withLightness(light + 0.035).withSaturation(math.min(h.saturation, 0.4)).toColor();
    double vivid(int i) {
      final v = HSVColor.fromColor(palette[i]);
      return v.saturation * v.value * math.sqrt(share(i) + 0.05);
    }
    final accIdx = [...idx]..sort((a, b) => vivid(b).compareTo(vivid(a)));
    final s = SkinMath.derive(base.copyWith(background: bg, surface: panels, accent: palette[accIdx.first]));
    return SkinCheck.autoFix(s);
  }
}
