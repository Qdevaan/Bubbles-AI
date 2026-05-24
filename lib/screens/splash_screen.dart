import 'package:flutter/material.dart';

import 'app_bootstrap.dart';

/// Backwards-compatible alias for [AppBootstrap].
///
/// The historical SplashScreen ran its own auth/profile fetch in series with
/// [AuthGate], producing the visible splash → skeleton → home triple-load.
/// Both stages have been collapsed into [AppBootstrap], which decides the
/// destination route synchronously from the [BootStateService] mirror on the
/// first frame and runs all warmup work post-paint.
///
/// This class remains so any legacy navigation referring to `SplashScreen`
/// keeps compiling. New code should target [AppBootstrap] directly.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) => const AppBootstrap();
}
