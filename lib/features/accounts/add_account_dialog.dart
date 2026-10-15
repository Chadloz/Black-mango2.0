import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/services.dart';
import '../../core/accounts/account_parser.dart';

/// Add Account: quick paste on top, the form underneath.
/// Paste fills the form; you can edit anything before saving.
class AddAccountDialog extends StatefulWidget {
  const AddAccountDialog({super.key});

  @override
  State<AddAccountDialog> createState() => _AddAccountDialogState();
}

class _AddAccountDialogState extends State<AddAccountDialog> {
  final _paste = TextEditingController();
  final _server = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _mac = TextEditingController();
  final _url = TextEditingController();
  final _name = TextEditingController();
  String _type = 'xtream';
  bool _showPass = false;
  bool _saving = false;
  List<String> _notes = [];
  String? _error;
  String? _testMsg;
  bool _testOk = false;
  bool _testing = false;

  @override
  void dispose() {
    for (final c in [_paste, _server, _user, _pass, _mac, _url, _name]) {
      c.dispose();
    }
    super.dispose();
  }

  void _detect() {
    final p = parseAccountText(_paste.text);
    setState(() {
      _error = null;
      if (p.isEmpty) {
        _notes = ['Nothing recognizable found. Fill in the form below.'];
        return;
      }
      _type = p.type;
      if (p.server.isNotEmpty) _server.text = p.server;
      if (p.username.isNotEmpty) _user.text = p.username;
      if (p.password.isNotEmpty) _pass.text = p.password;
      if (p.mac.isNotEmpty) _mac.text = p.mac;
      if (p.url.isNotEmpty) _url.text = p.url;
      if (_name.text.trim().isEmpty && p.suggestedName.isNotEmpty) _name.text = p.suggestedName;
      _notes = p.notes;
    });
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testMsg = null;
    });
    try {
      final msg = await Services.catalog.testInputs(
        type: _type,
        server: normalizeServer(_server.text),
        username: _user.text.trim(),
        password: _pass.text,
        url: _url.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _testOk = true;
        _testMsg = msg;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _testMsg = 'Test failed: $e';
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    final server = normalizeServer(_server.text);
    final url = _url.text.trim();
    String? err;
    if (_type == 'xtream' && (server.isEmpty || _user.text.trim().isEmpty || _pass.text.isEmpty)) {
      err = 'Server, username, and password are required.';
    } else if (_type == 'stalker' && (server.isEmpty || _mac.text.trim().isEmpty)) {
      err = 'Portal URL and MAC address are required.';
    } else if (_type == 'm3u' && url.isEmpty) {
      err = 'Playlist URL is required.';
    }
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final displayServer = _type == 'm3u' ? normalizeServer(hostOf(url)) : server;
    final fallbackName = hostOf(displayServer);
    final name = _name.text.trim().isNotEmpty ? _name.text.trim() : (fallbackName.isNotEmpty ? fallbackName : 'My Provider');
    try {
      final id = await Services.accounts.add(
        type: _type,
        name: name,
        server: displayServer,
        username: _type == 'xtream' ? _user.text.trim() : '',
        password: _type == 'xtream' ? _pass.text : '',
        mac: _type == 'stalker' ? _mac.text.trim().toUpperCase() : '',
        url: _type == 'm3u' ? url : '',
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(SnackBar(content: Text('Saved "$name". Loading...')));
      final account = await Services.accounts.get(id);
      if (account != null && account.type != 'stalker') {
        Services.catalog.load(account).then(
          (msg) => messenger.showSnackBar(SnackBar(content: Text('$name: $msg'))),
          onError: (e) => messenger.showSnackBar(SnackBar(content: Text('$name: load failed: $e'))),
        );
      }
    } catch (e) {
      setState(() {
        _saving = false;
        _error = 'Could not save: $e';
      });
    }
  }

  InputDecoration _dec(String hint, {Widget? suffix}) {
    OutlineInputBorder b(Color c) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: c),
        );
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: BMColors.dim),
      filled: true,
      fillColor: BMColors.surfaceHigh,
      suffixIcon: suffix,
      border: b(BMColors.border),
      enabledBorder: b(BMColors.border),
      focusedBorder: b(BMColors.mango),
    );
  }

  List<Widget> _fields() {
    switch (_type) {
      case 'stalker':
        return [
          const _Label('PORTAL URL'),
          TextField(controller: _server, decoration: _dec('http://portal.com:8080/c/')),
          const SizedBox(height: 12),
          const _Label('MAC ADDRESS'),
          TextField(controller: _mac, decoration: _dec('00:1A:79:XX:XX:XX')),
        ];
      case 'm3u':
        return [
          const _Label('PLAYLIST URL'),
          TextField(controller: _url, decoration: _dec('https://...m3u')),
        ];
      default:
        return [
          const _Label('SERVER URL'),
          TextField(controller: _server, decoration: _dec('http://provider.com:8080')),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Label('USERNAME'),
                    TextField(controller: _user, decoration: _dec('')),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Label('PASSWORD'),
                    TextField(
                      controller: _pass,
                      obscureText: !_showPass,
                      decoration: _dec(
                        '',
                        suffix: IconButton(
                          tooltip: _showPass ? 'Hide' : 'Show',
                          icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility, color: BMColors.dim),
                          onPressed: () => setState(() => _showPass = !_showPass),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: BMColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: BMColors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 780),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Text('Add Account', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: BMColors.text)),
                  const Spacer(),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
              const SizedBox(height: 12),
              const _Label('QUICK PASTE'),
              TextField(
                controller: _paste,
                minLines: 3,
                maxLines: 6,
                decoration: _dec("Paste a link, login details, or your provider's welcome message"),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _detect,
                    icon: const Icon(Icons.auto_fix_high, size: 18),
                    label: const Text('Detect'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(_notes.join('  '), style: const TextStyle(color: BMColors.mango, fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'xtream', label: Text('Xtream API')),
                  ButtonSegment(value: 'stalker', label: Text('Stalker / MAG')),
                  ButtonSegment(value: 'm3u', label: Text('M3U URL')),
                ],
                selected: {_type},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _type = s.first),
              ),
              const SizedBox(height: 16),
              ..._fields(),
              const SizedBox(height: 12),
              const _Label('NAME (OPTIONAL)'),
              TextField(controller: _name, decoration: _dec('My Provider')),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              ],
              if (_testMsg != null) ...[
                const SizedBox(height: 12),
                Text(_testMsg!, style: TextStyle(color: _testOk ? const Color(0xFF4CAF50) : Colors.redAccent)),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _testing ? null : _test,
                    child: Text(_testing ? 'Testing...' : 'Test'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? 'Saving...' : 'Save & Load'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text, style: const TextStyle(fontFamily: BMFonts.mono, fontSize: 11, letterSpacing: 1.5, color: BMColors.dim)),
    );
  }
}
