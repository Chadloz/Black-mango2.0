import 'package:flutter/material.dart';

/// Country and language filters, multi-select. Empty = no filter.
class FilterMenu extends StatelessWidget {
  final List<String> countries;
  final List<String> languages;
  final Set<String> selCountries;
  final Set<String> selLanguages;
  final void Function(Set<String> countries, Set<String> languages) onChanged;

  const FilterMenu({
    super.key,
    required this.countries,
    required this.languages,
    required this.selCountries,
    required this.selLanguages,
    required this.onChanged,
  });

  Set<String> _toggle(Set<String> s, String v, bool? on) {
    final n = Set<String>.from(s);
    if (on == true) {
      n.add(v);
    } else {
      n.remove(v);
    }
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final count = selCountries.length + selLanguages.length;
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(onPressed: () => onChanged(<String>{}, <String>{}), child: const Text('Clear filters')),
        const Divider(height: 1),
        SubmenuButton(
          menuChildren: [
            for (final c in countries)
              CheckboxMenuButton(
                value: selCountries.contains(c),
                closeOnActivate: false,
                onChanged: (v) => onChanged(_toggle(selCountries, c, v), selLanguages),
                child: Text(c),
              ),
          ],
          child: Text(selCountries.isEmpty ? 'Country' : 'Country (${selCountries.length})'),
        ),
        SubmenuButton(
          menuChildren: [
            for (final l in languages)
              CheckboxMenuButton(
                value: selLanguages.contains(l),
                closeOnActivate: false,
                onChanged: (v) => onChanged(selCountries, _toggle(selLanguages, l, v)),
                child: Text(l),
              ),
          ],
          child: Text(selLanguages.isEmpty ? 'Language' : 'Language (${selLanguages.length})'),
        ),
      ],
      builder: (context, controller, _) => OutlinedButton.icon(
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Icons.tune, size: 18),
        label: Text(count == 0 ? 'Filters' : 'Filters ($count)', maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}
