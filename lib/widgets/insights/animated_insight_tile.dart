import 'package:flutter/material.dart';

// ── Animated Insight Tile (stagger fade-in) ───────────────────────────────────

class AnimatedInsightTile extends StatefulWidget {
  final int index;
  final Widget child;

  const AnimatedInsightTile({
    super.key,
    required this.index,
    required this.child,
  });

  @override
  State<AnimatedInsightTile> createState() => _AnimatedInsightTileState();
}

class _AnimatedInsightTileState extends State<AnimatedInsightTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    // Stagger: delay based on index, capped at 300ms
    final delay = Duration(milliseconds: (widget.index * 50).clamp(0, 300));
    Future.delayed(delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _slide,
        child: widget.child,
      ),
    );
  }
}
