// Purpose: Badge widget that shows the count of tracked communication mistakes for a session.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/mistake_provider.dart';
import 'mistake_list_sheet.dart';

class MistakeBadge extends StatelessWidget {
  const MistakeBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<MistakeProvider>(
      builder: (context, p, _) {
        if (p.sessionTotal == 0) return const SizedBox.shrink();
        return InkWell(
          onTap: () => MistakeListSheet.show(context, p.items),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .errorContainer
                  .withAlpha(180),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.flag_rounded, size: 16),
                const SizedBox(width: 6),
                Text('${p.sessionTotal} flags',
                    style: Theme.of(context).textTheme.labelMedium),
              ],
            ),
          ),
        );
      },
    );
  }
}
