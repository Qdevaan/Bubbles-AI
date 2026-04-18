import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/design_tokens.dart';

/// Circular XP progress ring that wraps around the user's avatar.
/// Shows level progress as an animated arc segment with a level badge overlay.
class XpProgressRing extends StatefulWidget {
  final double progress; // 0.0 – 1.0
  final int level;
  final Widget child; // avatar content
  final double size;

  const XpProgressRing({
    super.key,
    required this.progress,
    required this.level,
    required this.child,
    this.size = 48,
  });

  @override
  State<XpProgressRing> createState() => _XpProgressRingState();
}

class _XpProgressRingState extends State<XpProgressRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _progressAnim;
  double _prevProgress = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: AppDurations.xpCountUp,
    );
    _progressAnim = Tween(begin: 0.0, end: widget.progress)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
    _prevProgress = widget.progress;
  }

  @override
  void didUpdateWidget(XpProgressRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.progress != _prevProgress) {
      _progressAnim = Tween(begin: _prevProgress, end: widget.progress)
          .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
      _ctrl
        ..reset()
        ..forward();
      _prevProgress = widget.progress;
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

    return SizedBox(
      width: widget.size + 8,
      height: widget.size + 8,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Ring
          AnimatedBuilder(
            animation: _progressAnim,
            builder: (_, __) => CustomPaint(
              size: Size(widget.size + 8, widget.size + 8),
              painter: _RingPainter(
                progress: _progressAnim.value,
                ringColor: Theme.of(context).colorScheme.primary,
                trackColor:
                    isDark ? Colors.white.withAlpha(20) : Colors.grey.shade200,
              ),
            ),
          ),
          // Avatar
          SizedBox(
            width: widget.size - 2,
            height: widget.size - 2,
            child: ClipOval(child: widget.child),
          ),
          // Level badge
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: AppColors.levelBadge,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark
                      ? AppColors.backgroundDark
                      : AppColors.backgroundLight,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.levelBadge.withAlpha(80),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  '${widget.level}',
                  style: GoogleFonts.manrope(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color ringColor;
  final Color trackColor;

  _RingPainter({
    required this.progress,
    required this.ringColor,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 2;

    // Track
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    // Progress arc
    if (progress > 0) {
      final sweepAngle = 2 * pi * progress.clamp(0.0, 1.0);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2, // start from top
        sweepAngle,
        false,
        Paint()
          ..color = ringColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.ringColor != ringColor;
}
