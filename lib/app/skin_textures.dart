import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'skins.dart';

/// Textures, laid over a skin's colors, one per area (see TextureArea): a built-in tile
/// (assets/textures: white and black specks that lighten and darken whatever color is under
/// them) or your own picture, with its own strength, size and tint. Nothing is ever drawn over
/// the video.
class SkinTextures {
  static const labels = {
    'grain': 'Grain',
    'carbon': 'Carbon fiber',
    'metal': 'Brushed metal',
    'paper': 'Paper',
  };

  static String? _dir; // <app support>/skins: your own pictures

  /// At startup: where your pictures live, then a tidy-up of ones no skin uses.
  static Future<void> init() async {
    try {
      _dir = '${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}skins';
    } catch (e) {
      debugPrint('[skins] no folder for pictures: $e');
    }
    Skins.onRemoved = tidy;
    tidy();
  }

  static String? pathOf(String file) => _dir == null || file.isEmpty ? null : '$_dir${Platform.pathSeparator}$file';

  static ImageProvider? provider(SkinTexture t) {
    if (t.isPicture) {
      final p = pathOf(t.pictureFile);
      return p == null ? null : FileImage(File(p));
    }
    return Skins.textures.contains(t.name) ? AssetImage('assets/textures/${t.name}.png') : null;
  }

  /// One area's texture as a decoration image, or null when it has none.
  static DecorationImage? image(Skin s, TextureArea a) {
    final t = s.textures[a];
    if (t == null) return null;
    final p = provider(t);
    if (p == null) return null;
    final photo = t.isPicture && t.fill;
    return DecorationImage(
      image: p,
      opacity: t.strength.clamp(0.0, 1.0),
      fit: photo ? BoxFit.cover : BoxFit.none,
      repeat: photo ? ImageRepeat.noRepeat : ImageRepeat.repeat,
      alignment: photo ? Alignment.center : Alignment.topLeft,
      scale: photo ? 1.0 : 1 / t.size.clamp(0.5, 3.0), // bigger size = fewer image pixels per point
      colorFilter: t.tint == null ? null : ColorFilter.mode(t.tint!, BlendMode.modulate),
      filterQuality: FilterQuality.medium,
      onError: (e, _) => debugPrint('[skins] texture did not load: $e'),
    );
  }

  static bool has(TextureArea a) => image(Skins.skin, a) != null;

  /// The window background's texture layer, or null when the skin has none.
  static Decoration? background() {
    final i = image(Skins.skin, TextureArea.background);
    return i == null ? null : BoxDecoration(image: i);
  }

  /// A panel (top bar, sidebar): its color with the panels' texture over it.
  static BoxDecoration panel(Color c) => BoxDecoration(color: c, image: image(Skins.skin, TextureArea.panels));

  /// Any area: its color, with the area's texture when [on] (a highlight only shows it while lit).
  static BoxDecoration decorate(TextureArea a, Color? c, {bool on = true, BorderRadius? radius, BoxBorder? border}) =>
      BoxDecoration(color: c, image: on ? image(Skins.skin, a) : null, borderRadius: radius, border: border);

  /// Wraps something (a search box) in its area's color and texture. Always the same widget,
  /// textured or not, so whatever is inside never loses its state when the skin changes.
  static Widget box(TextureArea a, Color c, {required BorderRadius radius, required Widget child}) =>
      DecoratedBox(decoration: decorate(a, c, radius: radius), child: child);

  // ---------- Your own pictures ----------

  static const maxBytes = 12 * 1024 * 1024;

  /// png, jpg, gif or webp, by the file's first bytes. Null if it isn't one of those.
  static String? kindOf(List<int> b) {
    if (b.length > 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return 'png';
    if (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return 'jpg';
    if (b.length > 6 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return 'gif';
    if (b.length > 12 && b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 && b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) {
      return 'webp';
    }
    return null;
  }

  /// Keeps a copy of a picture for a skin. Returns its file name.
  /// Throws a plain-language message if it can't be used.
  static Future<String> savePicture(String skinId, List<int> bytes) async {
    final kind = kindOf(bytes);
    if (kind == null) throw 'That picture isn\'t a PNG, JPEG, GIF or WebP.';
    if (bytes.length > maxBytes) throw 'That picture is over 12 MB. Pick a smaller one.';
    final dir = _dir;
    if (dir == null) throw 'Black Mango couldn\'t find a place to keep pictures.';
    await Directory(dir).create(recursive: true);
    final safeId = skinId.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '');
    final name = '${safeId}_${DateTime.now().millisecondsSinceEpoch}.$kind';
    await File('$dir${Platform.pathSeparator}$name').writeAsBytes(bytes, flush: true);
    return name;
  }

  static Future<List<int>?> readPicture(String file) async {
    final p = pathOf(file);
    if (p == null) return null;
    final f = File(p);
    return await f.exists() ? f.readAsBytes() : null;
  }

  /// Deletes pictures that no saved skin uses (from cancelled edits or deleted skins).
  /// Skips the one on screen, in case it's being edited right now.
  static Future<void> tidy() async {
    final dir = _dir;
    if (dir == null) return;
    try {
      final d = Directory(dir);
      if (!await d.exists()) return;
      final keep = {
        for (final s in [...Skins.mine, Skins.skin])
          for (final t in s.textures.values)
            if (t.isPicture) t.pictureFile,
      };
      await for (final e in d.list()) {
        final name = e.uri.pathSegments.isEmpty ? '' : e.uri.pathSegments.last;
        if (e is File && !keep.contains(name)) await e.delete();
      }
    } catch (e) {
      debugPrint('[skins] tidy: $e');
    }
  }
}
