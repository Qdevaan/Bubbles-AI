import 'package:flutter/material.dart';

import '../services/device_perf_tier.dart';

/// Resolved motion preferences for a subtree.
///
/// Reads `MediaQuery.disableAnimations` (OS-level reduce-motion) and the
/// active [DevicePerfTier]. Widgets that would otherwise hand-pick a
/// `Duration` or [Curve] consult [MotionScope.of] so the values automatically
/// degrade on low-tier devices and disappear entirely when reduce-motion is
/// enabled.
class MotionScope {
  MotionScope._();

  /// Returns a duration clamped to the active perf tier and zeroed when
  /// reduce-motion is on.
  static Duration duration(BuildContext context, Duration requested) {
    if (MediaQuery.of(context).disableAnimations) return Duration.zero;
    final cap = DevicePerfTier.instance.animationCap;
    return requested > cap ? cap : requested;
  }

  /// Substitutes expensive cubic curves with cheaper alternatives on
  /// low-tier devices. `Curves.elasticOut` and `Curves.bounceOut` are CPU
  /// hot-spots; `easeOutBack` is visually similar but evaluates in fewer
  /// multiplications.
  static Curve curve(BuildContext context, Curve requested) {
    if (DevicePerfTier.instance.tier == PerfTier.low) {
      if (requested == Curves.elasticOut) return Curves.easeOutBack;
      if (requested == Curves.bounceOut) return Curves.easeOut;
    }
    return requested;
  }

  /// True when animations should be suppressed (used by skeleton shimmer to
  /// fall back to an opacity pulse).
  static bool reduceMotion(BuildContext context) {
    return MediaQuery.of(context).disableAnimations ||
        DevicePerfTier.instance.tier == PerfTier.low;
  }
}
