import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/design_tokens.dart';
import 'pulse_dot.dart';

// ── Entity Orb ─────────────────────────────────────────────────────────────

class EntityOrb extends StatefulWidget {
  final bool isConnected;
  final AnimationController breatheAnimation;
  final VoidCallback onTap;

  const EntityOrb({
    super.key,
    required this.isConnected,
    required this.breatheAnimation,
    required this.onTap,
  });

  @override
  State<EntityOrb> createState() => _EntityOrbState();
}

class _EntityOrbState extends State<EntityOrb> with SingleTickerProviderStateMixin {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Text(
              "Ready to talk?",
              style: GoogleFonts.manrope(
                fontSize: 16, letterSpacing: 0.5, fontWeight: FontWeight.w600,
                color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: widget.breatheAnimation,
            builder: (_, child) {
              final scale = 1.0 + (widget.breatheAnimation.value * 0.08);
              return Transform.scale(scale: _pressed ? 0.95 : scale, child: child);
            },
            child: GestureDetector(
              onTapDown: (_) => setState(() => _pressed = true),
              onTapUp: (_) { setState(() => _pressed = false); widget.onTap(); },
              onTapCancel: () => setState(() => _pressed = false),
              child: Container(
                width: 170, height: 170,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [primary.withAlpha(isDark ? 255 : 200), primary.withAlpha(isDark ? 80 : 40), Colors.transparent],
                    stops: const [0.4, 0.8, 1.0],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: primary.withAlpha(widget.isConnected ? 120 : 60),
                      blurRadius: widget.isConnected ? 60 : 30,
                      spreadRadius: widget.isConnected ? 10 : -10,
                    )
                  ],
                ),
                child: Center(
                  child: Container(
                    width: 76, height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDark ? const Color(0xFF0F172A) : Colors.white,
                      border: Border.all(color: primary.withAlpha(100), width: 2),
                      boxShadow: [BoxShadow(color: Colors.black.withAlpha(20), blurRadius: 10)],
                    ),
                    child: Center(
                      child: Icon(
                        widget.isConnected ? Icons.graphic_eq_rounded : Icons.mic_rounded,
                        size: 32, color: primary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.isConnected) const PulseDot() else const Icon(Icons.circle, color: Color(0xFFEF4444), size: 8),
                const SizedBox(width: 8),
                Text(
                  widget.isConnected ? 'ACTIVE' : 'TAP TO CONNECT',
                  style: GoogleFonts.manrope(
                    fontSize: 11, fontWeight: FontWeight.w700,
                    color: widget.isConnected ? primary : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
