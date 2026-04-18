import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';
import '../theme/design_tokens.dart';
import '../widgets/app_button.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final AuthService _authService = AuthService.instance;
  bool _loading = false;

  void _checkVerification() async {
    // Reload user to get latest metadata
    try {
      // Note: Supabase user reload might be needed depending on implementation,
      // but accessing the property triggers a check on the current instance.
      // Ideally, you might want to call _authService.refreshSession() if available.

      if (_authService.isEmailVerified) {
        context.go('/profile-completion');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Email not verified yet. Please check your inbox.',
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      // handle error
    }
  }

  void _resendEmail() async {
    setState(() => _loading = true);
    try {
      final user = _authService.currentUser;
      if (user != null && user.email != null) {
        await _authService.resendVerificationEmail(user.email!);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Verification email sent!'),
              backgroundColor: Theme.of(context).colorScheme.primary,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.backgroundDark
          : AppColors.backgroundLight,
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
          SafeArea(
        child: Column(
          children: [
            // Consistent header
            Container(
              decoration: BoxDecoration(
                color: Colors.transparent,
                border: Border(
                  bottom: BorderSide(
                    color: isDark
                        ? AppColors.glassBorder
                        : AppColors.slate200,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.arrow_back_rounded,
                        color: isDark ? Colors.white : AppColors.slate900,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Text(
                      'Verify Email',
                      style: GoogleFonts.manrope(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : AppColors.slate900,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24.0,
                  vertical: 16.0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Spacer(flex: 1),

                    // Icon & Title
                    Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.glassWhite
                                : Theme.of(context).colorScheme.primary.withAlpha(26),
                            shape: BoxShape.circle,
                            border: isDark
                                ? Border.all(color: AppColors.glassBorder)
                                : null,
                          ),
                          child: Icon(
                            Icons.mark_email_unread_rounded,
                            size: 64,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 32),
                        Text(
                          'Verify your email',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.manrope(
                            fontSize: 28,
                            fontWeight: FontWeight.w200,
                            color: isDark
                                ? Colors.white
                                : AppColors.slate900,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'We have sent a verification link to your email address. Please tap the link in the email to continue.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.manrope(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            height: 1.6,
                            color: isDark
                                ? AppColors.slate400
                                : AppColors.slate500,
                          ),
                        ),
                      ],
                    ),

                    const Spacer(flex: 2),

                    // Buttons
                    Column(
                      children: [
                        AppButton(
                          label: 'I have verified it',
                          onTap: _checkVerification,
                          loading: _loading,
                          filled: true,
                        ),
                        const SizedBox(height: 16),
                        AppButton(
                          label: 'Resend Email',
                          onTap: _resendEmail,
                          loading: _loading,
                          filled: false,
                        ),
                      ],
                    ),

                    const Spacer(flex: 1),
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
