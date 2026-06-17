// Purpose: Thin alias for AppBootstrap — kept so legacy navigation references to SplashScreen keep compiling.
import 'package:flutter/material.dart';

import 'app_bootstrap.dart';

// Thin alias for AppBootstrap — keeps legacy navigation references compiling.
// Any new code should target AppBootstrap directly.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) => const AppBootstrap();
}
