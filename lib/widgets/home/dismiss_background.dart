import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';

/// Dismiss background shown when swiping an insight card to the left.
class DismissBackground extends StatelessWidget {
  final bool isDark;
  const DismissBackground({super.key, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        alignment: Alignment.topCenter,
        padding: const EdgeInsets.only(top: 20),
        decoration: BoxDecoration(
          color: AppColors.error.withAlpha(200),
          borderRadius: BorderRadius.circular(AppRadius.xxl),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 24),
      ),
    );
  }
}
