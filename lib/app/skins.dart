import 'package:flutter/material.dart';
import '../core/prefs.dart';

/// A skin fills Black Mango's 7 color slots, and can add its own logo, title font and
/// decorations. Picked any time in Settings > Appearance; the whole app follows.
class Skin {
  final String id;
  final String name;
  final String group; // shown above the cards: 'Classic', 'Halloween'
  final Color background; // behind everything
  final Color surface; // panels: top bar, sidebar, cards
  final Color surfaceHigh; // raised panels: search boxes, menus
  final Color border;
  final Color accent; // highlights, the selected item, progress bars (Black Mango's orange)
  final Color text;
  final Color dim; // secondary text and icons
  final bool halloween; // cobwebs, fog, bats, lit pumpkins, the Boo! ghost
  final String logo;
  final String? titleFont; // the wordmark and screen titles; null = the normal font

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
    this.halloween = false,
    this.logo = 'assets/brand/logo.png',
    this.titleFont,
  });
}

class Skins {
  static const _halloweenLogo = 'assets/brand/logo_halloween.png'; // the jack-o'-lantern mango
  static const _halloweenFont = 'Nosifer'; // dripping titles

  static const all = <Skin>[
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
      logo: _halloweenLogo,
      titleFont: _halloweenFont,
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
      logo: _halloweenLogo,
      titleFont: _halloweenFont,
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
      logo: _halloweenLogo,
      titleFont: _halloweenFont,
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
      logo: _halloweenLogo,
      titleFont: _halloweenFont,
    ),
  ];

  /// The skin in use. The app rebuilds everything when it changes.
  static final current = ValueNotifier<Skin>(all.first);
  static Skin get skin => current.value;

  /// At startup (after Prefs): the skin you picked last time.
  static void load() {
    final id = Prefs.getStr('skin');
    current.value = all.firstWhere((s) => s.id == id, orElse: () => all.first);
  }

  static Future<void> pick(Skin s) async {
    current.value = s;
    await Prefs.setStr('skin', s.id);
  }
}
