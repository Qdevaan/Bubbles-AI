// Purpose: Horizontal strip widget showing the latest Wingman AI coaching tip during a live session.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/suggestion_controller.dart';
import 'suggestion_sheet.dart';

class SuggestionStrip extends StatelessWidget {
  const SuggestionStrip({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SuggestionController>(
      builder: (context, c, _) {
        if (c.suggestions.isEmpty) return const SizedBox.shrink();
        final opacity = c.isDraft ? 0.6 : 1.0;
        return SizedBox(
          height: 56,
          child: Opacity(
            opacity: opacity,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: c.suggestions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final text = c.suggestions[i];
                return ActionChip(
                  label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Text(
                      text,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  onPressed: () => SuggestionSheet.show(
                    context,
                    text: text,
                    tone: c.tone,
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
