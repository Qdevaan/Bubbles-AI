import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/design_tokens.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../services/auth_service.dart';
import '../utils/permissions_util.dart';
import '../widgets/glass_morphism.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  double _progress = 0.0;
  String _loadingText = 'Loading...';
  String? _targetRoute;
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();
    _startInitialization();
  }

  Future<void> _startInitialization() async {
    try {
      // Short delay to let the UI render first
      await Future.delayed(AppDurations.normal);

      if (mounted) {
        setState(() {
          _progress = 0.3;
          _loadingText = 'Loading...';
        });
      }

      if (mounted) {
        setState(() {
          _progress = 0.6;
          _loadingText = 'Connecting...';
        });
      }
      
      try {
        await _checkConnectivity();
      } catch (e) {
        debugPrint('Connectivity error: $e');
      }

      if (mounted) {
        setState(() {
          _progress = 0.8;
        });
      }
      
      try {
        await _determineAuthState();
      } catch (e) {
        debugPrint('Auth error: $e');
        _targetRoute = '/login';
      }
    } catch (e) {
      debugPrint('Initialization error: $e');
      _targetRoute ??= '/login';
    } finally {
      if (mounted) {
        setState(() {
          _progress = 1.0;
        });
        
        // Failsafe in case animation callback doesn't fire
        Future.delayed(AppDurations.normal, () {
          if (mounted && !_hasNavigated) {
            _onLoadingComplete();
          }
        });
      }
    }
  }

  Future<void> _checkConnectivity() async {
    final results = await Connectivity().checkConnectivity();
    final hasConnection = !results.contains(ConnectivityResult.none);

    if (!hasConnection && mounted) {
      await _showSettingsDialog(
        title: 'No Connectivity',
        message:
            'Internet is not available. Please enable Wi-Fi or mobile data.',
      );
    }
  }

  Future<void> _determineAuthState() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      final profile = await AuthService.instance.getProfile();
      final isComplete = profile != null && (profile['full_name']?.toString().isNotEmpty ?? false);

      if (mounted) {
        await PermissionsUtil.requestStartupPermissions(context);
        try {
          if (mounted) {
            await Provider.of<SettingsProvider>(context, listen: false).loadSettings();
          }
        } catch (_) {}
      }

      _targetRoute = isComplete ? '/home' : '/profile-completion';
    } else {
      _targetRoute = '/login';
    }

    // Simulate extra loading time for visual effect (optional)
    await Future.delayed(AppDurations.normal);
  }

  void _onLoadingComplete() {
    if (!mounted || _targetRoute == null || _hasNavigated) return;

    _hasNavigated = true;
    // Once the bar finishes filling to 1.0, navigate
    context.go(_targetRoute!);
  }

  Future<void> _showSettingsDialog({
    required String title,
    required String message,
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => GlassDialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withAlpha(26),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Theme.of(context).colorScheme.primary.withAlpha(51)),
                        ),
                        child: Icon(Icons.settings_outlined, color: Theme.of(context).colorScheme.primary, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : AppColors.slate900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? AppColors.slate400 : AppColors.slate600,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: Text(
                          'OK',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: isDark ? AppColors.slate400 : AppColors.slate500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () async {
                          Navigator.of(ctx).pop();
                          await openAppSettings();
                        },
                        style: TextButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary.withAlpha(38),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.full),
                          ),
                        ),
                        child: Text(
                          'Open Settings',
                          style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final logoPath = isDark
        ? 'assets/logos/logo_dark.png'
        : 'assets/logos/logo_light.png';

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: Stack(
        children: [
          // Mesh gradient background
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
                    colors: [Theme.of(context).colorScheme.primary.withAlpha(38), Colors.transparent],
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
                    colors: [Theme.of(context).colorScheme.primary.withAlpha(26), Colors.transparent],
                  ),
                ),
              ),
            ),
          ],
          // Center content
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo with glow
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).colorScheme.primary.withAlpha(38),
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
                SizedBox(
                  width: 180,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0.0, end: _progress),
                      duration: AppDurations.normal,
                      builder: (context, value, _) {
                        return LinearProgressIndicator(
                          value: value,
                          minHeight: 3,
                          backgroundColor: isDark
                              ? AppColors.glassBorder
                              : AppColors.slate200,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Theme.of(context).colorScheme.primary,
                          ),
                        );
                      },
                      onEnd: () {
                        if (_progress >= 1.0) {
                          _onLoadingComplete();
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                AnimatedSwitcher(
                  duration: AppDurations.dialog,
                  child: Text(
                    _loadingText,
                    key: ValueKey<String>(_loadingText),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0.5,
                      color: isDark ? AppColors.slate400 : AppColors.slate500,
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
