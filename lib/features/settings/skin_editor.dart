import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/theme.dart';
import '../../app/skins.dart';
import '../../app/skin_tools.dart';
import '../../app/skin_textures.dart';
import '../../core/widgets/color_wheel.dart';
import '../../core/widgets/eyedropper.dart';

/// Make your own skin, or edit one of yours. The whole app shows the colors as you pick them;
/// nothing is kept until you save.
class SkinEditor extends StatefulWidget {
  final Skin start;
  final bool isNew;
  final VoidCallback onDone;
  const SkinEditor({super.key, required this.start, required this.isNew, required this.onDone});

  @override
  State<SkinEditor> createState() => _SkinEditorState();
}

class _SkinEditorState extends State<SkinEditor> {
  late Skin _draft = widget.start;
  SkinSlot _slot = SkinSlot.background;
  bool _advanced = false;
  bool _finished = false;
  late final _name = TextEditingController(text: widget.start.name);
  final _hex = TextEditingController();
  final _hexFocus = FocusNode();
  Timer? _previewTimer;
  SkinPicture? _picture; // a picture you picked: click colors out of it
  TextureArea _area = TextureArea.background; // the area whose texture you're setting
  bool _tint = false; // the color tools are picking that texture's tint, not a color slot
  late final Map<TextureArea, String> _pictures = {
    for (final e in widget.start.textures.entries)
      if (e.value.isPicture) e.key: e.value.pictureFile,
  }; // each area's last picture, so switching away and back keeps it

  /// True while the color tools pick the selected area's texture tint.
  bool get _tinting => _tint && _draft.textures[_area] != null;

  /// The color the wheel, hex box and swatches are working on.
  Color get _pickColor => _tinting ? (_draft.textures[_area]!.tint ?? Colors.white) : _draft.color(_slot);

  @override
  void initState() {
    super.initState();
    _hex.text = hexOf(_draft.color(_slot));
    WidgetsBinding.instance.addPostFrameCallback((_) => Skins.preview(_draft));
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    _name.dispose();
    _hex.dispose();
    _hexFocus.dispose();
    // Closed some other way (not Save or Cancel): go back to the saved skin.
    if (!_finished) WidgetsBinding.instance.addPostFrameCallback((_) => Skins.endPreview());
    super.dispose();
  }

  void _changed(Skin s) {
    setState(() => _draft = s);
    // The whole app follows, a few times a second at most while you drag.
    _previewTimer?.cancel();
    _previewTimer = Timer(const Duration(milliseconds: 60), () {
      if (!_finished) Skins.preview(_draft);
    });
  }

  void _setColor(Color c) {
    if (_tinting) {
      _changed(_draft.withTexture(_area, _draft.textures[_area]!.copyWith(tint: c)));
      if (!_hexFocus.hasFocus) _hex.text = hexOf(c);
      return;
    }
    var s = _draft.withColor(_slot, c);
    if (!_advanced && SkinSlot.simple.contains(_slot)) s = SkinMath.derive(s);
    _changed(s);
    if (!_hexFocus.hasFocus) _hex.text = hexOf(c);
  }

  void _pickSlot(SkinSlot s) {
    setState(() {
      _slot = s;
      _tint = false;
    });
    _hex.text = hexOf(_draft.color(s));
  }

  void _setMode(bool advanced) {
    setState(() {
      _advanced = advanced;
      if (!advanced && !SkinSlot.simple.contains(_slot)) _slot = SkinSlot.background;
    });
    _hex.text = hexOf(_draft.color(_slot));
  }

  void _snack(String t) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  // ---------- Eyedropper, pictures, textures ----------

  Future<void> _eyedrop() async {
    try {
      final c = await Eyedropper.pick(context);
      if (c != null && mounted) _setColor(c);
    } on MissingPluginException {
      _snack('The eyedropper needs a full restart: quit Black Mango and start it again.');
    } catch (e) {
      _snack('The eyedropper didn\'t work: $e');
    }
  }

  /// Skin from a picture: pick one, get a suggested skin, then click colors out of it.
  Future<void> _skinFromPicture() async {
    try {
      final pic = await SkinPicture.pick();
      if (pic == null || !mounted) return;
      setState(() => _picture = pic);
      _suggest();
    } catch (e) {
      _snack('$e');
    }
  }

  void _suggest() {
    final pic = _picture;
    if (pic == null) return;
    _changed(pic.suggest(_draft));
    _hex.text = hexOf(_pickColor);
    _snack('Colors suggested from your picture. Change anything you like, or Cancel to go back.');
  }

  /// Your own picture as the selected area's texture (fill the area, or repeat as a pattern).
  Future<void> _pictureTexture({SkinPicture? use}) async {
    try {
      final pic = use ?? await SkinPicture.pick();
      if (pic == null || !mounted) return;
      final file = await SkinTextures.savePicture(_draft.id, pic.bytes);
      if (!mounted) return;
      setState(() {
        _picture = pic;
        _pictures[_area] = file;
      });
      _usePicture(file);
    } catch (e) {
      _snack('$e');
    }
  }

  void _usePicture(String file) {
    final cur = _draft.textures[_area];
    _changed(_draft.withTexture(
      _area,
      SkinTexture(
        name: 'picture',
        pictureFile: file,
        strength: cur?.strength ?? 0.4,
        size: cur?.size ?? 1,
        tint: cur?.tint,
        fill: cur?.isPicture == true ? cur!.fill : _area == TextureArea.background,
      ),
    ));
  }

  void _setTexture(String key) {
    final cur = _draft.textures[_area];
    if (key.isEmpty) {
      setState(() => _tint = false);
      _changed(_draft.withTexture(_area, null));
      return;
    }
    if (key == 'picture') {
      final last = _pictures[_area];
      if (last == null) {
        _pictureTexture();
      } else {
        _usePicture(last);
      }
      return;
    }
    _changed(_draft.withTexture(_area, SkinTexture(name: key, strength: cur?.strength ?? 0.4, size: cur?.size ?? 1, tint: cur?.tint)));
  }

  void _updateTexture(SkinTexture Function(SkinTexture t) f) {
    final t = _draft.textures[_area];
    if (t != null) _changed(_draft.withTexture(_area, f(t)));
  }

  void _useEverywhere(SkinTexture t) {
    var s = _draft;
    for (final a in TextureArea.values) {
      s = s.withTexture(a, t);
    }
    _changed(s);
    _snack('Every area now has this texture. Pick an area to change just that one.');
  }

  void _cancel() {
    _finished = true;
    _previewTimer?.cancel();
    Skins.endPreview();
    widget.onDone();
  }

  Future<void> _save() async {
    var s = _draft.copyWith(name: Skins.uniqueName(_name.text, exceptId: _draft.id));
    final problems = SkinCheck.issues(s);
    var note = '';
    if (problems.isNotEmpty) {
      final choice = await _readabilityDialog(problems);
      if (choice == null || choice == 'cancel' || !mounted) return;
      if (choice == 'fix') {
        s = SkinCheck.autoFix(s);
        note = problems.length == 1 ? ' One color was adjusted so it\'s easy to read.' : ' ${problems.length} colors were adjusted so they\'re easy to read.';
      }
    }
    _finished = true;
    _previewTimer?.cancel();
    await Skins.save(s);
    await Skins.pick(s);
    _snack('Saved "${s.name}".$note');
    widget.onDone();
  }

  /// Hard-to-read colors: go back, keep them anyway, or let Black Mango fix just those.
  Future<String?> _readabilityDialog(List<SkinIssue> problems) => showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Some of this may be hard to read'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final p in problems)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 18, color: BMColors.mango),
                        const SizedBox(width: 8),
                        Expanded(child: Text(p.what)),
                      ],
                    ),
                  ),
                const SizedBox(height: 6),
                Text(
                  'Auto-fix changes only those colors, just enough to make them readable, and saves.',
                  style: TextStyle(color: BMColors.dim, fontSize: 13),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: const Text('Cancel')),
            OutlinedButton(onPressed: () => Navigator.pop(ctx, 'keep'), child: const Text('Keep my colors')),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'fix'), child: const Text('Auto-fix')),
          ],
        ),
      );

  // ---------- Layout ----------

  Widget _label(String t, {double top = 22}) => Padding(
        padding: EdgeInsets.only(top: top, bottom: 8),
        child: Text(t, style: TextStyle(fontFamily: BMFonts.mono, fontSize: 11, letterSpacing: 1.5, color: BMColors.dim)),
      );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 860;
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 24, 32),
        children: [
          _header(),
          const SizedBox(height: 8),
          if (wide)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: _left()),
                  const SizedBox(width: 32),
                  Expanded(flex: 6, child: _right()),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_left(), _right()]),
            ),
        ],
      );
    });
  }

  Widget _header() => Row(
        children: [
          IconButton(onPressed: _cancel, tooltip: 'Cancel', icon: Icon(Icons.arrow_back, color: BMColors.text)),
          const SizedBox(width: 4),
          Expanded(child: Text(widget.isNew ? 'Make your own' : 'Edit skin', style: BMFonts.titleStyle(24))),
          TextButton(onPressed: _cancel, child: const Text('Cancel')),
          const SizedBox(width: 8),
          FilledButton(onPressed: _save, child: const Text('Save skin')),
        ],
      );

  Widget _left() {
    final weak = SkinCheck.weak(_draft);
    final slots = _advanced ? SkinSlot.values : SkinSlot.simple;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('NAME', top: 8),
        TextField(
          controller: _name,
          maxLength: 40,
          decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), counterText: ''),
        ),
        _label('COLORS'),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Simple')),
            ButtonSegment(value: true, label: Text('Advanced')),
          ],
          selected: {_advanced},
          showSelectedIcon: false,
          onSelectionChanged: (v) => _setMode(v.first),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 6),
          child: Text(
            _advanced
                ? 'Every color, including the player buttons.'
                : 'Pick these three and Black Mango works out the rest.',
            style: TextStyle(color: BMColors.dim, fontSize: 12),
          ),
        ),
        for (final s in slots) _slotRow(s, weak.contains(s)),
        if (weak.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _advanced || weak.every(SkinSlot.simple.contains)
                  ? 'Colors marked with a warning may be hard to read. You can fix them when you save.'
                  : 'Some colors may be hard to read. Advanced shows which, or you can fix them when you save.',
              style: TextStyle(color: BMColors.dim, fontSize: 12),
            ),
          ),
        _textureSection(),
        _label('HALLOWEEN EXTRAS'),
        _switch('Decorations', 'Cobwebs, a little fog, bats, lit pumpkins, and the Boo! ghost', _draft.halloween,
            (v) => _changed(_draft.copyWith(halloween: v))),
        _switch('Dripping title font', 'For the wordmark and screen titles', _draft.drippingFont,
            (v) => _changed(_draft.copyWith(drippingFont: v))),
        _switch('Jack-o\'-lantern logo', 'A carved face on the mango', _draft.pumpkinLogo,
            (v) => _changed(_draft.copyWith(pumpkinLogo: v))),
      ],
    );
  }

  Widget _slotRow(SkinSlot s, bool weak) {
    final on = s == _slot && !_tinting;
    final c = _draft.color(s);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: () => _pickSlot(s),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: on ? BMColors.surfaceHigh : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: on ? BMColors.mango : BMColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: c,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: BMColors.border),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.label, style: TextStyle(color: BMColors.text, fontSize: 14)),
                    Text(s.hint, style: TextStyle(color: BMColors.dim, fontSize: 11)),
                  ],
                ),
              ),
              if (weak)
                Tooltip(
                  message: 'May be hard to read',
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(Icons.warning_amber_rounded, size: 18, color: BMColors.mango),
                  ),
                ),
              Text(hexOf(c), style: TextStyle(fontFamily: BMFonts.mono, fontSize: 12, color: BMColors.dim)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _switch(String title, String sub, bool value, ValueChanged<bool> on) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: BMColors.text, fontSize: 14)),
                  Text(sub, style: TextStyle(color: BMColors.dim, fontSize: 11)),
                ],
              ),
            ),
            Switch(value: value, onChanged: on),
          ],
        ),
      );

  Widget _right() {
    final c = _pickColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(_tinting ? 'TINT FOR ${_area.label.toUpperCase()}' : _slot.label.toUpperCase(), top: 8),
        Wrap(
          spacing: 24,
          runSpacing: 16,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ColorWheel(color: c, onChanged: _setColor, outline: BMColors.border, size: 220),
            SizedBox(
              width: 170,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: c,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: BMColors.border),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _hex,
                    focusNode: _hexFocus,
                    style: TextStyle(fontFamily: BMFonts.mono, fontSize: 14, color: BMColors.text),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      labelText: 'Hex code',
                      hintText: '#FF8C00',
                    ),
                    onChanged: (v) {
                      final parsed = parseHex(v);
                      if (parsed != null) _setColor(parsed);
                    },
                    onSubmitted: (_) => _hex.text = hexOf(_pickColor),
                  ),
                  const SizedBox(height: 6),
                  Text(_tinting ? 'Colors the light specks of the ${_area.label.toLowerCase()} texture' : _slot.hint,
                      style: TextStyle(color: BMColors.dim, fontSize: 11)),
                  if (Eyedropper.supported) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _eyedrop,
                      icon: const Icon(Icons.colorize, size: 18),
                      label: const Text('Pick from screen'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        _label('FROM A PICTURE'),
        _pictureSection(),
        _label('FROM THE BUILT-IN SKINS'),
        for (final s in Skins.builtIn) _swatchRow(s),
        _label('PREVIEW'),
        _Preview(skin: _draft),
      ],
    );
  }

  Widget _textureSection() {
    final weakAreas = SkinCheck.weakAreas(_draft);
    final t = _draft.textures[_area];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('TEXTURES'),
        Text(
          'Pick an area, then its texture. Each area can have its own, with its own strength, size and tint.',
          style: TextStyle(color: BMColors.dim, fontSize: 12),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final a in TextureArea.values) _areaChip(a, weakAreas.contains(a))],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 10),
          child: Text(_area.hint, style: TextStyle(color: BMColors.dim, fontSize: 11)),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _textureTile('', 'None'),
            for (final e in SkinTextures.labels.entries) _textureTile(e.key, e.value),
            _textureTile('picture', 'Your picture'),
          ],
        ),
        if (t != null) ...[
          const SizedBox(height: 6),
          _slider('Strength', t.strength, 0.05, 1, 19, (v) => _updateTexture((x) => x.copyWith(strength: v))),
          if (!(t.isPicture && t.fill))
            _slider('Size', t.size, 0.5, 3, 25, (v) => _updateTexture((x) => x.copyWith(size: v))),
          _tintRow(t),
          if (t.isPicture) ...[
            const SizedBox(height: 6),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Fill the area')),
                ButtonSegment(value: false, label: Text('Repeat as a pattern')),
              ],
              selected: {t.fill},
              showSelectedIcon: false,
              onSelectionChanged: (v) => _updateTexture((x) => x.copyWith(fill: v.first)),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                t.fill ? 'Like a photo: one copy, filling the area.' : 'Like a pattern: it repeats across the area.',
                style: TextStyle(color: BMColors.dim, fontSize: 12),
              ),
            ),
            TextButton.icon(
              onPressed: _pictureTexture,
              icon: const Icon(Icons.image_outlined, size: 18),
              label: const Text('Change picture'),
            ),
          ],
          TextButton.icon(
            onPressed: () => _useEverywhere(t),
            icon: const Icon(Icons.select_all, size: 18),
            label: const Text('Use this texture on every area'),
          ),
        ],
      ],
    );
  }

  Widget _areaChip(TextureArea a, bool weak) {
    final on = a == _area;
    final has = _draft.textures.containsKey(a);
    return InkWell(
      onTap: () {
        setState(() => _area = a);
        if (_tint) _hex.text = hexOf(_pickColor);
      },
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: on ? BMColors.surfaceHigh : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: on ? BMColors.mango : BMColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (has) ...[Icon(Icons.texture, size: 14, color: BMColors.mango), const SizedBox(width: 4)],
            Text(a.label, style: TextStyle(fontSize: 12, color: on ? BMColors.text : BMColors.dim)),
            if (weak) ...[const SizedBox(width: 4), Icon(Icons.warning_amber_rounded, size: 14, color: BMColors.mango)],
          ],
        ),
      ),
    );
  }

  Widget _slider(String title, double value, double min, double max, int steps, ValueChanged<double> on) => Row(
        children: [
          SizedBox(width: 64, child: Text(title, style: TextStyle(color: BMColors.text, fontSize: 14))),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: steps,
              label: '${(value * 100).round()}%',
              onChanged: on,
            ),
          ),
          SizedBox(
            width: 44,
            child: Text('${(value * 100).round()}%',
                textAlign: TextAlign.right, style: TextStyle(fontFamily: BMFonts.mono, fontSize: 12, color: BMColors.dim)),
          ),
        ],
      );

  Widget _tintRow(SkinTexture t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(width: 64, child: Text('Tint', style: TextStyle(color: BMColors.text, fontSize: 14))),
            Tooltip(
              message: 'Pick the tint with the color tools',
              child: InkWell(
                onTap: () {
                  setState(() => _tint = true);
                  _hex.text = hexOf(_pickColor);
                },
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: t.tint ?? Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _tinting ? BMColors.mango : BMColors.border, width: _tinting ? 2 : 1),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _tinting
                    ? 'Pick it with the wheel, hex code, swatches or eyedropper.'
                    : t.tint == null
                        ? 'None: light and dark specks. Click the square to tint them.'
                        : 'Click the square to change it.',
                style: TextStyle(color: BMColors.dim, fontSize: 12),
              ),
            ),
            if (t.tint != null)
              TextButton(
                onPressed: () {
                  setState(() => _tint = false);
                  _updateTexture((x) => x.copyWith(clearTint: true));
                },
                child: const Text('No tint'),
              ),
          ],
        ),
      );

  Widget _textureTile(String key, String label) {
    final cur = _draft.textures[_area];
    final on = key.isEmpty ? cur == null : cur?.name == key;
    DecorationImage? img;
    if (Skins.textures.contains(key)) {
      img = DecorationImage(
        image: AssetImage('assets/textures/$key.png'),
        repeat: ImageRepeat.repeat,
        fit: BoxFit.none,
        alignment: Alignment.topLeft,
        opacity: 0.6,
      );
    }
    final path = key == 'picture' ? SkinTextures.pathOf(_pictures[_area] ?? '') : null;
    if (path != null) img = DecorationImage(image: FileImage(File(path)), fit: BoxFit.cover);
    return InkWell(
      onTap: () => _setTexture(key),
      borderRadius: BorderRadius.circular(10),
      child: Column(
        children: [
          Container(
            width: 76,
            height: 52,
            decoration: BoxDecoration(
              color: _draft.surface,
              image: img,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: on ? BMColors.mango : BMColors.border, width: on ? 2 : 1),
            ),
            child: key == 'picture' && img == null
                ? Icon(Icons.add_photo_alternate_outlined, color: BMColors.dim, size: 22)
                : null,
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 11, color: on ? BMColors.text : BMColors.dim)),
        ],
      ),
    );
  }

  Widget _pictureSection() {
    final pic = _picture;
    if (pic == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pick a picture and Black Mango suggests a skin from its colors. Then click the picture to take any color from it.',
            style: TextStyle(color: BMColors.dim, fontSize: 12),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _skinFromPicture,
            icon: const Icon(Icons.image_search, size: 18),
            label: const Text('Choose a picture'),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460, maxHeight: 220),
            child: AspectRatio(
              aspectRatio: pic.width / pic.height,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LayoutBuilder(
                  builder: (context, box) => MouseRegion(
                    cursor: SystemMouseCursors.precise,
                    child: GestureDetector(
                      onTapDown: (d) => _setColor(pic.colorAt(d.localPosition.dx / box.maxWidth, d.localPosition.dy / box.maxHeight)),
                      child: Image.memory(pic.bytes, fit: BoxFit.fill, gaplessPlayback: true),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 6),
          child: Text(
            'Click the picture to use a color for ${_slot.label.toLowerCase()}. Its main colors:',
            style: TextStyle(color: BMColors.dim, fontSize: 12),
          ),
        ),
        Row(
          children: [
            for (final c in pic.palette)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Tooltip(
                  message: hexOf(c),
                  child: InkWell(
                    onTap: () => _setColor(c),
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: BMColors.border)),
                    ),
                  ),
                ),
              ),
          ],
        ),
        Wrap(
          spacing: 4,
          children: [
            TextButton(onPressed: _suggest, child: const Text('Suggest a skin again')),
            TextButton(
              onPressed: () => _pictureTexture(use: pic),
              child: Text('Use it as the ${_area.label.toLowerCase()} texture'),
            ),
            TextButton(onPressed: _skinFromPicture, child: const Text('Choose another picture')),
          ],
        ),
      ],
    );
  }

  Widget _swatchRow(Skin s) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            SizedBox(
              width: 120,
              child: Text(s.name, style: TextStyle(color: BMColors.dim, fontSize: 12), overflow: TextOverflow.ellipsis),
            ),
            for (final slot in SkinSlot.values)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Tooltip(
                  message: '${slot.label} ${hexOf(s.color(slot))}',
                  child: InkWell(
                    onTap: () => _setColor(s.color(slot)),
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: s.color(slot),
                        shape: BoxShape.circle,
                        border: Border.all(color: BMColors.border),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}

/// A small mock of the app in the colors being edited, including the player buttons,
/// which otherwise only show while something plays.
class _Preview extends StatelessWidget {
  final Skin skin;
  const _Preview({required this.skin});

  @override
  Widget build(BuildContext context) {
    final s = skin;
    Widget bar(double w, Color c) => Container(width: w, height: 8, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4)));
    Widget navItem(String t, bool on) => Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: on ? s.accent.withAlpha(0x33) : null,
            image: on ? SkinTextures.image(s, TextureArea.accent) : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(t, style: TextStyle(fontSize: 11, color: on ? s.accent : s.dim, fontWeight: on ? FontWeight.w600 : FontWeight.w400)),
        );
    Widget row(String name, String now, bool on) => Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.fromLTRB(6, 6, 8, 6),
          decoration: BoxDecoration(
            color: on ? s.surfaceHigh : s.surface,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 14,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(color: on ? s.accent : Colors.transparent, borderRadius: BorderRadius.circular(2)),
              ),
              Expanded(child: Text(name, style: TextStyle(fontSize: 12, color: s.text))),
              Text(now, style: TextStyle(fontSize: 10, color: s.dim)),
            ],
          ),
        );
    return Container(
      constraints: const BoxConstraints(maxWidth: 460),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: s.background,
        image: SkinTextures.image(s, TextureArea.background),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: s.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(color: s.surface, image: SkinTextures.image(s, TextureArea.panels)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Image.asset(s.logo, height: 20),
                const SizedBox(width: 8),
                Text.rich(TextSpan(children: [
                  TextSpan(text: 'Black ', style: TextStyle(color: s.text)),
                  TextSpan(text: 'Mango', style: TextStyle(color: s.accent)),
                ]), style: TextStyle(fontFamily: s.titleFont ?? BMFonts.ui, fontSize: s.titleFont != null ? 11 : 13, fontWeight: s.titleFont != null ? FontWeight.w400 : FontWeight.w700)),
                const Spacer(),
                Text('LIVE TV', style: TextStyle(fontFamily: BMFonts.mono, fontSize: 9, letterSpacing: 1.5, color: s.dim)),
              ],
            ),
          ),
          Container(height: 1, color: s.border),
          SizedBox(
            height: 150,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 96,
                  decoration: BoxDecoration(color: s.surface, image: SkinTextures.image(s, TextureArea.panels)),
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [navItem('Home', false), navItem('Live TV', true), navItem('Movies', false)],
                  ),
                ),
                Container(width: 1, color: s.border),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: s.surfaceHigh,
                            image: SkinTextures.image(s, TextureArea.raised),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: s.border),
                          ),
                          child: Text('Search channels', style: TextStyle(fontSize: 11, color: s.dim)),
                        ),
                        row('Channel 4 News', 'Now: Evening News', true),
                        row('Sports One', 'Now: Basketball', false),
                        const Spacer(),
                        Row(children: [Expanded(child: bar(double.infinity, s.accent)), const SizedBox(width: 6), bar(40, s.border)]),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            color: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                Icon(Icons.skip_previous, color: s.controls, size: 20),
                Icon(Icons.play_arrow, color: s.controls, size: 24),
                Icon(Icons.skip_next, color: s.controls, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(children: [Expanded(flex: 3, child: bar(double.infinity, s.accent)), Expanded(flex: 2, child: bar(double.infinity, Colors.white24))]),
                ),
                const SizedBox(width: 8),
                Icon(Icons.fullscreen, color: s.controls, size: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
