import 'dart:math';
import 'package:flutter/material.dart';

/// Animated floating-orb ambient background that shifts colors by time of day.
/// Used as the base layer behind HomeScreen and Game Center content.
class AnimatedAmbientBackground extends StatefulWidget {
  final bool isDark;
  final ScrollController? scrollController;

  const AnimatedAmbientBackground({
    super.key,
    required this.isDark,
    this.scrollController,
  });

  @override
  State<AnimatedAmbientBackground> createState() =>
      _AnimatedAmbientBackgroundState();
}

class _AnimatedAmbientBackgroundState extends State<AnimatedAmbientBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  double _scrollOffset = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
    widget.scrollController?.addListener(_onScroll);
  }

  void _onScroll() {
    if (widget.scrollController != null) {
      setState(() =>
          _scrollOffset = widget.scrollController!.offset.clamp(0, 400));
    }
  }

  @override
  void dispose() {
    widget.scrollController?.removeListener(_onScroll);
    _ctrl.dispose();
    super.dispose();
  }

  /// Returns a color palette based on current hour.
  static List<Color> _paletteForHour(int hour, bool isDark) {
    if (!isDark) {
      // Light-mode: soft pastels that still animate
      if (hour < 6) {
        return [
          const Color(0x1A1E3A5F),
          const Color(0x1A6366F1),
          const Color(0x1AA855F7),
        ];
      }
      if (hour < 12) {
        return [
          const Color(0x1AFBBF24),
          const Color(0x1AF97316),
          const Color(0x1AEF4444),
        ];
      }
      if (hour < 17) {
        return [
          const Color(0x1A13BDEC),
          const Color(0x1A6366F1),
          const Color(0x1A22C55E),
        ];
      }
      return [
        const Color(0x1AA855F7),
        const Color(0x1AEC4899),
        const Color(0x1A6366F1),
      ];
    }

    // Dark-mode — richer, deeper tones
    if (hour < 6) {
      // Night → deep blue + indigo
      return [
        const Color(0x261E3A5F),
        const Color(0x266366F1),
        const Color(0x20A855F7),
      ];
    }
    if (hour < 12) {
      // Morning → warm amber + coral
      return [
        const Color(0x26FBBF24),
        const Color(0x26F97316),
        const Color(0x20EF4444),
      ];
    }
    if (hour < 17) {
      // Afternoon → teal + cyan (brand)
      return [
        const Color(0x2613BDEC),
        const Color(0x266366F1),
        const Color(0x2022C55E),
      ];
    }
    // Evening → purple + pink
    return [
      const Color(0x26A855F7),
      const Color(0x26EC4899),
      const Color(0x206366F1),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = _paletteForHour(DateTime.now().hour, widget.isDark);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => CustomPaint(
        painter: _OrbPainter(
          progress: _ctrl.value,
          colors: colors,
          scrollOffset: _scrollOffset,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  final double progress;
  final List<Color> colors;
  final double scrollOffset;

  _OrbPainter({
    required this.progress,
    required this.colors,
    required this.scrollOffset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final orbs = <_Orb>[
      _Orb(
        baseX: 0.2,
        baseY: 0.15,
        radius: size.width * 0.55,
        phaseX: 0,
        phaseY: 0,
        color: colors[0],
      ),
      _Orb(
        baseX: 0.8,
        baseY: 0.35,
        radius: size.width * 0.45,
        phaseX: pi / 3,
        phaseY: pi / 4,
        color: colors.length > 1 ? colors[1] : colors[0],
      ),
      _Orb(
        baseX: 0.4,
        baseY: 0.75,
        radius: size.width * 0.50,
        phaseX: pi / 2,
        phaseY: pi / 6,
        color: colors.length > 2 ? colors[2] : colors[0],
      ),
    ];

    for (final orb in orbs) {
      final dx = size.width * orb.baseX +
          sin(progress * 2 * pi + orb.phaseX) * size.width * 0.06;
      final dy = size.height * orb.baseY +
          cos(progress * 2 * pi + orb.phaseY) * size.height * 0.04 -
          scrollOffset * 0.12; // parallax

      final paint = Paint()
        ..shader = RadialGradient(
          colors: [orb.color, orb.color.withAlpha(0)],
        ).createShader(
          Rect.fromCircle(center: Offset(dx, dy), radius: orb.radius),
        );

      canvas.drawCircle(Offset(dx, dy), orb.radius, paint);
    }
  }

  @override
  bool shouldRepaint(_OrbPainter old) =>
      old.progress != progress || old.scrollOffset != scrollOffset;
}

class _Orb {
  final double baseX, baseY, radius, phaseX, phaseY;
  final Color color;

  const _Orb({
    required this.baseX,
    required this.baseY,
    required this.radius,
    required this.phaseX,
    required this.phaseY,
    required this.color,
  });
}
