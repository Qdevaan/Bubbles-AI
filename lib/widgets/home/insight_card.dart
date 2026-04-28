import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/design_tokens.dart';

class HomeInsightCard extends StatefulWidget {
  final Color accentColor;
  final String title;
  final String badge;
  final String description;
  final bool isDark;
  final IconData? icon;
  final String? sessionId;
  final ValueChanged<bool>? onToggle;
  final VoidCallback? onLongPress;

  const HomeInsightCard({
    super.key,
    required this.accentColor,
    required this.title,
    required this.badge,
    required this.description,
    required this.isDark,
    this.icon,
    this.sessionId,
    this.onToggle,
    this.onLongPress,
  });

  @override
  State<HomeInsightCard> createState() => _HomeInsightCardState();
}

class _HomeInsightCardState extends State<HomeInsightCard>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  bool _dismissing = false;
  late AnimationController _ctrl;
  late Animation<double> _expandAnim;
  late Animation<double> _chevronTurn;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _expandAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _chevronTurn = Tween<double>(begin: 0.0, end: 0.5).animate(_expandAnim);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    _expanded ? _ctrl.forward() : _ctrl.reverse();
    widget.onToggle?.call(_expanded);
  }

  void _handleLongPress() async {
    HapticFeedback.heavyImpact();
    setState(() {
      _dismissing = true;
    });
    await Future.delayed(const Duration(milliseconds: 300));
    widget.onLongPress?.call();
  }

  @override
  Widget build(BuildContext context) {
    final hasBody = widget.description.isNotEmpty;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: _dismissing ? 0.0 : 1.0,
      curve: Curves.easeOut,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 300),
        scale: _dismissing ? 0.8 : 1.0,
        curve: Curves.easeInBack,
        child: GestureDetector(
          onLongPress: widget.onLongPress != null ? _handleLongPress : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: widget.isDark ? AppColors.glassWhite : Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.xxl),
              border: Border(left: BorderSide(color: widget.accentColor, width: 3)),
              boxShadow: _expanded
                  ? [
                      BoxShadow(
                          color: widget.accentColor.withAlpha(widget.isDark ? 30 : 15),
                          blurRadius: 16,
                          spreadRadius: -2)
                    ]
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(hasBody),
                _buildExpandedBody(hasBody),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool hasBody) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: hasBody ? _toggle : null,
      child: Row(children: [
        if (widget.icon != null)
          Container(
            padding: const EdgeInsets.all(7),
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              color: widget.accentColor.withAlpha(25),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(widget.icon, size: 16, color: widget.accentColor),
          ),
        Expanded(
          child: Text(widget.title,
              style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: widget.isDark ? Colors.white : AppColors.slate900)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: widget.accentColor.withAlpha(25),
            borderRadius: BorderRadius.circular(AppRadius.full),
            border: Border.all(color: widget.accentColor.withAlpha(80)),
          ),
          child: Text(widget.badge,
              style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: widget.accentColor)),
        ),
        if (hasBody) ...[
          const SizedBox(width: 6),
          RotationTransition(
            turns: _chevronTurn,
            child: Icon(Icons.expand_more_rounded,
                size: 20,
                color: widget.isDark
                    ? AppColors.slate500
                    : Colors.grey.shade400),
          ),
        ],
      ]),
    );
  }

  Widget _buildExpandedBody(bool hasBody) {
    return SizeTransition(
      sizeFactor: _expandAnim,
      axisAlignment: -1.0,
      child: hasBody
          ? Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: widget.isDark ? Colors.white.withAlpha(5) : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(widget.description,
                      style: GoogleFonts.manrope(fontSize: 13, color: widget.isDark ? AppColors.slate300 : AppColors.slate600, height: 1.6)),
                ),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.start, children: [
                  GestureDetector(
                    onTap: _toggle,
                    behavior: HitTestBehavior.opaque,
                    child: Row(children: [
                      Icon(Icons.touch_app_outlined, size: 12, color: widget.isDark ? AppColors.slate500 : Colors.grey.shade400),
                      const SizedBox(width: 4),
                      Text('Tap to collapse', style: GoogleFonts.manrope(fontSize: 11, color: widget.isDark ? AppColors.slate500 : Colors.grey.shade400)),
                    ]),
                  ),
                ]),
              ]),
            )
          : const SizedBox.shrink(),
    );
  }
}
