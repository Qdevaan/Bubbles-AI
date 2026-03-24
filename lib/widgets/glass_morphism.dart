import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/design_tokens.dart';

/// Mesh gradient background used on most screens.
/// Replicates: radial-gradients at corners with primary@15% on #101e22 base.
class MeshGradientBackground extends StatelessWidget {
  final Widget? child;
  const MeshGradientBackground({super.key, this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Adapted for Light mode too using the accent color
    final bgColor = isDark ? AppColors.backgroundDark : AppColors.backgroundLight;
    final blurColor1 = Theme.of(context).colorScheme.primary.withAlpha(isDark ? 38 : 60); // 15% / ~25%
    final blurColor2 = Theme.of(context).colorScheme.primary.withAlpha(isDark ? 26 : 40); // 10% / ~15%
    final radialBase = isDark ? AppColors.backgroundDark : AppColors.backgroundLight;

    return Container(
      decoration: BoxDecoration(color: bgColor),
      child: Stack(
        children: [
          // Top-left glow
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    blurColor1,
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Bottom-right glow
          Positioned(
            bottom: -100,
            right: -100,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    blurColor2,
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Center subtlety
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.2,
                  colors: [
                    radialBase.withAlpha(100),
                    radialBase.withAlpha(0),
                  ],
                ),
              ),
            ),
          ),
          if (child != null) child!,
        ],
      ),
    );
  }
}

/// Standard glass card matching .glass-card CSS:
/// background: rgba(255,255,255,0.03), blur(12px), border rgba(255,255,255,0.1)
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double borderRadius;
  final double blur;
  final Color? backgroundColor;
  final Color? borderColor;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = AppRadius.xxl,
    this.blur = 12,
    this.backgroundColor,
    this.borderColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = backgroundColor ??
        (isDark ? AppColors.glassWhite : Colors.white.withAlpha(220)); // White glass base
    final border = borderColor ??
        (isDark ? AppColors.glassBorder : Colors.white.withAlpha(255)); // Tinted border

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(color: border, width: 1),
            ),
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Glass panel — thinner border variant for sections.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double borderRadius;

  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = AppRadius.xxl,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.glassWhite : Theme.of(context).colorScheme.primary.withAlpha(12),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: isDark ? AppColors.glassBorderLight : Theme.of(context).colorScheme.primary.withAlpha(20),
              width: 1,
            ),
          ),
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

/// Glass tile — used for list items, settings rows.
/// Matches .glass-tile: rgba(255,255,255,0.03) + blur(8px)
class GlassTile extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final bool active;

  const GlassTile({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = active
        ? Theme.of(context).colorScheme.primary.withAlpha(isDark ? 38 : 60)
        : (isDark ? AppColors.glassWhite : Theme.of(context).colorScheme.primary.withAlpha(8));
    final border = active
        ? Theme.of(context).colorScheme.primary.withAlpha(isDark ? 76 : 100)
        : (isDark ? AppColors.glassBorderLight : Theme.of(context).colorScheme.primary.withAlpha(20));

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: border, width: 1),
            ),
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// A standard glassmorphic dialog wrapper.
class GlassDialog extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double borderRadius;

  const GlassDialog({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.borderRadius = AppRadius.xxl,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: GlassCard(
        padding: padding,
        borderRadius: borderRadius,
        borderColor: isDark
            ? Theme.of(context).colorScheme.primary.withAlpha(80)
            : Colors.white.withAlpha(255),
        backgroundColor: isDark
            ? AppColors.backgroundDark.withAlpha(200)
            : Colors.white.withAlpha(240),
        blur: 20,
        child: child,
      ),
    );
  }
}

/// A standard glassmorphic bottom sheet wrapper.
class GlassBottomSheet extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  
  const GlassBottomSheet({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xxl)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.backgroundDark.withAlpha(220)
                : Colors.white.withAlpha(240),
            border: Border(
              top: BorderSide(
                color: isDark
                    ? Theme.of(context).colorScheme.primary.withAlpha(80)
                    : Colors.white.withAlpha(255),
                width: 1,
              ),
            ),
          ),
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

/// Glass pill button — matches .glass-pill:
/// rgba(19,189,236,0.15) + blur(10px) + inset glow
class GlassPillButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool loading;
  final IconData? icon;

  const GlassPillButton({
    super.key,
    required this.label,
    required this.onTap,
    this.loading = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.full),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withAlpha(38),
              borderRadius: BorderRadius.circular(AppRadius.full),
              border: Border.all(color: Theme.of(context).colorScheme.primary.withAlpha(77), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).colorScheme.primary.withAlpha(51), // inset glow
                  blurRadius: 15,
                  spreadRadius: -2,
                ),
              ],
            ),
            child: Center(
              child: loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        if (icon != null) ...[
                          const SizedBox(width: 8),
                          Icon(icon, color: Colors.white, size: 18),
                        ],
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Glass bottom nav bar matching stitch designs.
class GlassBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<GlassBottomNavItem> items;

  const GlassBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 72,
          decoration: BoxDecoration(
            color: AppColors.glassWhite,
            border: Border(
              top: BorderSide(color: AppColors.glassBorder, width: 1),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(items.length, (i) {
              final active = i == currentIndex;
              final item = items[i];
              return GestureDetector(
                onTap: () => onTap(i),
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 64,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        item.icon,
                        color: active ? Theme.of(context).colorScheme.primary : AppColors.slate500,
                        size: 24,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight:
                              active ? FontWeight.w600 : FontWeight.w400,
                          color:
                              active ? Theme.of(context).colorScheme.primary : AppColors.slate500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class GlassBottomNavItem {
  final IconData icon;
  final String label;
  const GlassBottomNavItem({required this.icon, required this.label});
}

/// Glass header bar — sticky header with backdrop blur.
class GlassHeader extends StatelessWidget {
  final Widget? leading;
  final String title;
  final List<Widget>? actions;
  final bool centerTitle;

  const GlassHeader({
    super.key,
    this.leading,
    required this.title,
    this.actions,
    this.centerTitle = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? AppColors.glassWhite : Colors.white.withAlpha(200),
            border: Border(
              bottom: BorderSide(
                color: isDark ? AppColors.glassBorder : Colors.grey.shade200,
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              if (leading != null) leading!,
              if (centerTitle) const Spacer(),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : AppColors.slate900,
                ),
              ),
              if (centerTitle) const Spacer(),
              if (!centerTitle) const Expanded(child: SizedBox()),
              if (actions != null) ...actions!,
            ],
          ),
        ),
      ),
    );
  }
}

/// Light leak decorative element used for ambient effects.
class LightLeak extends StatelessWidget {
  final double size;
  final Alignment alignment;
  final Color color;

  const LightLeak({
    super.key,
    this.size = 300,
    this.alignment = Alignment.topLeft,
    this.color = const Color(0x3313BDEC), // primary @ 20%
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, Colors.transparent],
          ),
        ),
      ),
    );
  }
}
