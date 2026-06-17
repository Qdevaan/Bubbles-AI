// Purpose: Bottom sheet listing all tracked mistakes for a session with category labels and timestamps.
import 'package:flutter/material.dart';

import '../services/mistake_service.dart';
import 'app_sheet.dart';

class MistakeListSheet extends StatelessWidget {
  final List<MistakeItem> items;
  const MistakeListSheet({super.key, required this.items});

  static Future<void> show(BuildContext context, List<MistakeItem> items) {
    return AppSheet.show<void>(
      context: context,
      title: 'Mistakes this session',
      icon: Icons.error_outline_rounded,
      heightFactor: 0.75,
      child: MistakeListSheet(items: items),
    );
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<MistakeItem>>{};
    for (final it in items) {
      grouped.putIfAbsent(it.category, () => []).add(it);
    }
    final categories = grouped.keys.toList()
      ..sort((a, b) => grouped[b]!.length.compareTo(grouped[a]!.length));

    return ListView(
      shrinkWrap: true,
      children: [
        for (final cat in categories) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(
              '${cat.replaceAll('_', ' ')} '
              '(${grouped[cat]!.length})',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          for (final it in grouped[cat]!)
            ListTile(
              dense: true,
              title: Text(it.snippet),
              subtitle:
                  it.suggestion != null ? Text('→ ${it.suggestion}') : null,
            ),
        ],
      ],
    );
  }
}
