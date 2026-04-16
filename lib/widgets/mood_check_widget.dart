import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/design_tokens.dart';

/// Daily mood check-in widget with emoji selectors and tap animation.
/// Emits the selected mood via [onMoodSelected].
class MoodCheckWidget extends StatefulWidget {
  final String? currentMood;
  final ValueChanged<String> onMoodSelected;

  const MoodCheckWidget({
    super.key,
    this.currentMood,
    required this.onMoodSelected,
  });

  @override
  State<MoodCheckWidget> createState() => _MoodCheckWidgetState();
}

class _MoodCheckWidgetState extends State<MoodCheckWidget> {
  String? _selected;

  static const _moods = [
    ('great', '😊', 'Great', AppColors.moodGreat),
    ('good', '🙂', 'Good', AppColors.moodGood),
    ('neutral', '😐', 'Okay', AppColors.moodNeutral),
    ('low', '😔', 'Low', AppColors.moodLow),
    ('tough', '😢', 'Tough', AppColors.moodTough),
  ];

  @override
  void initState() {
    super.initState();
    _selected = widget.currentMood;
  }

  @override
  void didUpdateWidget(MoodCheckWidget old) {
    super.didUpdateWidget(old);
    if (widget.currentMood != old.currentMood) {
      _selected = widget.currentMood;
    }
  }

  void _selectMood(String mood) {
    HapticFeedback.lightImpact();
    setState(() => _selected = mood);
    widget.onMoodSelected(mood);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasSelected = _selected != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.glassWhite : Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        border: Border.all(
          color: isDark ? AppColors.glassBorder : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                hasSelected ? 'Today\'s mood' : 'How are you feeling?',
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : AppColors.slate900,
                ),
              ),
              if (hasSelected) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _colorForMood(_selected!).withAlpha(30),
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                  child: Text(
                    _labelForMood(_selected!),
                    style: GoogleFonts.manrope(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _colorForMood(_selected!),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: _moods.map((m) {
              final isActive = _selected == m.$1;
              return _MoodButton(
                emoji: m.$2,
                label: m.$3,
                color: m.$4,
                isActive: isActive,
                isDimmed: hasSelected && !isActive,
                onTap: () => _selectMood(m.$1),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Color _colorForMood(String mood) {
    return _moods
        .firstWhere((m) => m.$1 == mood, orElse: () => _moods[2])
        .$4;
  }

  String _labelForMood(String mood) {
    return _moods
        .firstWhere((m) => m.$1 == mood, orElse: () => _moods[2])
        .$3;
  }
}

class _MoodButton extends StatefulWidget {
  final String emoji;
  final String label;
  final Color color;
  final bool isActive;
  final bool isDimmed;
  final VoidCallback onTap;

  const _MoodButton({
    required this.emoji,
    required this.label,
    required this.color,
    required this.isActive,
    required this.isDimmed,
    required this.onTap,
  });

  @override
  State<_MoodButton> createState() => _MoodButtonState();
}

class _MoodButtonState extends State<_MoodButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scale = Tween(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut),
    );
  }

  @override
  void didUpdateWidget(_MoodButton old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) {
      _ctrl.forward().then((_) {
        if (mounted) _ctrl.reverse();
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: widget.isDimmed ? 0.4 : 1.0,
        child: AnimatedBuilder(
          animation: _scale,
          builder: (_, child) => Transform.scale(
            scale: _scale.value,
            child: child,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.isActive
                      ? widget.color.withAlpha(30)
                      : (isDark
                          ? AppColors.glassWhite
                          : Colors.grey.shade50),
                  border: Border.all(
                    color: widget.isActive
                        ? widget.color
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Text(
                    widget.emoji,
                    style: const TextStyle(fontSize: 22),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.label,
                style: GoogleFonts.manrope(
                  fontSize: 10,
                  fontWeight:
                      widget.isActive ? FontWeight.w700 : FontWeight.w500,
                  color: widget.isActive
                      ? widget.color
                      : (isDark ? AppColors.slate500 : AppColors.slate400),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
