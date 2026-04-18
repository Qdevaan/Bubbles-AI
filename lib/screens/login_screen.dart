import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/theme_provider.dart';
import '../theme/design_tokens.dart';
import '../services/auth_service.dart';
import '../utils/permissions_util.dart';
import '../widgets/app_button.dart';
import '../widgets/app_input.dart';
import '../widgets/social_button.dart';
import '../widgets/app_logo.dart';
import '../widgets/glass_morphism.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _authService = AuthService.instance;
  final _formKey = GlobalKey<FormState>();

  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _isEmailLoading = false;
  bool _isGoogleLoading = false;
  late final StreamSubscription<AuthState> _authSubscription;

  @override
  void initState() {
    super.initState();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      data,
    ) async {
      if (data.event == AuthChangeEvent.signedIn && data.session != null) {
        if (!_isEmailLoading && mounted) {
          await _handlePostLogin();
        }
      }
    });
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkAndShowThemeDialog() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSelectedTheme = prefs.getBool('has_selected_theme') ?? false;
    if (!hasSelectedTheme) {
      await _showThemeSelectionDialog();
      await prefs.setBool('has_selected_theme', true);
    }
  }

  Future<void> _showThemeSelectionDialog() async {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    await showDialog(
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
                        child: Icon(Icons.palette_outlined, color: Theme.of(context).colorScheme.primary, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Select Theme',
                        style: GoogleFonts.manrope(
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                          color: isDark ? Colors.white : AppColors.slate900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildThemeListTile(ctx, themeProvider, isDark,
                      icon: Icons.brightness_auto,
                      label: 'System Default',
                      mode: ThemeMode.system),
                  _buildThemeListTile(ctx, themeProvider, isDark,
                      icon: Icons.light_mode,
                      label: 'Light',
                      mode: ThemeMode.light),
                  _buildThemeListTile(ctx, themeProvider, isDark,
                      icon: Icons.dark_mode,
                      label: 'Dark',
                      mode: ThemeMode.dark),
                ],
              ),
      ),
    );
  }

  Widget _buildThemeListTile(
    BuildContext ctx,
    ThemeProvider themeProvider,
    bool isDark, {
    required IconData icon,
    required String label,
    required ThemeMode mode,
  }) {
    final isSelected = themeProvider.themeMode == mode;
    return GestureDetector(
      onTap: () {
        themeProvider.setThemeMode(mode);
        Navigator.pop(ctx);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).colorScheme.primary.withAlpha(26) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Theme.of(context).colorScheme.primary.withAlpha(76) : (isDark ? Colors.white10 : Colors.black12),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? Theme.of(context).colorScheme.primary : (isDark ? Colors.white70 : Colors.black87),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.manrope(
                  fontSize: 15,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? Theme.of(context).colorScheme.primary : (isDark ? Colors.white : Colors.black87),
                ),
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle_rounded, color: Theme.of(context).colorScheme.primary, size: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _handlePostLogin() async {
    final profile = await _authService.getProfile();
    final isComplete = profile != null && (profile['full_name']?.toString().isNotEmpty ?? false);

    if (mounted) {
      await PermissionsUtil.requestStartupPermissions(context);
    }
    
    if (mounted) {
      await _checkAndShowThemeDialog();
    }
    
    if (mounted) {
      Navigator.pushReplacementNamed(context, isComplete ? '/home' : '/profile-completion');
    }
  }

  void _showForgotPasswordSheet(BuildContext context) {
    final emailCtrl = TextEditingController(text: _emailCtrl.text.trim());
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String? inlineError;
    bool sending = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: GlassBottomSheet(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.glassBorder : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    'Reset Password',
                  style: GoogleFonts.manrope(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : AppColors.slate900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Enter your email and we\'ll send a reset link.',
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    color: AppColors.slate400,
                  ),
                ),
                const SizedBox(height: 20),
                AppInput(
                  controller: emailCtrl,
                  label: 'Email',
                  prefixIcon: Icons.email_outlined,
                  type: TextInputType.emailAddress,
                  hintText: 'your@email.com',
                ),
                if (inlineError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    inlineError!,
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      color: AppColors.error,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                AppButton(
                  label: 'Send Reset Link',
                  icon: Icons.send_rounded,
                  filled: true,
                  loading: sending,
                  onTap: () async {
                    final email = emailCtrl.text.trim();
                    if (email.isEmpty || !email.contains('@')) {
                      setSheetState(() => inlineError = 'Enter a valid email address.');
                      return;
                    }
                    setSheetState(() { sending = true; inlineError = null; });
                    try {
                      await _authService.resetPasswordForEmail(email);
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Password reset link sent — check your inbox.'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    } catch (e) {
                      final msg = e.toString().toLowerCase();
                      setSheetState(() {
                        sending = false;
                        if (msg.contains('rate') || msg.contains('too many')) {
                          inlineError = 'Reset email already sent. Please wait a few minutes.';
                        } else {
                          inlineError = 'Could not send reset email. Check your connection.';
                        }
                      });
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  }

  Future<void> _loginWithEmail() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isEmailLoading = true);
    try {
      await _authService.signInWithEmail(
        _emailCtrl.text.trim(),
        _passCtrl.text,
      );
      if (mounted) {
        await _handlePostLogin();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception:', '').trim()),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() => _isEmailLoading = false);
      }
    }
  }

  Future<void> _loginWithGoogle() async {
    setState(() => _isGoogleLoading = true);
    try {
      await _authService.signInWithGoogle();
      // Loading state will be cleared by the auth listener on sign-in
      if (mounted) setState(() => _isGoogleLoading = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Google Sign in failed: $e')));
        setState(() => _isGoogleLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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

          // Main Content
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 60),

                    // Header — Logo + Title
                    Column(
                      children: [
                        const AppLogo(size: 80),
                        const SizedBox(height: 16),
                        Text(
                          'Welcome Back',
                          style: GoogleFonts.manrope(
                            fontSize: 36,
                            fontWeight: FontWeight.w200,
                            color: isDark ? Colors.white : AppColors.slate900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Your premium AI Wingman & Consultant',
                          style: GoogleFonts.manrope(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: AppColors.slate400,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 40),

                    // Form Fields
                    AppInput(
                      controller: _emailCtrl,
                      label: 'Email',
                      prefixIcon: Icons.email_outlined,
                      type: TextInputType.emailAddress,
                      hintText: 'Enter your email',
                      validator: (v) =>
                          v != null && v.contains('@') ? null : 'Invalid email',
                    ),
                    const SizedBox(height: 18),

                    // Password with Forgot Password
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 4, bottom: 8),
                              child: Text(
                                'PASSWORD',
                                style: GoogleFonts.manrope(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.2,
                                  color: isDark ? AppColors.slate400 : AppColors.slate500,
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () => _showForgotPasswordSheet(context),
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  'Forgot Password?',
                                  style: GoogleFonts.manrope(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        AppInput(
                          controller: _passCtrl,
                          label: '',
                          prefixIcon: Icons.lock_outline,
                          obscure: true,
                          hintText: 'Enter your password',
                          validator: (v) => v != null && v.length >= 6
                              ? null
                              : 'Min 6 characters',
                        ),
                      ],
                    ),

                    const SizedBox(height: 28),

                    // Login Button — gradient primary
                    AppButton(
                      label: 'Log In',
                      icon: Icons.arrow_forward,
                      onTap: _loginWithEmail,
                      loading: _isEmailLoading,
                      filled: true,
                    ),

                    const SizedBox(height: 24),

                    // Divider
                    Row(
                      children: [
                        Expanded(
                          child: Divider(
                            color: isDark ? AppColors.glassBorder : AppColors.slate200,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Text(
                            'Or continue with',
                            style: GoogleFonts.manrope(
                              fontSize: 12,
                              color: AppColors.slate500,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Divider(
                            color: isDark ? AppColors.glassBorder : AppColors.slate200,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Social Buttons
                    SocialButton(
                      label: 'Continue with Google',
                      imagePath: 'assets/logos/google_logo.png',
                      onTap: _loginWithGoogle,
                      loading: _isGoogleLoading,
                    ),

                    const SizedBox(height: 28),

                    // Footer
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'New to Bubbles? ',
                          style: GoogleFonts.manrope(
                            fontSize: 14,
                            color: AppColors.slate400,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pushNamed(context, '/signup'),
                          child: Text(
                            'Sign Up',
                            style: GoogleFonts.manrope(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          ),

          // Bottom accent line
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    Theme.of(context).colorScheme.primary.withAlpha(128),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
