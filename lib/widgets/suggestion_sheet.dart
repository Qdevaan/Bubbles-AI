import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/app_snack_bar.dart';
class SuggestionSheet extends StatelessWidget {
  final String text;
  final String tone;

  const SuggestionSheet({
    super.key,
    required this.text,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                tone,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
            const SizedBox(height: 16),
            SelectableText(
              text,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: text));
                if (!context.mounted) return;
                AppSnackBar.show(context, message: 'Copied');
                Navigator.pop(context);
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copy'),
            ),
          ],
        ),
      ),
    );
  }
}
