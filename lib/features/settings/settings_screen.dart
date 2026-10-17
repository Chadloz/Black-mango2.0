import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/theme.dart';
import '../../core/prefs.dart';
import '../../core/services.dart';
import '../../core/app_log.dart';
import '../../core/hotkeys.dart';
import '../../core/backup.dart';
import '../../core/playback/still_watching.dart';

const _langOptions = [
  ('', 'Automatic'),
  ('en,eng', 'English'),
  ('es,spa', 'Spanish'),
  ('fr,fre,fra', 'French'),
  ('pt,por', 'Portuguese'),
  ('de,ger,deu', 'German'),
  ('it,ita', 'Italian'),
  ('ar,ara', 'Arabic'),
  ('ru,rus', 'Russian'),
  ('ja,jpn', 'Japanese'),
  ('ko,kor', 'Korean'),
  ('zh,chi,zho', 'Chinese'),
  ('hi,hin', 'Hindi'),
];

const _shortcuts = [
  ('Space', 'Play / pause'),
  ('← →', 'Back / forward 10 seconds'),
  ('↑ ↓', 'Volume'),
  ('F', 'Fullscreen'),
  ('M', 'Mute'),
  ('Esc', 'Exit fullscreen'),
  ('Double-click', 'Fullscreen'),
];

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _msgCtrl = TextEditingController(text: Prefs.getStr('still.msg') ?? '');

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  String _langValue(String? stored) {
    if (stored == null || stored.isEmpty) return '';
    final first = stored.split(',').first.toLowerCase();
    for (final o in _langOptions) {
      if (o.$1.split(',').contains(first)) return o.$1;
    }
    return '';
  }

  Future<bool> _confirm(String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear')),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _export() async {
    try {
      final path = await Backup.export();
      if (path != null) _snack('Backup saved: ${path.split('/').last}');
    } catch (e) {
      _snack('Export failed: $e');
    }
  }

  Future<void> _import() async {
    Map<String, dynamic>? picked;
    try {
      picked = await Backup.pick();
    } catch (e) {
      _snack('$e');
      return;
    }
    if (picked == null || !mounted) return;
    final data = picked;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import this backup?'),
        content: Text('${Backup.describe(data)}.\n\nAccounts you already have are updated, and nothing else is removed. '
            'Imported accounts reload their channels in the background.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Import')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final accts = await Backup.apply(data);
      if (mounted) setState(() {});
      _snack('Imported. Reloading ${accts.length} account(s) in the background...');
      Backup.reloadAll(accts);
    } catch (e) {
      _snack('Import failed: $e');
    }
  }

  void _snack(String t) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  @override
  Widget build(BuildContext context) {
    final launch = Prefs.getStr('launch.mode') ?? 'resume';
    final subsOn = Prefs.getBool('subs.on');
    final subLang = _langValue(Prefs.getStr('subs.lang') ?? 'en');
    final audioLang = _langValue(Prefs.getStr('audio.lang'));
    final stillOn = !Prefs.getBool('still.disabled');
    final hours = Prefs.getInt('still.hours') ?? 3;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      children: [
        const Text('Settings', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: BMColors.text)),

        _section('PLAYBACK'),
        _row(
          'When Black Mango opens',
          DropdownButton<String>(
            value: launch,
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(value: 'resume', child: Text('Pick up where I left off')),
              DropdownMenuItem(value: 'paused', child: Text('Load where I left off, paused')),
              DropdownMenuItem(value: 'home', child: Text('Start on Home')),
            ],
            onChanged: (v) {
              Prefs.setStr('launch.mode', v);
              setState(() {});
            },
          ),
          sub: 'Pick up: live channels keep playing, movies and shows come back paused at your spot.',
        ),
        _row('Subtitles on by default', Switch(
          value: subsOn,
          onChanged: (v) async {
            await Services.playback.setSubsVisible(v);
            setState(() {});
          },
        )),
        _row('Subtitle language', _langDrop(subLang, (v) async {
          await Services.playback.setSubLang(v);
          setState(() {});
        })),
        _row(
          'Audio language',
          _langDrop(audioLang, (v) async {
            await Services.playback.setAudioLang(v);
            setState(() {});
          }),
          sub: 'Used when a movie or stream has more than one audio track.',
        ),

        _section('LIVE TV'),
        _row('Show channel numbers', Switch(
          value: !Prefs.getBool('live.hideNumbers'),
          onChanged: (v) {
            Prefs.setBool('live.hideNumbers', !v);
            setState(() {});
          },
        )),

        _section('LIVE TV AUDIO'),
        _row(
          'Dolby audio fix',
          Switch(
            value: !Prefs.getBool('relay.off'),
            onChanged: (v) {
              Prefs.setBool('relay.off', !v);
              setState(() {});
            },
          ),
          sub: 'Some channels label Dolby Digital Plus audio in a way the video engine skips, so they play silent. This relabels it on the fly. If live channels ever misbehave, turn it off. Applies to the next channel you open.',
        ),
        _section('MINI PLAYER'),
        _row(
          'Float when I switch to another app',
          Switch(
            value: !Prefs.getBool('mini.autoFloat.off'),
            onChanged: (v) {
              Prefs.setBool('mini.autoFloat.off', !v);
              setState(() {});
            },
          ),
          sub: 'While something plays, Black Mango shrinks into a small always-on-top window when you click over to another app.',
        ),
        _section('STILL WATCHING?'),
        _row(
          "Ask if I'm still watching",
          Switch(
            value: stillOn,
            onChanged: (v) {
              Prefs.setBool('still.disabled', !v);
              setState(() {});
            },
          ),
          sub: 'Pauses after a while with no mouse or keyboard activity.',
        ),
        if (stillOn)
          _row(
            'Ask after',
            DropdownButton<int>(
              value: hours,
              underline: const SizedBox.shrink(),
              items: [
                for (final h in [1, 2, 3, 4, 6]) DropdownMenuItem(value: h, child: Text('$h hour${h == 1 ? '' : 's'}')),
              ],
              onChanged: (v) {
                if (v != null) Prefs.setInt('still.hours', v);
                setState(() {});
              },
            ),
          ),
        if (stillOn)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextField(
              controller: _msgCtrl,
              onChanged: (v) => Prefs.setStr('still.msg', v.trim().isEmpty ? null : v.trim()),
              decoration: InputDecoration(
                labelText: 'Message',
                hintText: StillWatching.defaultMessage,
                filled: true,
                fillColor: BMColors.surfaceHigh,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
          ),

        _section('KEYBOARD SHORTCUTS'),
        const HotkeyEditor(),

        _section('DATA'),
        _row(
          'Clear watch history',
          OutlinedButton(
            onPressed: () async {
              if (await _confirm('Clear watch history?',
                  'Continue Watching and Recent Channels will be emptied, and saved spots in movies are lost.')) {
                await Services.db.delete(Services.db.history).go();
                _snack('Watch history cleared.');
              }
            },
            child: const Text('Clear'),
          ),
          sub: 'Empties Continue Watching and Recent Channels.',
        ),
        _row(
          'Clear favorites',
          OutlinedButton(
            onPressed: () async {
              if (await _confirm('Clear all favorites?', 'Every starred channel, movie, and show will be unstarred.')) {
                await Services.db.delete(Services.db.favorites).go();
                _snack('Favorites cleared.');
              }
            },
            child: const Text('Clear'),
          ),
          sub: 'Removes every star.',
        ),
        _row(
          'Reset server health',
          OutlinedButton(
            onPressed: () {
              Services.health.clearAll();
              _snack('Server health reset. Every server gets a fresh try.');
            },
            child: const Text('Reset'),
          ),
          sub: 'Forget which servers were marked down.',
        ),
        _row(
          'Clear all data',
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.redAccent,
              side: const BorderSide(color: Colors.redAccent),
            ),
            onPressed: () async {
              if (await _confirm('Clear ALL data?',
                  'Removes every account, channel, favorite, and watch history entry, plus the saved logins. Settings are kept.')) {
                await Services.playback.stop();
                final accts = await Services.db.select(Services.db.accounts).get();
                for (final a in accts) {
                  await Services.accounts.delete(a.id);
                }
                await Services.db.delete(Services.db.history).go();
                await Services.db.delete(Services.db.favorites).go();
                _snack('All data cleared.');
              }
            },
            child: const Text('Clear'),
          ),
          sub: 'Removes all accounts, channels, favorites, and history.',
        ),

        _section('BACKUP'),
        _row(
          'Export backup',
          OutlinedButton(onPressed: _export, child: const Text('Export…')),
          sub: 'Accounts, logins, favorites, watch history, and settings in one file. It contains your passwords, so keep it private.',
        ),
        _row(
          'Import backup',
          OutlinedButton(onPressed: _import, child: const Text('Import…')),
          sub: 'Adds everything from a backup file and reloads its accounts. Nothing you have now is deleted.',
        ),
        _section('DEBUG LOG'),
        _row(
          'Diagnostic log',
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: AppLog.text(last: 200)));
                  _snack('Copied the last 200 lines. Paste them into the chat.');
                },
                child: const Text('Copy recent'),
              ),
              OutlinedButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: AppLog.text()));
                  _snack('Copied the whole log.');
                },
                child: const Text('Copy all'),
              ),
              OutlinedButton(
                onPressed: () {
                  AppLog.clear();
                  setState(() {});
                  _snack('Log cleared.');
                },
                child: const Text('Clear'),
              ),
            ],
          ),
          sub: '${AppLog.count} lines kept. Passwords in stream links are hidden.',
        ),

        _section('ABOUT'),
        const Text('Black Mango 2.0 · development build', style: TextStyle(color: BMColors.text)),
        const SizedBox(height: 4),
        const Text('Free and open source (GPL-3.0) · github.com/Chadloz/Black-mango2.0',
            style: TextStyle(color: BMColors.dim, fontSize: 13)),
        _row(
          'App updates',
          const OutlinedButton(onPressed: null, child: Text('Check for updates')),
          sub: 'Automatic updates arrive with the first 2.0 release.',
        ),
      ],
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(top: 28, bottom: 8),
        child: Text(t, style: const TextStyle(fontFamily: BMFonts.mono, fontSize: 11, letterSpacing: 1.5, color: BMColors.dim)),
      );

  Widget _row(String title, Widget control, {String? sub}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: BMColors.text, fontSize: 15)),
                  if (sub != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(sub, style: const TextStyle(color: BMColors.dim, fontSize: 12)),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            control,
          ],
        ),
      );

  Widget _langDrop(String value, ValueChanged<String> on) => DropdownButton<String>(
        value: value,
        underline: const SizedBox.shrink(),
        items: [for (final o in _langOptions) DropdownMenuItem(value: o.$1, child: Text(o.$2))],
        onChanged: (v) {
          if (v != null) on(v);
        },
      );

  Widget _shortcut(String key, String what) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 110,
              child: Text(key, style: const TextStyle(fontFamily: BMFonts.mono, fontSize: 13, color: BMColors.mango)),
            ),
            Text(what, style: const TextStyle(color: BMColors.text, fontSize: 14)),
          ],
        ),
      );
}
