import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/gamification_provider.dart';
import '../providers/home_provider.dart';
import '../providers/persona_provider.dart';
import '../providers/settings_provider.dart';
import '../routes/app_routes.dart';
import '../services/auth_service.dart';
import '../services/boot_state_service.dart';
import '../theme/design_tokens.dart';
import '../widgets/app_dialog.dart';

/// Unified boot widget — replaces the legacy SplashScreen + AuthGate two-stage
/// gauntlet.
///
/// The decision tree:
///   * No Supabase session  → `/login`.
///   * Session restored + persona mirror says complete/skipped + onboarding seen
///     → `/home` immediately on the first frame, no spinner.
///   * Session restored + mirror cold → branded loader while [PersonaProvider]
///     refreshes, then route based on its result.
///   * Session restored + persona mirror says incomplete → `/performa-wizard`.
///   * Session restored + onboarding mirror cold → `/onboarding`.
///
/// In every case PersonaProvider, HomeProvider, and the daily-quest call are
/// kicked off in the background after the first navigation so cached screens
/// repaint silently when fresh data arrives.
class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  bool _navigated = false;
  bool _showColdLoader = false;
  String _loaderText = 'Loading...';
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery && !_navigated) {
        _navigated = true;
        Navigator.of(context).pushReplacementNamed(AppRoutes.updatePassword);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _decideAndNavigate());
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _decideAndNavigate() async {
    if (_navigated || !mounted) return;

    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      _go(AppRoutes.login);
      return;
    }

    // Settle the auth-aware settings provider quickly — non-blocking on fail.
    unawaited(_loadSettingsSafely());

    final boot = BootStateService.instance;
    final user = Supabase.instance.client.auth.currentUser;
    final cacheMatchesUser =
        user != null && boot.lastUserId == user.id && boot.lastUserId != null;

    // Fast path: same user, persona resolved or skipped, onboarding seen.
    if (cacheMatchesUser && boot.canSkipWizard && boot.onboardingSeen) {
      _go(AppRoutes.home);
      _scheduleBackgroundWarmup();
      return;
    }

    // Cold path: still need to resolve persona before deciding the route.
    setState(() {
      _showColdLoader = true;
      _loaderText = 'Checking your account...';
    });

    // Network sanity check — informative, not blocking.
    final hasConnection = await _quickConnectivityCheck();
    if (!hasConnection && mounted) {
      await _showSettingsDialog(
        title: 'No Connectivity',
        message:
            'Internet is not available. Please enable Wi-Fi or mobile data.',
      );
    }

    if (!mounted) return;

    final profile = await AuthService.instance.getProfile();
    final hasFullName =
        profile != null && (profile['full_name']?.toString().isNotEmpty ?? false);

    if (!mounted) return;

    if (!hasFullName) {
      _go(AppRoutes.profileCompletion);
      return;
    }

    // Persona resolution — single network call, no second skeleton.
    if (mounted) {
      setState(() => _loaderText = 'Preparing your workspace...');
    }
    final persona = context.read<PersonaProvider>();
    try {
      await persona.refresh();
    } catch (_) {
      // PersonaProvider already records the error; treat as needsWizard.
    }
    if (!mounted) return;

    // Persist the user-id mirror so the next cold start hits the fast path.
    if (user != null) {
      await boot.setLastUserId(user.id);
    }

    if (persona.needsWizard && !boot.personaSkipped) {
      _go(AppRoutes.performaWizard);
      return;
    }

    if (!boot.onboardingSeen) {
      _go(AppRoutes.onboarding);
      return;
    }

    _go(AppRoutes.home);
    _scheduleBackgroundWarmup();
  }

  Future<void> _loadSettingsSafely() async {
    try {
      if (!mounted) return;
      await context.read<SettingsProvider>().loadSettings();
    } catch (_) {}
  }

  void _scheduleBackgroundWarmup() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Fire-and-forget warmups; each provider guards re-entrancy itself.
      try {
        context.read<HomeProvider>().init();
      } catch (_) {}
      try {
        context.read<GamificationProvider>().ensureDailyQuestsIssued();
      } catch (_) {}
    });
  }

  void _go(String route) {
    if (_navigated || !mounted) return;
    _navigated = true;
    Navigator.of(context).pushReplacementNamed(route);
  }

  Future<bool> _quickConnectivityCheck() async {
    try {
      final results = await Connectivity().checkConnectivity().timeout(
            const Duration(seconds: 2),
            onTimeout: () => const [ConnectivityResult.none],
          );
      return !results.contains(ConnectivityResult.none);
    } catch (_) {
      return true; // Optimistic — let the network call surface the real error.
    }
  }

  Future<void> _showSettingsDialog({
    required String title,
    required String message,
  }) async {
    await AppDialog.show<void>(
      context: context,
      title: title,
      subtitle: message,
      icon: Icons.settings_outlined,
      tone: AppDialogTone.info,
      barrierDismissible: false,
      actions: [
        AppDialogAction(
          label: 'OK',
          onTap: () => Navigator.of(context).pop(),
        ),
        AppDialogAction(
          label: 'Open Settings',
          primary: true,
          onTap: () async {
            Navigator.of(context).pop();
            await openAppSettings();
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final logoPath =
        isDark ? 'assets/logos/logo_dark.png' : 'assets/logos/logo_light.png';

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: Stack(
        children: [
          if (isDark) ...[
            Positioned(
              top: -120,
              left: -120,
              child: Container(
                width: 400,
                height: 400,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Theme.of(context).colorScheme.primary.withAlpha(38),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -120,
              right: -120,
              child: Container(
                width: 400,
                height: 400,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Theme.of(context).colorScheme.primary.withAlpha(26),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ],
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color:
                            Theme.of(context).colorScheme.primary.withAlpha(38),
                        blurRadius: 60,
                        spreadRadius: 20,
                      ),
                    ],
                  ),
                  child: Image.asset(logoPath, width: 112, height: 112),
                ),
                const SizedBox(height: 32),
                Text(
                  'BUBBLES',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w200,
                    letterSpacing: 8,
                    color: isDark ? Colors.white : AppColors.slate900,
                  ),
                ),
                const SizedBox(height: 32),
                AnimatedOpacity(
                  opacity: _showColdLoader ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 220),
                  child: SizedBox(
                    width: 180,
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.full),
                          child: LinearProgressIndicator(
                            minHeight: 3,
                            backgroundColor: isDark
                                ? AppColors.glassBorder
                                : AppColors.slate200,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        AnimatedSwitcher(
                          duration: AppDurations.dialog,
                          child: Text(
                            _loaderText,
                            key: ValueKey<String>(_loaderText),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              letterSpacing: 0.5,
                              color: isDark
                                  ? AppColors.slate400
                                  : AppColors.slate500,
                            ),
                          ),
                        ),
                      ],
                    ),
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
