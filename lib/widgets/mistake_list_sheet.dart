import 'package:flutter/material.dart';

import '../services/mistake_service.dart';

class MistakeListSheet extends StatelessWidget {
  final List<MistakeItem> items;
  const MistakeListSheet({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<MistakeItem>>{};
    for (final it in items) {
      grouped.putIfAbsent(it.category, () => []).add(it);
    }
    final categories = grouped.keys.toList()
      ..sort((a, b) => grouped[b]!.length.compareTo(grouped[a]!.length));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Mistakes this session',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.6,
              ),
              child: ListView(
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
                        subtitle: it.suggestion != null
                            ? Text('→ ${it.suggestion}')
                            : null,
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
