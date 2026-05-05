import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/design_tokens.dart';

class _ScanlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withAlpha(6)
      ..strokeWidth = 1;
    for (double y = 0; y < size.height; y += 3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_ScanlinePainter old) => false;
}

class _WaveRingPainter extends CustomPainter {
  final double progress;
  final Color color;

  _WaveRingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    for (int i = 0; i < 3; i++) {
      final phase = (progress + i * 0.33) % 1.0;
      final radius = 28 + phase * 60;
      final opacity = (1.0 - phase) * 0.35;
      final paint = Paint()
        ..color = color.withAlpha((opacity * 255).round())
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(Offset(cx, cy), radius, paint);
    }
  }

  @override
  bool shouldRepaint(_WaveRingPainter old) => old.progress != progress;
}

class _GridDotsPainter extends CustomPainter {
  final Color color;

  _GridDotsPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withAlpha(30);
    const spacing = 20.0;
    for (double x = spacing; x < size.width; x += spacing) {
      for (double y = spacing; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.5, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_GridDotsPainter old) => false;
}

class SessionHeroCard extends StatelessWidget {
  final bool isConnected;
  final Animation<double> breatheAnimation;
  final VoidCallback onTap;

  const SessionHeroCard({
    super.key,
    required this.isConnected,
    required this.breatheAnimation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    const connectedColor = Color(0xFF10B981);
    const disconnectedColor = Color(0xFFF43F5E);

    final statusColor = isConnected ? connectedColor : disconnectedColor;
    final glowColor = isConnected ? connectedColor : primary;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedBuilder(
        animation: breatheAnimation,
        builder: (context, _) {
          final t = breatheAnimation.value;
          return Container(
            height: 188,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [
                        const Color(0xFF0F1E2E),
                        Color.lerp(const Color(0xFF0D2137), primary.withAlpha(180), 0.6)!,
                        primary.withAlpha(100),
                      ]
                    : [
                        Colors.white,
                        primary.withAlpha(40),
                        primary.withAlpha(80),
                      ],
                stops: const [0.0, 0.55, 1.0],
              ),
              border: Border.all(
                color: glowColor.withAlpha((60 + (t * 140)).round()),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: glowColor.withAlpha((15 + (t * 50)).round()),
                  blurRadius: 24 + t * 16,
                  spreadRadius: -4,
                ),
                BoxShadow(
                  color: glowColor.withAlpha((8 + (t * 20)).round()),
                  blurRadius: 48,
                  spreadRadius: -8,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                children: [
                  // Scanlines texture
                  Positioned.fill(
                    child: CustomPaint(painter: _ScanlinePainter()),
                  ),
                  // Dot grid
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _GridDotsPainter(color: glowColor),
                    ),
                  ),
                  // Large ambient glow orb (top-right)
                  Positioned(
                    right: -40,
                    top: -40,
                    child: Container(
                      width: 180,
                      height: 180,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            glowColor.withAlpha((60 + (t * 30)).round()),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Wave rings emanating from center-left
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    right: 0,
                    child: CustomPaint(
                      painter: _WaveRingPainter(
                        progress: t,
                        color: glowColor,
                      ),
                    ),
                  ),
                  // Status badge — top left
                  Positioned(
                    top: 14,
                    left: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withAlpha(isDark ? 40 : 30),
                        borderRadius: BorderRadius.circular(AppRadius.full),
                        border: Border.all(
                          color: statusColor.withAlpha(120),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Pulsing dot
                          AnimatedBuilder(
                            animation: breatheAnimation,
                            builder: (_, __) => Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: statusColor,
                                boxShadow: [
                                  BoxShadow(
                                    color: statusColor.withAlpha(
                                        (80 + (t * 120)).round()),
                                    blurRadius: 6,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isConnected ? 'LIVE' : 'OFFLINE',
                            style: GoogleFonts.manrope(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Waveform bars — top right decorative
                  Positioned(
                    top: 14,
                    right: 16,
                    child: _WaveformBars(
                      isActive: isConnected,
                      color: glowColor,
                      breathe: t,
                    ),
                  ),
                  // Main content center
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Icon circle
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: glowColor.withAlpha((30 + (t * 20)).round()),
                            border: Border.all(
                              color: glowColor.withAlpha((100 + (t * 80)).round()),
                              width: 1.5,
                            ),
                          ),
                          child: Icon(
                            isConnected
                                ? Icons.mic_rounded
                                : Icons.mic_off_rounded,
                            color: isConnected
                                ? glowColor
                                : (isDark ? AppColors.slate400 : AppColors.slate500),
                            size: 26,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          isConnected ? 'Start Session' : 'Not Connected',
                          style: GoogleFonts.manrope(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white : AppColors.slate900,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isConnected
                              ? 'Tap to begin your wingman session'
                              : 'Connect to start a new session',
                          style: GoogleFonts.manrope(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: isDark ? AppColors.slate400 : AppColors.slate500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Bottom shimmer line
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 2,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            glowColor.withAlpha((80 + (t * 100)).round()),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _WaveformBars extends StatelessWidget {
  final bool isActive;
  final Color color;
  final double breathe;

  const _WaveformBars({
    required this.isActive,
    required this.color,
    required this.breathe,
  });

  @override
  Widget build(BuildContext context) {
    final heights = isActive
        ? [8.0, 14.0, 10.0, 18.0, 12.0, 16.0, 9.0]
        : [4.0, 4.0, 4.0, 4.0, 4.0, 4.0, 4.0];

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(heights.length, (i) {
        final phase = math.sin((breathe * math.pi * 2) + i * 0.6);
        final h = isActive ? heights[i] + phase * 4 : heights[i];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1.5),
          child: Container(
            width: 3,
            height: h.clamp(3.0, 22.0),
            decoration: BoxDecoration(
              color: color.withAlpha(isActive ? 160 : 60),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }
}
