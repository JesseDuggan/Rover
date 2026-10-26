import 'package:flutter/material.dart';

import 'drive_interest_catalog.dart';

class DriveInterestsScreen extends StatefulWidget {
  const DriveInterestsScreen({required this.selected, super.key});
  final Set<String> selected;
  @override
  State<DriveInterestsScreen> createState() => _DriveInterestsScreenState();
}

class _DriveInterestsScreenState extends State<DriveInterestsScreen> {
  late final Set<String> _selected = {...widget.selected};
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Driving interests')),
    body: ListView(
      children: [
        for (final category in driveCategories)
          ExpansionTile(
            key: PageStorageKey(category.id),
            leading: Checkbox(
              semanticLabel: category.label,
              value:
                  _selected.contains(category.id) ||
                  category.children.keys.any(_selected.contains),
              onChanged: (value) => setState(() {
                _selected.remove(category.id);
                _selected.removeAll(category.children.keys);
                if (value == true) _selected.add(category.id);
              }),
            ),
            title: Text(category.label),
            subtitle: Text(
              _selected.contains(category.id)
                  ? 'Any in this category'
                  : '${category.children.keys.where(_selected.contains).length} specific interests',
            ),
            children: [
              for (final child in category.children.entries)
                CheckboxListTile(
                  title: Text(child.value),
                  value: _selected.contains(child.key),
                  onChanged: (value) => setState(() {
                    _selected.remove(category.id);
                    if (value == true) {
                      _selected.add(child.key);
                    } else {
                      _selected.remove(child.key);
                    }
                  }),
                ),
            ],
          ),
      ],
    ),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton.icon(
          icon: const Icon(Icons.check),
          label: const Text('Use these interests'),
          onPressed: () => Navigator.pop(context, _selected),
        ),
      ),
    ),
  );
}
