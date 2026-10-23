import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/services.dart';
import '../../core/storage/database.dart';
import '../../core/accounts/account_parser.dart';
import '../../core/catalog/free_packs.dart';

/// Free channel packs. Each one is saved as an M3U account, marked with "pack:<id>"
/// in the username field (M3U accounts don't use usernames otherwise).
class FreeChannelsDialog extends StatelessWidget {
  const FreeChannelsDialog({super.key});

  Future<void> _add(BuildContext context, FreePack p) async {
    final messenger = ScaffoldMessenger.of(context);
    final id = await Services.accounts.add(
      type: 'm3u',
      name: p.name,
      server: normalizeServer(hostOf(p.url)),
      username: 'pack:${p.id}',
      url: p.url,
    );
    final a = await Services.accounts.get(id);
    if (a == null) return;
    messenger.showSnackBar(SnackBar(content: Text('${p.name}: loading...')));
    Services.catalog.load(a).then(
          (m) => messenger.showSnackBar(SnackBar(content: Text('${p.name}: $m'))),
          onError: (e) => messenger.showSnackBar(SnackBar(content: Text('${p.name}: load failed: $e'))),
        );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: BMColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: BMColors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 12, 4),
              child: Row(
                children: [
                  Text('Free Channels', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: BMColors.text)),
                  const Spacer(),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text('Free public channel packs. Add one and it loads like any other account.',
                  style: TextStyle(fontSize: 13, color: BMColors.dim)),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: StreamBuilder<List<Account>>(
                stream: Services.accounts.watchAll(),
                builder: (context, snap) {
                  final added = <String, String>{};
                  for (final a in snap.data ?? const <Account>[]) {
                    if (a.username.startsWith('pack:')) added[a.username.substring(5)] = a.id;
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    itemCount: freePacks.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final p = freePacks[i];
                      final accId = added[p.id];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            Text(p.icon, style: const TextStyle(fontSize: 24)),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(p.name, style: TextStyle(fontWeight: FontWeight.w700, color: BMColors.text)),
                                  const SizedBox(height: 2),
                                  Text(p.desc, style: TextStyle(fontSize: 12, color: BMColors.dim)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            accId == null
                                ? FilledButton(
                                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF3E7D32), foregroundColor: Colors.white),
                                    onPressed: () => _add(context, p),
                                    child: const Text('Add'),
                                  )
                                : FilledButton(
                                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB23B2E), foregroundColor: Colors.white),
                                    onPressed: () => Services.accounts.delete(accId),
                                    child: const Text('Remove'),
                                  ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
