import 'package:flutter/material.dart';
import '../theme/design_tokens.dart';

class AppLogo extends StatelessWidget {
  final double size;
  final Color? fallbackColor;

  const AppLogo({super.key, this.size = 100, this.fallbackColor});

  @override
  Widget build(BuildContext context) {
    // Detect system theme for correct logo
    // We use platformBrightness to be safe, or Theme.of(context).brightness
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Image.asset(
      isDarkMode ? 'assets/logos/logo_dark.png' : 'assets/logos/logo_light.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (c, o, s) => Icon(
        Icons.bubble_chart,
        size: size,
        color: fallbackColor ?? Theme.of(context).colorScheme.primary,
      ),
    );
  }
}
