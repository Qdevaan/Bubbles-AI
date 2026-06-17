// Purpose: Auth gate widget — listens to Supabase auth state changes and redirects between login and home accordingly.
import 'package:flutter/material.dart';

import 'app_bootstrap.dart';

/// Post-login routing gate.
///
/// Delegates to [AppBootstrap] so a freshly-signed-in user follows the same
/// fast-path decision tree as a cold launch:
///   * If [PersonaProvider] / [BootStateService] indicate the wizard is
///     unfinished and was not skipped → `/performa-wizard`.
///   * Otherwise → `/home` (or `/onboarding` if the tutorial hasn't run).
///
/// AuthGate assumes the user is already authenticated. It is intended to be
/// the destination after [LoginScreen] and [SignupScreen]. Cold launches go
/// through [AppBootstrap] directly without ever rendering this widget.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) => const AppBootstrap();
}
