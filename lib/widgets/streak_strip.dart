import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/design_tokens.dart';

/// Compact strip showing streak fire, XP total, level, and freeze count.
/// Tappable to navigate to the Game Center.
class StreakStrip extends StatefulWidget {
  final int streak;
  final int totalXp;
  final int level;
  final int streakFreezes;
  final String skillTierEmoji;
  final VoidCallback? onTap;

  const StreakStrip({
    super.key,
    required this.streak,
    required this.totalXp,
    required this.level,
    required this.streakFreezes,
    required this.skillTierEmoji,
    this.onTap,
  });

  @override
  State<StreakStrip> createState() => _StreakStripState();
}

class _StreakStripState extends State<StreakStrip>
    with SingleTickerProviderStateMixin {
  late AnimationController _fireCtrl;

  @override
  void initState() {
    super.initState();
    _fireCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    if (widget.streak > 0) _fireCtrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(StreakStrip old) {
    super.didUpdateWidget(old);
    if (widget.streak > 0 && !_fireCtrl.isAnimating) {
      _fireCtrl.repeat(reverse: true);
    } else if (widget.streak <= 0 && _fireCtrl.isAnimating) {
      _fireCtrl.stop();
      _fireCtrl.value = 0;
    }
  }

  @override
  void dispose() {
    _fireCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isHot = widget.streak >= 3;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? AppColors.glassWhite : Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(
            color: isDark
                ? (isHot
                    ? AppColors.streakFire.withAlpha(60)
                    : AppColors.glassBorder)
                : Colors.grey.shade200,
          ),
          boxShadow: isHot
              ? [
                  BoxShadow(
                    color: AppColors.streakFire.withAlpha(isDark ? 30 : 15),
                    blurRadius: 12,
                    spreadRadius: -2,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Fire icon
            AnimatedBuilder(
              animation: _fireCtrl,
              builder: (_, child) => Transform.scale(
                scale: 1.0 + (_fireCtrl.value * 0.15),
                child: child,
              ),
              child: Text(
                widget.streak > 0 ? '🔥' : '💤',
                style: const TextStyle(fontSize: 16),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${widget.streak}d',
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: isHot
                    ? AppColors.streakFire
                    : (isDark ? AppColors.slate400 : AppColors.slate500),
              ),
            ),
            _dot(isDark),
            // XP
            Icon(
              Icons.star_rounded,
              size: 14,
              color: AppColors.xpGold,
            ),
            const SizedBox(width: 3),
            Text(
              _formatXp(widget.totalXp),
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : AppColors.slate900,
              ),
            ),
            _dot(isDark),
            // Level
            Text(
              '${widget.skillTierEmoji} Lv.${widget.level}',
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.levelBadge,
              ),
            ),
            if (widget.streakFreezes > 0) ...[
              _dot(isDark),
              Text(
                '❄️×${widget.streakFreezes}',
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppColors.slate400 : AppColors.slate500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _dot(bool isDark) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Container(
          width: 3,
          height: 3,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDark ? AppColors.slate500 : Colors.grey.shade300,
          ),
        ),
      );

  String _formatXp(int xp) {
    if (xp >= 10000) return '${(xp / 1000).toStringAsFixed(1)}k';
    if (xp >= 1000) return '${(xp / 1000).toStringAsFixed(1)}k';
    return '$xp';
  }
}
