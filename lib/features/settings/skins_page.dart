import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/theme.dart';
import '../../app/skins.dart';
import '../../app/skin_tools.dart';
import '../../app/skin_textures.dart';
import '../../app/skin_drops.dart';
import 'skin_editor.dart';

/// Settings > Skins: its own page, so Settings stays short.
class SkinsPage extends StatefulWidget {
  final VoidCallback onBack;
  const SkinsPage({super.key, required this.onBack});

  @override
  State<SkinsPage> createState() => _SkinsPageState();
}

class _SkinsPageState extends State<SkinsPage> {
  Skin? _editing; // the skin open in the editor, if any
  bool _isNew = false;

  @override
  void initState() {
    super.initState();
    Skins.mineChanged.addListener(_refresh);
    Skins.current.addListener(_refresh);
  }

  @override
  void dispose() {
    Skins.mineChanged.removeListener(_refresh);
    Skins.current.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _snack(String t) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  /// A new skin of yours, starting as a copy of [base]. Opens the editor.
  void _make(Skin base) {
    final name = base.custom ? '${base.name} copy' : (base.id == 'black_mango' ? 'My skin' : 'My ${base.name}');
    setState(() {
      _isNew = true;
      _editing = base.copyWith(id: Skins.newId(), name: Skins.uniqueName(name), group: 'My skins', custom: true);
    });
  }

  void _edit(Skin s) => setState(() {
        _isNew = false;
        _editing = s;
      });

  /// A pasted or imported skin: added to My skins and switched to.
  Future<void> _add(Skin s) async {
    final named = s.copyWith(name: Skins.uniqueName(s.name));
    await Skins.save(named);
    await Skins.pick(named);
    _snack('Added "${named.name}" to My skins.');
  }

  Future<void> _duplicate(Skin s) async {
    final copy = s.copyWith(id: Skins.newId(), name: Skins.uniqueName('${s.name} copy'), group: 'My skins', custom: true);
    await Skins.save(copy);
    _snack('Made "${copy.name}".');
  }

  Future<void> _pasteCode() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final s = SkinCode.find(data?.text ?? '');
    if (s == null) {
      _snack('No skin code on the clipboard. Skin codes start with ${SkinCode.prefix}');
      return;
    }
    await _add(s);
  }

  Future<void> _importFile() async {
    try {
      final s = await SkinFile.pick();
      if (s != null) await _add(s);
    } catch (e) {
      _snack('$e');
    }
  }

  /// Giveaways: paste the code Chad handed out to collect the pack.
  Future<void> _redeem() async {
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Redeem a code'),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(hintText: 'Giveaway code', border: OutlineInputBorder()),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Redeem')),
        ],
      ),
    );
    ctrl.dispose();
    if (code == null) return;
    final problem = await SkinDrops.redeem(code);
    if (problem != null) _snack(problem);
  }

  Future<void> _copyCode(Skin s) async {
    await Clipboard.setData(ClipboardData(text: SkinCode.encode(s)));
    _snack(s.hasPicture
        ? 'Skin code for "${s.name}" copied, without your picture (too big for a code). Save it as a file to include the picture.'
        : 'Skin code for "${s.name}" copied. Paste it anywhere to share it.');
  }

  Future<void> _exportFile(Skin s) async {
    try {
      final f = await SkinFile.export(s);
      if (f != null) _snack('Saved $f');
    } catch (e) {
      _snack('Couldn\'t save the skin file: $e');
    }
  }

  Future<void> _delete(Skin s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${s.name}"?'),
        content: Text(Skins.skin.id == s.id
            ? 'You\'re using this skin, so Black Mango goes back to its own look.'
            : 'This can\'t be undone, unless you saved it as a file or skin code.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await Skins.remove(s.id);
    _snack('Deleted "${s.name}".');
  }

  Widget _menu(Skin s) => PopupMenuButton<String>(
        tooltip: 'More',
        icon: Icon(Icons.more_horiz, color: s.dim, size: 20),
        padding: EdgeInsets.zero,
        onSelected: (v) {
          switch (v) {
            case 'edit':
              _edit(s);
            case 'copy':
              if (s.custom) {
                _duplicate(s);
              } else {
                _make(s);
              }
            case 'code':
              _copyCode(s);
            case 'file':
              _exportFile(s);
            case 'delete':
              _delete(s);
          }
        },
        itemBuilder: (_) => [
          if (s.custom) const PopupMenuItem(value: 'edit', child: Text('Edit')),
          PopupMenuItem(
            value: 'copy',
            child: Text(s.custom
                ? 'Duplicate'
                : s.exclusive.isNotEmpty
                    ? 'Make a copy to edit (colors only)'
                    : 'Make a copy to edit'),
          ),
          // Collected holiday skins stay yours: no codes or files for them.
          if (s.exclusive.isEmpty) const PopupMenuItem(value: 'code', child: Text('Copy skin code')),
          if (s.exclusive.isEmpty) const PopupMenuItem(value: 'file', child: Text('Save as a file')),
          if (s.custom) const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      );

  /// Debug builds only (flutter run): try a holiday drop and its reveal without waiting for its dates.
  Widget _debugDrops() => Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Test drops (debug builds only):', style: TextStyle(color: BMColors.dim, fontSize: 12)),
            for (final p in Skins.packs.values)
              OutlinedButton(onPressed: () => SkinDrops.test(p), child: Text('Drop ${p.name}')),
            TextButton(onPressed: Skins.forgetCollected, child: const Text('Forget collected drops')),
          ],
        ),
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 28, bottom: 10),
        child: Text(t, style: TextStyle(fontFamily: BMFonts.mono, fontSize: 11, letterSpacing: 1.5, color: BMColors.dim)),
      );

  Widget _cards(List<Skin> skins) => Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [for (final s in skins) SkinCard(skin: s, onTap: () => Skins.pick(s), menu: _menu(s))],
      );

  @override
  Widget build(BuildContext context) {
    final editing = _editing;
    if (editing != null) {
      return SkinEditor(
        key: ValueKey(editing.id),
        start: editing,
        isNew: _isNew,
        onDone: () => setState(() => _editing = null),
      );
    }
    final current = Skins.skin;
    final groups = <String>[];
    for (final s in Skins.builtIn) {
      if (!groups.contains(s.group)) groups.add(s.group);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 24, 32),
      children: [
        Row(
          children: [
            IconButton(
              onPressed: widget.onBack,
              tooltip: 'Back to Settings',
              icon: Icon(Icons.arrow_back, color: BMColors.text),
            ),
            const SizedBox(width: 4),
            Text('Skins', style: BMFonts.titleStyle(24)),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 8, top: 4),
          child: Text(
            'Changes the colors of the whole app. Pick one, or make your own.',
            style: TextStyle(color: BMColors.dim, fontSize: 13),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 8, top: 18),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              PopupMenuButton<String>(
                tooltip: 'Pick a starting point',
                onSelected: (v) => _make(v == 'current' ? current : Skins.builtIn.first),
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'current', child: Text('Start from my current skin (${current.name})')),
                  const PopupMenuItem(value: 'bm', child: Text('Start from Black Mango')),
                ],
                child: IgnorePointer(
                  child: FilledButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.brush_outlined, size: 18),
                    label: const Text('Make your own'),
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _pasteCode,
                icon: const Icon(Icons.content_paste, size: 18),
                label: const Text('Paste skin code'),
              ),
              OutlinedButton.icon(
                onPressed: _importFile,
                icon: const Icon(Icons.file_open_outlined, size: 18),
                label: const Text('Import skin file'),
              ),
              OutlinedButton.icon(
                onPressed: _redeem,
                icon: const Icon(Icons.redeem, size: 18),
                label: const Text('Redeem a code'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final g in groups) ...[
                _label(g.toUpperCase()),
                _cards([for (final s in Skins.builtIn) if (s.group == g) s]),
              ],
              _label('MY SKINS'),
              if (Skins.mine.isEmpty && Skins.collected.isEmpty)
                Text(
                  'Skins you make, paste or import show up here, and holiday skins you collect.',
                  style: TextStyle(color: BMColors.dim, fontSize: 13),
                )
              else
                _cards([...Skins.collected, ...Skins.mine]),
              if (kDebugMode) _debugDrops(),
            ],
          ),
        ),
      ],
    );
  }
}

/// One skin, drawn in its own colors, so the card is the preview.
class SkinCard extends StatelessWidget {
  final Skin skin;
  final VoidCallback onTap;
  final Widget? menu;
  const SkinCard({super.key, required this.skin, required this.onTap, this.menu});

  @override
  Widget build(BuildContext context) {
    final on = Skins.skin.id == skin.id;
    Widget dot(Color c) => Container(
          width: 14,
          height: 14,
          margin: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: skin.border)),
        );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 200,
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 12),
        decoration: BoxDecoration(
          color: skin.background,
          image: SkinTextures.image(skin, TextureArea.background),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: on ? skin.accent : skin.border, width: on ? 2 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Image.asset(skin.logo, height: 28),
                const SizedBox(width: 8),
                if (on) Icon(Icons.check_circle, color: skin.accent, size: 18),
                const Spacer(),
                if (menu != null) SizedBox(width: 32, height: 32, child: menu),
              ],
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(skin.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontFamily: skin.titleFont ?? BMFonts.ui,
                      fontSize: skin.titleFont != null ? 13 : 15,
                      fontWeight: skin.titleFont != null ? FontWeight.w400 : FontWeight.w700,
                      color: skin.text)),
            ),
            if (skin.exclusive.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Icon(Icons.star_rounded, size: 14, color: skin.accent),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(skin.exclusive,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: skin.accent)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Row(children: [
              dot(skin.surface),
              dot(skin.surfaceHigh),
              dot(skin.accent),
              dot(skin.text),
              dot(skin.dim),
            ]),
          ],
        ),
      ),
    );
  }
}
