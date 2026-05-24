import 'package:flutter/material.dart';

import 'motion_scope.dart';

/// Silent stale-while-revalidate indicator.
///
/// A row of three small dots that pulse opacity while a background refresh
/// is in-flight. Renders nothing when [visible] is false so providers can
/// hand it the same bool they already drive their main UI from.
///
/// Designed to sit directly under the AppBar so the user sees a refresh is
/// happening without losing the cached content they were reading.
class RefreshPulse extends StatefulWidget {
  final bool visible;
  final EdgeInsets padding;

  const RefreshPulse({
    super.key,
    required this.visible,
    this.padding = const EdgeInsets.fromLTRB(20, 4, 20, 4),
  });

  @override
  State<RefreshPulse> createState() => _RefreshPulseState();
}

class _RefreshPulseState extends State<RefreshPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.visible) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant RefreshPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    } else if (!widget.visible && _ctrl.isAnimating) {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) return const SizedBox.shrink();
    final reduce = MotionScope.reduceMotion(context);
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: widget.padding,
      child: SizedBox(
        height: 8,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (i) {
            return AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) {
                final phase = (_ctrl.value + i * 0.25) % 1.0;
                final opacity = reduce ? 0.7 : (0.25 + 0.65 * phase);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: primary.withValues(alpha: opacity),
                    ),
                  ),
                );
              },
            );
          }),
        ),
      ),
    );
  }
}
