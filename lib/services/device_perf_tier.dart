import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'boot_state_service.dart';

/// Classification of the host device's render-budget capacity.
///
/// * [low]  — 2 GB RAM or less, software GPU, < 60 Hz. Heavy blurs / long
///            animations cause visible jank. Default to [SurfaceStyle.solid]
///            and capped animation durations.
/// * [mid]  — 3–4 GB RAM, 60 Hz hardware GPU. Blur acceptable at lower
///            sigmas; full animation durations.
/// * [high] — 6 GB+ RAM, 90 Hz+ display. Full glassmorphism + animations.
enum PerfTier { low, mid, high }

class DevicePerfTier {
  DevicePerfTier._();
  static final DevicePerfTier instance = DevicePerfTier._();

  PerfTier _tier = PerfTier.high;
  PerfTier get tier => _tier;

  bool _detected = false;

  /// Coarse-grained timings for tuning animations and shimmer cost.
  Duration get animationCap {
    switch (_tier) {
      case PerfTier.low:
        return const Duration(milliseconds: 200);
      case PerfTier.mid:
        return const Duration(milliseconds: 350);
      case PerfTier.high:
        return const Duration(milliseconds: 500);
    }
  }

  /// Multiplier applied to BackdropFilter sigmas so mid-tier devices use a
  /// cheaper blur than high-tier without dropping the glass aesthetic.
  double get blurScale {
    switch (_tier) {
      case PerfTier.low:
        return 0.0; // solid mode anyway, but defensive
      case PerfTier.mid:
        return 0.5;
      case PerfTier.high:
        return 1.0;
    }
  }

  /// Loads cached tier from prefs (if present) and runs a fresh classification
  /// in the background. Safe to call multiple times — only the first call
  /// performs work.
  Future<void> detect() async {
    if (_detected) return;
    _detected = true;

    final cached = BootStateService.instance.perfTier;
    if (cached != null) {
      _tier = _fromString(cached);
    }

    try {
      final fresh = await _classify();
      if (fresh != _tier) {
        _tier = fresh;
        await BootStateService.instance.setPerfTier(_tier.name);
      } else if (cached == null) {
        await BootStateService.instance.setPerfTier(_tier.name);
      }
    } catch (e) {
      debugPrint('DevicePerfTier.detect: $e');
    }
  }

  /// Wires a first-frame timings callback. If the first 10 frames average
  /// above 18 ms (i.e. consistently dropping below 60 fps), the tier is
  /// downgraded one step.
  void observeFirstFrames(BuildContext context) {
    int frameCount = 0;
    int totalMicros = 0;
    late TimingsCallback callback;
    callback = (List<FrameTiming> timings) {
      for (final t in timings) {
        totalMicros += t.totalSpan.inMicroseconds;
        frameCount += 1;
      }
      if (frameCount >= 10) {
        WidgetsBinding.instance.removeTimingsCallback(callback);
        final avgMs = (totalMicros / frameCount) / 1000.0;
        if (avgMs > 18 && _tier != PerfTier.low) {
          _tier = _tier == PerfTier.high ? PerfTier.mid : PerfTier.low;
          BootStateService.instance.setPerfTier(_tier.name);
        }
      }
    };
    WidgetsBinding.instance.addTimingsCallback(callback);
  }

  Future<PerfTier> _classify() async {
    final info = DeviceInfoPlugin();
    if (kIsWeb) {
      return PerfTier.mid;
    }
    if (Platform.isAndroid) {
      final android = await info.androidInfo;
      final sdk = android.version.sdkInt;
      final lowRam = android.isLowRamDevice;
      if (lowRam || sdk < 26) return PerfTier.low;
      if (sdk >= 31) return PerfTier.high;
      return PerfTier.mid;
    }
    if (Platform.isIOS) {
      final ios = await info.iosInfo;
      final model = (ios.utsname.machine).toLowerCase();
      // Pre-A12 devices (iPhone X and older) downgrade to mid; the rest stay
      // high. iPad models are conservatively treated as high tier.
      if (model.startsWith('iphone8') ||
          model.startsWith('iphone9') ||
          model.startsWith('iphone10')) {
        return PerfTier.mid;
      }
      return PerfTier.high;
    }
    return PerfTier.high;
  }

  PerfTier _fromString(String name) {
    return PerfTier.values.firstWhere(
      (t) => t.name == name,
      orElse: () => PerfTier.high,
    );
  }
}
