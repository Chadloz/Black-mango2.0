import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../services.dart';
import '../playback/vod_failover.dart';
import '../storage/database.dart';
import 'account_picker.dart';
import 'filter_menu.dart';
import 'player_panel.dart';
import 'details_panel.dart';
import '../favorites/favorites_service.dart';
import '../../app/nav.dart';
import '../prefs.dart';

String _fmt(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');

const _letters = ['#', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z'];

String _letterOf(String name) {
  final t = name.trim();
  if (t.isEmpty) return '#';
  final c = t[0].toUpperCase();
  return RegExp(r'[A-Z]').hasMatch(c) ? c : '#';
}

/// Poster grid with search, filters, accounts, genre pills, and an A-Z bar.
/// While something of this kind plays, posters move left and the video takes the right,
/// same as Live TV. Used by Movies and Shows.
class PosterBrowser extends StatefulWidget {
  final String kind; // movie | series
  final String noun; // "movies" | "shows"
  final Set<String> playKinds; // which playing kinds show the player here
  const PosterBrowser({super.key, required this.kind, required this.noun, required this.playKinds});

  @override
  State<PosterBrowser> createState() => _PosterBrowserState();
}

class _PosterBrowserState extends State<PosterBrowser> {
  Set<String> _accounts = {};
  Set<String> _countries = {};
  Set<String> _languages = {};
  String? _genre;
  String _query = '';
  List<Item> _items = [];
  Set<String> _present = {};
  List<String> _genres = [];
  List<String> _countryOpts = [];
  List<String> _langOpts = [];
  Map<String, String> _acctNames = {};
  bool _loading = true;
  int _gen = 0;
  Timer? _debounce;
  StreamSubscription<List<Account>>? _acctSub;
  final _scroll = ScrollController();
  final _searchCtrl = TextEditingController(); // keeps search text across layout changes
  double? _guideW;
  Item? _selected; // title whose details are open
  Set<String> _favKeys = {};
  StreamSubscription<Set<String>>? _favSub;
  bool _showVideo = false; // right pane: video (true) or details (false)
  int _cols = 1;
  double _rowExtent = 300;
  // Stalker: when one Stalker account is picked, browse by the portal's own categories.
  Map<String, Account> _acctObjs = {};
  List<(String, String)> _cats = []; // (id, title) for _catAcct
  String? _catAcct;
  String? _catId;
  String? _vodStatus; // "Loading DE ✨ KINO (3/31)..." while a category or portal search runs
  Timer? _vodDebounce;

  @override
  void initState() {
    super.initState();
    final k = widget.kind;
    _accounts = Prefs.getSet('$k.accounts');
    _countries = Prefs.getSet('$k.countries');
    _languages = Prefs.getSet('$k.languages');
    _genre = Prefs.getStr('$k.genre');
    _guideW = Prefs.getDouble('$k.guideW');
    AppNav.select.addListener(_onSelectRequest);
    Services.playback.current.addListener(_onPlaying);
    _favSub = Services.favorites.watchKeys().listen((k) {
      if (mounted) setState(() => _favKeys = k);
    });
    Services.catalog.vodChanges.addListener(_onVodChanged);
    Services.catalog.vodStatus.addListener(_onVodStatus);
    _acctSub = Services.accounts.watchAll().listen((list) {
      if (!mounted) return;
      final names = {for (final a in list) a.id: a.name};
      setState(() {
        _acctNames = names;
        _acctObjs = {for (final a in list) a.id: a};
        _accounts = _accounts.where(names.containsKey).toSet();
      });
      _syncStalker();
      _reload();
    });
  }

  // ---------- Stalker categories ----------

  /// The one Stalker account picked in the account filter, if that's what's picked.
  String? get _stalkerAcct =>
      _accounts.length == 1 && _acctObjs[_accounts.first]?.type == 'stalker' ? _accounts.first : null;

  String? get _catTitle {
    for (final c in _cats) {
      if (c.$1 == _catId) return c.$2;
    }
    return null;
  }

  String _lastCatKey(String acctId) => 'acct.$acctId.stalkerlast.${widget.kind}';

  void _onVodChanged() {
    _vodDebounce?.cancel();
    _vodDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _reload();
    });
  }

  void _onVodStatus() {
    if (mounted) setState(() => _vodStatus = Services.catalog.vodStatus.value);
  }

  /// One Stalker account picked: get its categories and open the last one you used there.
  Future<void> _syncStalker() async {
    final acctId = _stalkerAcct;
    if (acctId == null) {
      if (_catAcct != null) {
        setState(() {
          _catAcct = null;
          _cats = [];
          _catId = null;
        });
        _reload();
      }
      return;
    }
    if (_catAcct == acctId && _cats.isNotEmpty) return;
    final a = _acctObjs[acctId];
    if (a == null) return;
    try {
      final cats = await Services.catalog.stalkerCategories(a, widget.kind);
      if (!mounted || _stalkerAcct != acctId) return;
      final last = Prefs.getStr(_lastCatKey(acctId));
      final pick = cats.any((x) => x.$1 == last) ? last : (cats.isEmpty ? null : cats.first.$1);
      setState(() {
        _catAcct = acctId;
        _cats = cats;
        _catId = pick;
      });
      _reload();
      if (pick != null) _openCat(pick);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not load the categories: $e')));
      }
    }
  }

  Future<void> _openCat(String id, {bool force = false}) async {
    final acctId = _stalkerAcct;
    final a = acctId == null ? null : _acctObjs[acctId];
    if (a == null) return;
    var title = '';
    for (final x in _cats) {
      if (x.$1 == id) title = x.$2;
    }
    Prefs.setStr(_lastCatKey(a.id), id);
    try {
      await Services.catalog.openStalkerCategory(a, widget.kind, id, title, force: force);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not load $title: $e')));
    }
  }

  Future<void> _pickCategory() async {
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => _CategoryPicker(cats: _cats, selected: _catId),
    );
    if (picked == null || !mounted) return;
    setState(() => _catId = picked);
    _reload();
    _openCat(picked);
  }

  /// Enter in the search box: also ask the Stalker portals in scope (they search everything,
  /// not just what's cached). Local results already filter as you type.
  Future<void> _portalSearch(String v) async {
    _debounce?.cancel();
    _query = v;
    final anyStalker = _acctObjs.values
        .any((a) => a.type == 'stalker' && (_accounts.isEmpty || _accounts.contains(a.id)));
    if (!anyStalker || v.trim().length < 2) {
      _reload();
      return;
    }
    await Services.catalog.searchStalker(widget.kind, v, _accounts);
    if (mounted) _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _vodDebounce?.cancel();
    Services.catalog.vodChanges.removeListener(_onVodChanged);
    Services.catalog.vodStatus.removeListener(_onVodStatus);
    _acctSub?.cancel();
    _favSub?.cancel();
    AppNav.select.removeListener(_onSelectRequest);
    Services.playback.current.removeListener(_onPlaying);
    _scroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Another screen (Favorites, Home) asked to open a title here.
  /// Something started playing here (Home, Continue Watching, restore, failover):
  /// open its page behind the video, so closing the video lands on the show's episodes.
  Future<void> _onPlaying() async {
    final cur = Services.playback.current.value;
    if (cur == null || !widget.playKinds.contains(cur.kind)) return;
    Item? page;
    if (cur.kind == 'episode') {
      final sel = _selected;
      page = await VodFailover.showPageFor(cur);
      if (page == null || (sel != null && sel.id == page.id)) return;
    } else {
      if (_selected?.id == cur.id) return;
      page = cur;
    }
    if (!mounted || Services.playback.current.value?.id != cur.id) return;
    setState(() {
      _selected = page;
      _showVideo = true;
    });
  }

  void _onSelectRequest() {
    final r = AppNav.select.value;
    if (r == null || r.kind != widget.kind) return;
    setState(() {
      _selected = r;
      _showVideo = false;
    });
    AppNav.select.value = null;
  }

  void _savePrefs() {
    final k = widget.kind;
    Prefs.setSet('$k.accounts', _accounts);
    Prefs.setSet('$k.countries', _countries);
    Prefs.setSet('$k.languages', _languages);
    Prefs.setStr('$k.genre', _genre);
    if (_guideW != null) Prefs.setDouble('$k.guideW', _guideW!);
  }

  Future<void> _reload() async {
    final gen = ++_gen;
    _savePrefs();
    setState(() => _loading = true);
    final cat = Services.catalog;
    final k = widget.kind;
    // Stalker account picked: show its open category. A search looks across all of its cached titles.
    final category = (_stalkerAcct != null && _query.trim().isEmpty) ? _catTitle : null;
    final countryOpts = await cat.countries(k, accountIds: _accounts, category: category);
    final langOpts = await cat.languages(k, accountIds: _accounts, category: category);
    final countries = _countries.where(countryOpts.contains).toSet();
    final languages = _languages.where(langOpts.contains).toSet();
    final genres = await cat.genres(k, accountIds: _accounts, countries: countries, languages: languages, category: category);
    final genre = (_genre != null && genres.contains(_genre)) ? _genre : null;
    final raw = await cat.items(k,
        accountIds: _accounts,
        genre: genre,
        countries: countries,
        languages: languages,
        query: _query,
        byName: true,
        category: category);
    // A Stalker title can sit in more than one category: show it once.
    final seen = <String>{};
    final items = raw.where((it) => seen.add(favKey(it))).toList();
    if (!mounted || gen != _gen) return;
    setState(() {
      _countryOpts = countryOpts;
      _langOpts = langOpts;
      _countries = countries;
      _languages = languages;
      _genres = genres;
      _genre = genre;
      _items = items;
      _present = {for (final it in items) _letterOf(it.name)};
      _loading = false;
    });
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _query = v;
      _reload();
    });
  }

  void _jump(String letter) {
    final i = _items.indexWhere((x) => _letterOf(x.name) == letter);
    if (i < 0 || !_scroll.hasClients) return;
    final off = (i ~/ _cols) * _rowExtent;
    _scroll.jumpTo(off.clamp(0.0, _scroll.position.maxScrollExtent).toDouble());
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => ValueListenableBuilder<Item?>(
        valueListenable: Services.playback.current,
        builder: (context, cur, _) {
          final playing = cur != null && widget.playKinds.contains(cur.kind);
          final sel = _selected;
          final hasPane = playing || sel != null;
          // Narrow space (small window, mini player): stack the toolbar so nothing overflows.
          // The Stalker category button needs a bit more room before the toolbar stacks.
          final browser = _browser(compact: hasPane || box.maxWidth < (_stalkerAcct != null ? 780 : 600), cur: cur);
          if (!hasPane) return browser;
          final Widget panel;
          if (playing && (_showVideo || sel == null)) {
            panel = PlayerPanel(item: cur, accountName: _acctNames[cur.accountId] ?? '');
          } else {
            panel = DetailsPanel(
              key: ValueKey(sel!.id),
              item: sel,
              accountName: _acctNames.length > 1 ? (_acctNames[sel.accountId] ?? '') : '',
              onClose: () => setState(() => _selected = null),
              onPlayed: () => setState(() => _showVideo = true),
              onBackToVideo: playing ? () => setState(() => _showVideo = true) : null,
            );
          }
          if (box.maxWidth >= 800) {
            final maxGuide = max(300.0, box.maxWidth - 320);
            final listW = (_guideW ?? (box.maxWidth * 0.32).clamp(320.0, 460.0).toDouble()).clamp(300.0, maxGuide).toDouble();
            return Row(
              children: [
                SizedBox(width: listW, child: browser),
                _dragHandle(box.maxWidth, listW),
                Expanded(child: panel),
              ],
            );
          }
          final playerH = min(box.maxWidth * 9 / 16 + 40, box.maxHeight * 0.55);
          return Column(
            children: [
              SizedBox(height: playerH, child: panel),
              const Divider(height: 1),
              Expanded(child: browser),
            ],
          );
        },
      ),
    );
  }

  Widget _dragHandle(double total, double current) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (d) => setState(
          () => _guideW = (current + d.delta.dx).clamp(300.0, max(300.0, total - 320)).toDouble(),
        ),
        onHorizontalDragEnd: (_) => _savePrefs(),
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

  Widget _browser({required bool compact, required Item? cur}) {
    final search = TextField(
      controller: _searchCtrl,
      onChanged: _onSearch,
      onSubmitted: _portalSearch,
      decoration: InputDecoration(
        hintText: 'Search ${widget.noun}...',
        suffixIcon: _searchCtrl.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  _searchCtrl.clear();
                  _onSearch('');
                },
              ),
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
        _syncStalker();
        _reload();
      },
    );
    final catTitle = _catTitle;
    // Stalker category button + reload. In the stacked (narrow) toolbar it stretches to fit;
    // in the wide toolbar it caps its own width, since that row hands it unbounded width.
    Widget? categoriesFor({required bool stretch}) {
      if (_stalkerAcct == null) return null;
      final button = OutlinedButton.icon(
        onPressed: _cats.isEmpty ? null : _pickCategory,
        icon: const Icon(Icons.folder_open_outlined, size: 18),
        label: stretch
            ? Text(catTitle ?? 'Category', overflow: TextOverflow.ellipsis, maxLines: 1)
            : ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(catTitle ?? 'Category', overflow: TextOverflow.ellipsis, maxLines: 1),
              ),
      );
      final reload = IconButton(
        tooltip: 'Reload this category from the portal',
        onPressed: _catId == null ? null : () => _openCat(_catId!, force: true),
        icon: const Icon(Icons.refresh, size: 20),
      );
      return stretch
          ? Row(children: [Expanded(child: button), reload])
          : Row(mainAxisSize: MainAxisSize.min, children: [button, reload]);
    }

    final categoriesNarrow = categoriesFor(stretch: true);
    final categoriesWide = categoriesFor(stretch: false);
    final toolbar = compact
        ? Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Column(
              children: [
                search,
                const SizedBox(height: 8),
                Row(children: [Expanded(child: filters), const SizedBox(width: 8), Expanded(child: accounts)]),
                if (categoriesNarrow != null) ...[const SizedBox(height: 8), categoriesNarrow],
              ],
            ),
          )
        : Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(child: search),
                const SizedBox(width: 12),
                filters,
                const SizedBox(width: 8),
                if (categoriesWide != null) ...[categoriesWide, const SizedBox(width: 8)],
                accounts,
              ],
            ),
          );
    return Column(
      children: [
        toolbar,
        SizedBox(
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
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _vodStatus ?? (_loading ? 'Loading...' : '${_fmt(_items.length)} ${widget.noun}'),
              style: const TextStyle(fontFamily: BMFonts.mono, fontSize: 11, color: BMColors.dim),
            ),
          ),
        ),
        Expanded(
          child: _items.isEmpty
              ? Center(
                  child: _loading
                      ? const CircularProgressIndicator()
                      : Text(
                          _vodStatus != null
                              ? 'Loading...'
                              : _stalkerAcct != null
                                  ? 'Nothing here yet. Pick a category, or press Enter to search the portal.'
                                  : 'No ${widget.noun} match. Load an account in Accounts, or loosen the filters.',
                          style: const TextStyle(color: BMColors.dim)),
                )
              : Row(
                  children: [
                    Expanded(child: _grid(cur)),
                    _azBar(),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _grid(Item? cur) {
    return LayoutBuilder(builder: (context, g) {
      const pad = 16.0, spacing = 14.0, target = 170.0, aspect = 0.54;
      final usable = max(1.0, g.maxWidth - pad * 2);
      final count = max(1, ((usable + spacing) / (target + spacing)).floor());
      final tileW = (usable - spacing * (count - 1)) / count;
      _cols = count;
      _rowExtent = tileW / aspect + spacing;
      return GridView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(pad, 0, pad, 16),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: count,
          mainAxisSpacing: spacing,
          crossAxisSpacing: spacing,
          childAspectRatio: aspect,
        ),
        itemCount: _items.length,
        itemBuilder: (context, i) {
          final it = _items[i];
          return _PosterTile(
            item: it,
            active: cur?.id == it.id || _selected?.id == it.id,
            accountName: _acctNames.length > 1 ? (_acctNames[it.accountId] ?? '') : '',
            onTap: () => setState(() {
              _selected = it;
              _showVideo = false;
            }),
            isFav: _favKeys.contains(favKey(it)),
            onFav: () => Services.favorites.toggle(it),
          );
        },
      );
    });
  }

  Widget _azBar() {
    return SizedBox(
      width: 26,
      child: Column(
        children: [
          for (final l in _letters)
            Expanded(
              child: InkWell(
                onTap: _present.contains(l) ? () => _jump(l) : null,
                child: Center(
                  child: Text(
                    l,
                    style: TextStyle(
                      fontFamily: BMFonts.mono,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _present.contains(l) ? BMColors.mango : BMColors.border,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A searchable list of a Stalker portal's categories.
class _CategoryPicker extends StatefulWidget {
  final List<(String, String)> cats;
  final String? selected;
  const _CategoryPicker({required this.cats, required this.selected});

  @override
  State<_CategoryPicker> createState() => _CategoryPickerState();
}

class _CategoryPickerState extends State<_CategoryPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final list = q.isEmpty ? widget.cats : widget.cats.where((c) => c.$2.toLowerCase().contains(q)).toList();
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _q = v),
                onSubmitted: (_) {
                  if (list.isNotEmpty) Navigator.pop(context, list.first.$1);
                },
                decoration: InputDecoration(
                  hintText: 'Find a category...',
                  prefixIcon: const Icon(Icons.search, color: BMColors.dim),
                  isDense: true,
                  filled: true,
                  fillColor: BMColors.surfaceHigh,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: list.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No category matches.', style: TextStyle(color: BMColors.dim)),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: list.length,
                        itemBuilder: (context, i) {
                          final c = list[i];
                          final on = c.$1 == widget.selected;
                          return ListTile(
                            dense: true,
                            title: Text(c.$2,
                                style: TextStyle(color: on ? BMColors.mango : BMColors.text, fontWeight: on ? FontWeight.w600 : null)),
                            trailing: on ? const Icon(Icons.check, size: 18, color: BMColors.mango) : null,
                            onTap: () => Navigator.pop(context, c.$1),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
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

class _PosterTile extends StatelessWidget {
  final Item item;
  final bool active;
  final String accountName;
  final VoidCallback onTap;
  final bool isFav;
  final VoidCallback onFav;
  const _PosterTile({required this.item, required this.active, required this.accountName, required this.onTap, required this.isFav, required this.onFav});

  @override
  Widget build(BuildContext context) {
    final fallback = Center(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Text(item.name,
            textAlign: TextAlign.center, maxLines: 4, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: BMColors.dim, fontSize: 13)),
      ),
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: active ? BMColors.mango : Colors.transparent, width: 2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: double.infinity,
                  color: BMColors.surfaceHigh,
                  child: item.logo.startsWith('http')
                      ? Image.network(item.logo, fit: BoxFit.cover, cacheWidth: 340, errorBuilder: (_, _, _) => fallback)
                      : fallback,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(item.name,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: active ? BMColors.mango : BMColors.text)),
              ),
              InkWell(
                onTap: onFav,
                child: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(isFav ? Icons.star : Icons.star_border, size: 18, color: isFav ? BMColors.mango : BMColors.dim),
                ),
              ),
            ],
          ),
          if (accountName.isNotEmpty)
            Text(accountName,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: BMColors.mango, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
