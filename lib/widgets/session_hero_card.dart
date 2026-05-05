import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/design_tokens.dart';

class _ScanlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withAlpha(8)
      ..strokeWidth = 1;
    for (double y = 0; y < size.height; y += 2) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_ScanlinePainter old) => false;
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

    final glowColor = isConnected ? connectedColor : AppColors.slate500;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedBuilder(
        animation: breatheAnimation,
        builder: (context, _) {
          final glow = breatheAnimation.value;
          return Container(
            height: 200,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [AppColors.slate900, primary.withAlpha(180)]
                    : [Colors.white.withAlpha(230), primary.withAlpha(60)],
              ),
              border: Border.all(
                color: glowColor.withAlpha((80 + (glow * 120)).round()),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: glowColor.withAlpha((20 + (glow * 40)).round()),
                  blurRadius: 20 + (glow * 10),
                  spreadRadius: -2,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(painter: _ScanlinePainter()),
                  ),
                  Positioned(
                    top: 16,
                    right: 16,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isConnected ? connectedColor : AppColors.error,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          isConnected ? 'Connected' : 'No connection',
                          style: GoogleFonts.manrope(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: isDark ? AppColors.slate400 : AppColors.slate500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Start Session',
                          style: GoogleFonts.manrope(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white : AppColors.slate900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Tap to begin',
                          style: GoogleFonts.manrope(
                            fontSize: 13,
                            color: isDark ? AppColors.slate400 : AppColors.slate500,
                          ),
                        ),
                      ],
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
