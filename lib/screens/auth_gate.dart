import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/persona_provider.dart';

/// Post-login routing gate.
///
/// Refreshes [PersonaProvider] once and then redirects:
///   * `/performa-wizard` — if the user has no persona row, or the row
///     exists but has not been completed (`completed_at` is null).
///   * `/home`            — if the persona is fully completed.
///
/// Combined with [PerformaWizardScreen]'s `PopScope(canPop: false)`,
/// this gives us a hard block: a freshly-signed-in user with no persona
/// cannot reach the rest of the app until the wizard is finished.
///
/// AuthGate assumes the user is already authenticated. It is intended to
/// be the destination after `LoginScreen`, `SignupScreen`,
/// `ProfileCompletionScreen`, and the splash's logged-in branch.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _decided = false;

  @override
  void initState() {
    super.initState();
    // Defer one frame so the Navigator is mounted before we push.
    WidgetsBinding.instance.addPostFrameCallback((_) => _decideRoute());
  }

  Future<void> _decideRoute() async {
    if (_decided || !mounted) return;
    final persona = context.read<PersonaProvider>();
    try {
      await persona.refresh();
    } catch (_) {
      // Refresh errors are surfaced by PersonaProvider.error; even on
      // failure we route to the wizard so the user is never stranded
      // on a blank gate. PersonaProvider.needsWizard is true when
      // _persona is null (which is the case after a failed fetch too).
    }
    if (!mounted || _decided) return;
    _decided = true;
    final route = persona.needsWizard ? '/performa-wizard' : '/home';
    Navigator.of(context).pushReplacementNamed(route);
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
