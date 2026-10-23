import 'package:flutter/material.dart';
import '../../app/theme.dart';

/// Multi-select account filter. Empty selection = all accounts.
class AccountPicker extends StatelessWidget {
  final Map<String, String> names;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  const AccountPicker({super.key, required this.names, required this.selected, required this.onChanged});

  String get _label {
    if (selected.isEmpty) return 'All accounts';
    if (selected.length == 1) return names[selected.first] ?? '1 account';
    return '${selected.length} accounts';
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        if (selected.isNotEmpty)
          MenuItemButton(
            leadingIcon: const Icon(Icons.clear, size: 18),
            onPressed: () => onChanged(<String>{}),
            child: const Text('Clear selection'),
          ),
        MenuItemButton(
          onPressed: () => onChanged(<String>{}),
          leadingIcon: selected.isEmpty
              ? Icon(Icons.check, size: 18, color: BMColors.mango)
              : const SizedBox(width: 18),
          child: const Text('All accounts'),
        ),
        const Divider(height: 1),
        for (final e in names.entries)
          CheckboxMenuButton(
            value: selected.contains(e.key),
            closeOnActivate: false,
            onChanged: (v) {
              final s = Set<String>.from(selected);
              if (v == true) {
                s.add(e.key);
              } else {
                s.remove(e.key);
              }
              onChanged(s);
            },
            child: Text(e.value),
          ),
      ],
      builder: (context, controller, _) => OutlinedButton.icon(
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Icons.filter_list, size: 18),
        label: Text(_label, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}
