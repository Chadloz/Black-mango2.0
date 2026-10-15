import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../app/theme.dart';
import '../../core/services.dart';
import '../../core/storage/database.dart';
import '../../core/widgets/account_picker.dart';
import '../../core/widgets/filter_menu.dart';

String _fmt(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');

class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  Set<String> _accounts = {}; // empty = all accounts
  Set<String> _countries = {};
  Set<String> _languages = {};
  String? _genre;
  String _query = '';
  List<Item> _items = [];
  List<String> _genres = [];
  List<String> _countryOpts = [];
  List<String> _langOpts = [];
  Map<String, String> _acctNames = {};
  bool _loading = true;
  int _gen = 0;
  Timer? _debounce;
  StreamSubscription<List<Account>>? _acctSub;
  final _scroll = ScrollController();
  double? _guideW; // guide width while playing, set by dragging the divider

  @override
  void initState() {
    super.initState();
    Services.playback.current.addListener(_onCurrent);
    // Refresh whenever accounts change (added, renamed, deleted, or reloaded).
    _acctSub = Services.accounts.watchAll().listen((list) {
      if (!mounted) return;
      final names = {for (final a in list) a.id: a.name};
      setState(() {
        _acctNames = names;
        _accounts = _accounts.where(names.containsKey).toSet();
      });
      _reload();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _acctSub?.cancel();
    Services.playback.current.removeListener(_onCurrent);
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final gen = ++_gen;
    setState(() => _loading = true);
    final cat = Services.catalog;
    final countryOpts = await cat.countries('live', accountIds: _accounts);
    final langOpts = await cat.languages('live', accountIds: _accounts);
    final countries = _countries.where(countryOpts.contains).toSet();
    final languages = _languages.where(langOpts.contains).toSet();
    final genres = await cat.genres('live', accountIds: _accounts, countries: countries, languages: languages);
    final genre = (_genre != null && genres.contains(_genre)) ? _genre : null;
    final items = await cat.items('live',
        accountIds: _accounts, genre: genre, countries: countries, languages: languages, query: _query);
    if (!mounted || gen != _gen) return;
    setState(() {
      _countryOpts = countryOpts;
      _langOpts = langOpts;
      _countries = countries;
      _languages = languages;
      _genres = genres;
      _genre = genre;
      _items = items;
      _loading = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealCurrent());
  }

  void _onCurrent() => WidgetsBinding.instance.addPostFrameCallback((_) => _revealCurrent());

  /// Keeps the playing channel visible in the list. Does nothing if it already is.
  void _revealCurrent() {
    final cur = Services.playback.current.value;
    if (cur == null || !_scroll.hasClients) return;
    final i = _items.indexWhere((x) => x.id == cur.id);
    if (i < 0) return;
    const rowH = 60.0;
    final pos = i * rowH;
    final view = _scroll.position.viewportDimension;
    final off = _scroll.offset;
    if (pos >= off && pos + rowH <= off + view) return;
    final target = (pos - view / 2 + rowH / 2).clamp(0.0, _scroll.position.maxScrollExtent).toDouble();
    _scroll.jumpTo(target);
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _query = v;
      _reload();
    });
  }

  Future<void> _play(Item item) async {
    try {
      await Services.playback.play(item);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not play: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => ValueListenableBuilder<Item?>(
        valueListenable: Services.playback.current,
        builder: (context, cur, _) {
          final countLine = Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _loading ? 'Loading...' : '${_fmt(_items.length)} channels',
                style: const TextStyle(fontFamily: BMFonts.mono, fontSize: 11, color: BMColors.dim),
              ),
            ),
          );
          // Wide window: guide on the left, video fills the rest.
          if (box.maxWidth >= 800) {
            // Playing: slimmer guide so the video gets the room. Idle: the guide takes it all.
            final maxGuide = max(260.0, box.maxWidth - 320);
            final listW = cur == null
                ? box.maxWidth
                : (_guideW ?? (box.maxWidth * 0.3).clamp(280.0, 420.0).toDouble()).clamp(260.0, maxGuide).toDouble();
            return Row(
              children: [
                SizedBox(
                  width: listW,
                  child: Column(
                    children: [_toolbar(compact: cur != null), _pills(), countLine, Expanded(child: _list(cur))],
                  ),
                ),
                if (cur != null) _dragHandle(box.maxWidth, listW),
                if (cur != null) Expanded(child: _PlayerArea(item: cur, acctNames: _acctNames)),
              ],
            );
          }
          // Narrow window: video on top (slim bar when idle), guide underneath.
          final playerH = cur == null ? 120.0 : min(box.maxWidth * 9 / 16 + 40, box.maxHeight * 0.6);
          return Column(
            children: [
              SizedBox(height: playerH, child: _PlayerArea(item: cur, acctNames: _acctNames)),
              const Divider(height: 1),
              _toolbar(compact: false),
              _pills(),
              countLine,
              Expanded(child: _list(cur)),
            ],
          );
        },
      ),
    );
  }

  Widget _toolbar({required bool compact}) {
    final search = TextField(
      onChanged: _onSearch,
      decoration: InputDecoration(
        hintText: 'Search channels...',
        prefixIcon: const Icon(Icons.search, color: BMColors.dim),
        isDense: true,
        filled: true,
        fillColor: BMColors.surfaceHigh,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      ),
    );
    final filters = FilterMenu(
      countries: _countryOpts,
      languages: _langOpts,
      selCountries: _countries,
      selLanguages: _languages,
      onChanged: (c, l) {
        setState(() {
          _countries = c;
          _languages = l;
        });
        _reload();
      },
    );
    final accounts = AccountPicker(
      names: _acctNames,
      selected: _accounts,
      onChanged: (s) {
        setState(() => _accounts = s);
        _reload();
      },
    );
    if (compact) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          children: [
            search,
            const SizedBox(height: 8),
            Row(children: [Expanded(child: filters), const SizedBox(width: 8), Expanded(child: accounts)]),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Expanded(child: search),
          const SizedBox(width: 12),
          filters,
          const SizedBox(width: 8),
          accounts,
        ],
      ),
    );
  }

  /// The line between guide and video. Drag it like a spreadsheet column.
  Widget _dragHandle(double total, double current) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (d) => setState(
          () => _guideW = (current + d.delta.dx).clamp(260.0, max(260.0, total - 320)).toDouble(),
        ),
        child: Container(
          width: 9,
          alignment: Alignment.center,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(width: 1, color: BMColors.border),
              Container(
                width: 5,
                height: 44,
                decoration: BoxDecoration(color: BMColors.dim, borderRadius: BorderRadius.circular(3)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pills() {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _Pill(label: 'All', selected: _genre == null, onTap: () {
            setState(() => _genre = null);
            _reload();
          }),
          for (final g in _genres)
            _Pill(label: g, selected: _genre == g, onTap: () {
              setState(() => _genre = g);
              _reload();
            }),
        ],
      ),
    );
  }

  Widget _list(Item? cur) {
    if (_items.isEmpty) {
      return Center(
        child: _loading
            ? const CircularProgressIndicator()
            : const Text('No channels match. Load an account in Accounts, or loosen the filters.',
                style: TextStyle(color: BMColors.dim)),
      );
    }
    // Number column fits the biggest number in the list, plus a little gap.
    final numberWidth = _items.length.toString().length * 7.5 + 10;
    return ListView.builder(
      controller: _scroll,
      itemCount: _items.length,
      itemExtent: 60,
      itemBuilder: (context, i) {
        final it = _items[i];
        return _ChannelRow(
          index: i,
          item: it,
          accountName: _acctNames[it.accountId] ?? '',
          active: cur?.id == it.id,
          onTap: () => _play(it),
          numberWidth: numberWidth,
        );
      },
    );
  }
}

class _PlayerArea extends StatelessWidget {
  final Item? item;
  final Map<String, String> acctNames;
  const _PlayerArea({required this.item, required this.acctNames});

  @override
  Widget build(BuildContext context) {
    final cur = item;
    if (cur == null) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: const Text('Select a channel to begin', style: TextStyle(color: BMColors.dim, fontSize: 16)),
      );
    }
    return Container(
      color: Colors.black,
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Video(controller: Services.playback.controller),
                Positioned(
                  top: 12,
                  left: 12,
                  child: ValueListenableBuilder<String?>(
                    valueListenable: Services.playback.reconnecting,
                    builder: (context, msg, _) => msg == null
                        ? const SizedBox.shrink()
                        : Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
                            child: Text(msg, style: const TextStyle(color: BMColors.mango, fontWeight: FontWeight.w600)),
                          ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            height: 40,
            color: BMColors.surface,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: cur.name, style: const TextStyle(fontWeight: FontWeight.w700, color: BMColors.text)),
                TextSpan(text: '   ${acctNames[cur.accountId] ?? ''}', style: const TextStyle(color: BMColors.mango)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Pill({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => onTap(),
        selectedColor: const Color(0x33FF8C00),
        labelStyle: TextStyle(color: selected ? BMColors.mango : BMColors.text),
        side: BorderSide(color: selected ? BMColors.mango : BMColors.border),
      ),
    );
  }
}

class _ChannelRow extends StatelessWidget {
  final int index;
  final Item item;
  final String accountName;
  final bool active;
  final VoidCallback onTap;
  final double numberWidth;
  const _ChannelRow({required this.index, required this.item, required this.accountName, required this.active, required this.onTap, required this.numberWidth});

  @override
  Widget build(BuildContext context) {
    final sub = [item.genre, item.country, item.category].where((s) => s.isNotEmpty).join('  ·  ');
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: active ? const Color(0x22FF8C00) : null,
          border: const Border(bottom: BorderSide(color: BMColors.border, width: 0.5)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: numberWidth,
              child: Text('${index + 1}', style: const TextStyle(fontFamily: BMFonts.mono, fontSize: 12, color: BMColors.dim)),
            ),
            _Logo(url: item.logo, name: item.name),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: active ? BMColors.mango : BMColors.text),
                  ),
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(text: sub, style: const TextStyle(color: BMColors.dim)),
                      if (accountName.isNotEmpty)
                        TextSpan(text: '   $accountName', style: const TextStyle(color: BMColors.mango, fontWeight: FontWeight.w600)),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            if (active) const Icon(Icons.graphic_eq, color: BMColors.mango, size: 18),
          ],
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  final String url;
  final String name;
  const _Logo({required this.url, required this.name});

  @override
  Widget build(BuildContext context) {
    final t = name.trim();
    final initials = t.isEmpty ? '?' : t.substring(0, min(2, t.length)).toUpperCase();
    final fallback = Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: BMColors.surfaceHigh, borderRadius: BorderRadius.circular(8)),
      child: Text(initials, style: const TextStyle(fontFamily: BMFonts.mono, fontSize: 12, color: BMColors.dim)),
    );
    if (!url.startsWith('http')) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        width: 44,
        height: 44,
        fit: BoxFit.contain,
        cacheWidth: 88,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}
