import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/services.dart';
import '../../core/storage/database.dart';
import 'add_account_dialog.dart';
import 'free_channels_dialog.dart';
import '../../core/prefs.dart';

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
          child: Row(
            children: [
              const Text('Accounts', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: BMColors.text)),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () => showDialog(context: context, builder: (_) => const FreeChannelsDialog()),
                icon: const Icon(Icons.satellite_alt),
                label: const Text('Free Channels'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => showDialog(context: context, builder: (_) => const AddAccountDialog()),
                icon: const Icon(Icons.add),
                label: const Text('Account'),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Account>>(
            stream: Services.accounts.watchAll(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(child: Text('Could not load accounts: ${snap.error}', style: const TextStyle(color: Colors.redAccent)));
              }
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final list = snap.data!;
              if (list.isEmpty) return const _Empty();
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, i) => _AccountCard(account: list[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person_add_alt, size: 56, color: BMColors.mango),
          SizedBox(height: 16),
          Text('No accounts yet', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: BMColors.text)),
          SizedBox(height: 8),
          Text('Click + Account to add an Xtream, Stalker, or M3U account.', style: TextStyle(color: BMColors.dim)),
        ],
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  final Account account;
  const _AccountCard({required this.account});

  String get _host {
    final u = Uri.tryParse(account.server);
    if (u != null && u.host.isNotEmpty) return u.hasPort ? '${u.host}:${u.port}' : u.host;
    return account.server;
  }

  String get _counts {
    final total = account.liveCount + account.movieCount + account.seriesCount;
    if (total == 0) return 'Not loaded yet';
    return '${account.liveCount} live   ${account.movieCount} movies   ${account.seriesCount} shows';
  }

  Future<void> _rename(BuildContext context) async {
    final ctrl = TextEditingController(text: account.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename account'),
        content: TextField(controller: ctrl, autofocus: true, onSubmitted: (v) => Navigator.pop(ctx, v)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Save')),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) await Services.accounts.rename(account.id, name.trim());
  }

  Future<void> _reload(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final msg = await Services.catalog.load(account);
      final host = Uri.tryParse(account.server)?.host ?? '';
      if (host.isNotEmpty) Services.health.clear(host);
      messenger.showSnackBar(SnackBar(content: Text('${account.name}: $msg')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('${account.name}: load failed: $e')));
    }
  }

  Future<void> _delete(BuildContext context) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account?'),
        content: Text('Remove "${account.name}" and its saved login from this computer?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes == true) await Services.accounts.delete(account.id);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BMColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: BMColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _TypeBadge(type: account.type),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  account.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: BMColors.text),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(_host, style: const TextStyle(fontFamily: BMFonts.mono, fontSize: 12, color: BMColors.dim)),
          const SizedBox(height: 4),
          ValueListenableBuilder<Map<String, String>>(
            valueListenable: Services.catalog.status,
            builder: (context, st, _) {
              final msg = st[account.id];
              if (msg == null) return Text(_counts, style: const TextStyle(fontSize: 13, color: BMColors.dim));
              return Row(
                children: [
                  const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 8),
                  Text(msg, style: const TextStyle(fontSize: 13, color: BMColors.mango)),
                ],
              );
            },
          ),
          _AccountStatus(account: account),
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => _rename(context),
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('Rename'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => _reload(context),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Reload'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent),
                ),
                onPressed: () => _delete(context),
                icon: const Icon(Icons.close, size: 16),
                label: const Text('Delete'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Working / Server down / Expires on, under each account.
class _AccountStatus extends StatelessWidget {
  final Account account;
  const _AccountStatus({required this.account});

  String _ago(DateTime t) {
    final m = DateTime.now().difference(t).inMinutes;
    if (m < 1) return 'just now';
    return m < 60 ? '$m min ago' : '${m ~/ 60} hr ago';
  }

  Widget _dot(Color c, String t) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(t, style: TextStyle(fontSize: 12, color: c)),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final host = Uri.tryParse(account.server)?.host ?? '';
    final exp = Prefs.getInt('acct.${account.id}.exp');
    return ValueListenableBuilder<int>(
      valueListenable: Services.health.changes,
      builder: (context, _, _) {
        final h = Services.health;
        final parts = <Widget>[];
        final until = h.downUntil(host);
        final ok = h.lastOk(host);
        if (until != null) {
          final mins = until.difference(DateTime.now()).inMinutes + 1;
          parts.add(_dot(Colors.redAccent, 'Server down · skipping for $mins min'));
        } else if (ok != null) {
          parts.add(_dot(const Color(0xFF4CAF50), 'Working · played fine ${_ago(ok)}'));
        }
        if (exp != null && exp > 0) {
          final d = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
          final days = d.difference(DateTime.now()).inDays;
          final label = '${_months[d.month - 1]} ${d.day}, ${d.year}';
          final color = days < 0 ? Colors.redAccent : (days < 7 ? Colors.amber : BMColors.dim);
          parts.add(Text(days < 0 ? 'Expired $label' : 'Expires $label', style: TextStyle(fontSize: 12, color: color)));
        }
        if (parts.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(spacing: 16, runSpacing: 4, children: parts),
        );
      },
    );
  }
}

class _TypeBadge extends StatelessWidget {
  final String type;
  const _TypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final label = switch (type) { 'stalker' => 'STALKER', 'm3u' => 'M3U', _ => 'XTREAM' };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: const Color(0x224CAF50), borderRadius: BorderRadius.circular(6)),
      child: Text(
        label,
        style: const TextStyle(fontFamily: BMFonts.mono, fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF4CAF50)),
      ),
    );
  }
}
