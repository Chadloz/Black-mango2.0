import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/services.dart';
import '../../core/storage/database.dart';
import 'add_account_dialog.dart';

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
          Text(_counts, style: const TextStyle(fontSize: 13, color: BMColors.dim)),
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
