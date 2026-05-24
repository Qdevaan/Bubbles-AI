/// Visual style applied to surfaces (cards, sheets, dialogs, the bottom nav).
///
/// * [glass] — translucent surfaces with `BackdropFilter` blur. Premium look
///   but expensive on low-end GPUs (each surface forces an offscreen pass).
/// * [solid] — opaque Material surfaces with hairline elevation. ~4 ms/frame
///   cheaper on low-end devices and visually consistent.
///
/// The active style is read from [ThemeProvider.effectiveSurfaceStyle], which
/// honours the user's explicit override first and falls back to a
/// [DevicePerfTier] heuristic (low-tier → solid, mid/high → glass).
enum SurfaceStyle { glass, solid }

extension SurfaceStyleX on SurfaceStyle {
  bool get useBlur => this == SurfaceStyle.glass;

  String get persistedValue {
    switch (this) {
      case SurfaceStyle.glass:
        return 'glass';
      case SurfaceStyle.solid:
        return 'solid';
    }
  }

  static SurfaceStyle fromPersisted(String? value) {
    switch (value) {
      case 'solid':
        return SurfaceStyle.solid;
      case 'glass':
        return SurfaceStyle.glass;
      default:
        return SurfaceStyle.glass;
    }
  }
}
