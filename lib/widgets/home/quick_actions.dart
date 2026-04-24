import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/design_tokens.dart';

// ── QuickActionCard (grid style) ──────────────────────────────────────────────

class QuickActionCard extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const QuickActionCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  State<QuickActionCard> createState() => _QuickActionCardState();
}

class _QuickActionCardState extends State<QuickActionCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? AppColors.glassWhite : Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.xxl),
            border: Border.all(
              color: _pressed
                  ? widget.iconColor.withAlpha(80)
                  : (isDark ? AppColors.glassBorder : Colors.grey.shade200),
            ),
            boxShadow: _pressed
                ? [
                    BoxShadow(
                      color: widget.iconColor.withAlpha(20),
                      blurRadius: 12,
                      spreadRadius: -2,
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: widget.iconBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(widget.icon, color: widget.iconColor, size: 22),
              ),
              const SizedBox(height: 12),
              Text(
                widget.title,
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : AppColors.slate900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.subtitle,
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  color: isDark ? AppColors.slate400 : AppColors.slate500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── QuickActionsSection (container with layout switching) ──────────────────────

class QuickActionsSection extends StatelessWidget {
  final String style;
  final List<String> enabledIds;

  const QuickActionsSection({super.key, required this.style, required this.enabledIds});

  @override
  Widget build(BuildContext context) {
    final actions = [
      {
        'id': 'consultant',
        'icon': Icons.psychology_rounded,
        'iconColor': Theme.of(context).colorScheme.secondary,
        'iconBg': Theme.of(context).colorScheme.secondary.withAlpha(51),
        'title': 'Consultant AI',
        'subtitle': 'Strategy & advice',
        'route': '/consultant',
      },
      {
        'id': 'sessions',
        'icon': Icons.history_rounded,
        'iconColor': const Color(0xFF34D399),
        'iconBg': const Color(0xFF34D399).withAlpha(51),
        'title': 'History',
        'subtitle': 'Past sessions',
        'route': '/sessions',
      },
      {
        'id': 'roleplay',
        'icon': Icons.theater_comedy_outlined,
        'iconColor': Colors.deepPurple,
        'iconBg': Colors.deepPurple.withAlpha(51),
        'title': 'Roleplay Mode',
        'subtitle': 'Practice with personas',
        'route': '/roleplay-setup',
      },
      {
        'id': 'game-center',
        'icon': Icons.emoji_events,
        'iconColor': AppColors.xpGold,
        'iconBg': AppColors.xpGold.withAlpha(51),
        'title': 'Game Center',
        'subtitle': 'Quests & achievements',
        'route': '/game-center',
      },
      {
        'id': 'graph-explorer',
        'icon': Icons.hub_rounded,
        'iconColor': const Color(0xFF8B5CF6),
        'iconBg': const Color(0xFF8B5CF6).withAlpha(51),
        'title': 'Knowledge Graph',
        'subtitle': 'Explore your memory',
        'route': '/graph-explorer',
      },
      {
        'id': 'insights',
        'icon': Icons.lightbulb_outline,
        'iconColor': const Color(0xFFF59E0B),
        'iconBg': const Color(0xFFF59E0B).withAlpha(51),
        'title': 'Insights',
        'subtitle': 'Events & highlights',
        'route': '/insights',
      },
    ].where((a) => enabledIds.contains(a['id'])).toList();

    if (actions.isEmpty) {
      return const SizedBox();
    }

    if (style == 'list') {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: actions.map((a) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: QuickActionListTile(
              icon: a['icon'] as IconData,
              iconColor: a['iconColor'] as Color,
              iconBg: a['iconBg'] as Color,
              title: a['title'] as String,
              subtitle: a['subtitle'] as String,
              onTap: () => Navigator.pushNamed(context, a['route'] as String),
            ),
          )).toList(),
        ),
      );
    } else if (style == 'icons') {
      final rowCount = (actions.length / 3).ceil();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: List.generate(rowCount, (rowIndex) {
            final rowActions = actions.skip(rowIndex * 3).take(3).toList();
            return Padding(
              padding: EdgeInsets.only(bottom: rowIndex == rowCount - 1 ? 0 : 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(3, (i) {
                  if (i < rowActions.length) {
                    final a = rowActions[i];
                    return QuickActionIconStyle(
                      icon: a['icon'] as IconData,
                      iconColor: a['iconColor'] as Color,
                      iconBg: a['iconBg'] as Color,
                      title: a['title'] as String,
                      onTap: () => Navigator.pushNamed(context, a['route'] as String),
                    );
                  } else {
                    return const SizedBox(width: 76); // matches width of QuickActionIconStyle
                  }
                }),
              ),
            );
          }),
        ),
      );
    } else {
      // Default to 'grid'
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            for (var i = 0; i < actions.length; i += 2)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: QuickActionCard(
                        icon: actions[i]['icon'] as IconData,
                        iconColor: actions[i]['iconColor'] as Color,
                        iconBg: actions[i]['iconBg'] as Color,
                        title: actions[i]['title'] as String,
                        subtitle: actions[i]['subtitle'] as String,
                        onTap: () => Navigator.pushNamed(context, actions[i]['route'] as String),
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (i + 1 < actions.length)
                      Expanded(
                        child: QuickActionCard(
                          icon: actions[i + 1]['icon'] as IconData,
                          iconColor: actions[i + 1]['iconColor'] as Color,
                          iconBg: actions[i + 1]['iconBg'] as Color,
                          title: actions[i + 1]['title'] as String,
                          subtitle: actions[i + 1]['subtitle'] as String,
                          onTap: () => Navigator.pushNamed(context, actions[i + 1]['route'] as String),
                        ),
                      )
                    else
                      const Expanded(child: SizedBox()),
                  ],
                ),
              ),
          ],
        ),
      );
    }
  }
}

// ── QuickActionListTile ───────────────────────────────────────────────────────

class QuickActionListTile extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const QuickActionListTile({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  State<QuickActionListTile> createState() => _QuickActionListTileState();
}

class _QuickActionListTileState extends State<QuickActionListTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? AppColors.glassWhite : Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.xxl),
            border: Border.all(
              color: _pressed
                  ? widget.iconColor.withAlpha(80)
                  : (isDark ? AppColors.glassBorder : Colors.grey.shade200),
            ),
            boxShadow: _pressed
                ? [
                    BoxShadow(
                      color: widget.iconColor.withAlpha(20),
                      blurRadius: 12,
                      spreadRadius: -2,
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: widget.iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(widget.icon, color: widget.iconColor, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: GoogleFonts.manrope(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : AppColors.slate900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle,
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        color: isDark ? AppColors.slate400 : AppColors.slate500,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: isDark ? Colors.white30 : Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── QuickActionIconStyle ──────────────────────────────────────────────────────

class QuickActionIconStyle extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final VoidCallback onTap;

  const QuickActionIconStyle({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.onTap,
  });

  @override
  State<QuickActionIconStyle> createState() => _QuickActionIconStyleState();
}

class _QuickActionIconStyleState extends State<QuickActionIconStyle> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.9 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: SizedBox(
          width: 76,
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: widget.iconBg,
                  borderRadius: BorderRadius.circular(16),
                  border: _pressed
                      ? Border.all(color: widget.iconColor.withAlpha(80), width: 1.5)
                      : null,
                  boxShadow: [
                    if (_pressed)
                      BoxShadow(
                        color: widget.iconColor.withAlpha(40),
                        blurRadius: 10,
                        spreadRadius: -2,
                      )
                  ],
                ),
                child: Icon(widget.icon, color: widget.iconColor, size: 28),
              ),
              const SizedBox(height: 8),
              Text(
                widget.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  height: 1.1,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : AppColors.slate700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
