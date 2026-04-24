import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../services/analytics_service.dart';
import '../widgets/app_logo.dart';
import '../widgets/glass_morphism.dart';
import '../widgets/settings/settings_dialogs.dart';
import '../theme/design_tokens.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  void _showFeedbackDialog(BuildContext context) {
    int selectedRating = 0;
    final textController = TextEditingController();
    final theme = Theme.of(context);

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text('Rate Bubbles', style: GoogleFonts.manrope(fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (i) {
                      return IconButton(
                        icon: Icon(
                          i < selectedRating ? Icons.star_rounded : Icons.star_border_rounded,
                          color: theme.colorScheme.primary,
                          size: 32,
                        ),
                        onPressed: () => setDialogState(() => selectedRating = i + 1),
                      );
                    }),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: textController,
                    maxLines: 3,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Tell us what you think...',
                      hintStyle: const TextStyle(fontSize: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest.withAlpha(128),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: selectedRating == 0
                      ? null
                      : () async {
                          Navigator.pop(ctx);
                          await _submitFeedback(context, selectedRating, textController.text);
                        },
                  child: const Text('Submit'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _submitFeedback(BuildContext context, int rating, String text) async {
    final user = AuthService.instance.currentUser;
    if (user == null) return;
    try {
      await Supabase.instance.client.from('app_feedback').insert({
        'user_id': user.id,
        'rating': rating,
        'feedback_text': text.isNotEmpty ? text : null,
        'app_version': '1.0.4',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      AnalyticsService.instance.logAction(
        action: 'app_feedback_submitted',
        entityType: 'app_feedback',
        details: {'rating': rating},
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Thank you for your feedback!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const String appVersion = "1.0.5";

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: isDark ? AppColors.backgroundDark : theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          // Glass morphism background
          const MeshGradientBackground(),
          
          SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(theme),
                  const SizedBox(height: 32),
                  _buildTypographySection(
                    theme: theme,
                    title: 'PROJECT ABSTRACT',
                    content: 'The aim of our project is to enhance communication skills by using AI and NLP to assist during and after conversations. It aims to recognize the tone and flow of discussions, provide real-time suggestions for impactful responses, and help users understand industry-specific jargon. By analysing conversations, it offers tailored tips to improve communication, ensuring users can refine their skills over time.\n\nThe tool not only transcribes and summarizes conversations but also finds key participants, highlights key details, and provides actionable insights. It includes a "replay" feature that suggests alternative phrases or approaches, helping users reflect on what could have been said more effectively. Whether it is a formal business meeting, an informal chat, or a professional negotiation, this AI-powered assistant is designed to support users in becoming more confident and articulate communicators.',
                  ),
                  const SizedBox(height: 24),
                  _buildTypographySection(
                    theme: theme,
                    title: 'PROJECT RATIONALE',
                    content: 'As a student, sometime after a conversation ends, I realize the words that I used were not appropriate for the conversation and I could have done it in a better way, or how could I have delivered my message more clearly and made my conversation more engaging? But then, after some time passes, I forget all the points that I wanted to keep in mind.\n\nThe purpose of our project is to create a smart assistant that can not only capture, summarize, and analyze conversations in real-time but also assist people in improving their communication skills. The system will determine the tone of the conversation, map the flow of the conversation, provide instant responses, suggest strong phrases, and comment on the clarity, structure, and engagement of the conversation.',
                  ),
                  const SizedBox(height: 32),
                  _buildSectionTitle(theme, 'MEET THE TEAM'),
                  const SizedBox(height: 16),
                  _buildTeamSection(theme),
                  const SizedBox(height: 32),
                  _buildSupportSection(context, theme, isDark),
                  const SizedBox(height: 48),
                  _buildFooter(isDark),
                  const SizedBox(height: 80), // Padding for FAB
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showFeedbackDialog(context),
        elevation: 0,
        backgroundColor: theme.colorScheme.primaryContainer.withAlpha(200), // Slightly transparent
        foregroundColor: theme.colorScheme.onPrimaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        icon: const Icon(Icons.rate_review_rounded, size: 20),
        label: Text('Rate App', style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 16),
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: const AppLogo(size: 64),
          ),
          const SizedBox(height: 20),
          Text(
            'Bubbles AI',
            style: GoogleFonts.manrope(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'AI-powered Conversational Assistant',
            style: GoogleFonts.manrope(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.2,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(ThemeData theme, String title) {
    return Text(
      title,
      style: GoogleFonts.manrope(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.5,
        color: theme.colorScheme.primary,
      ).copyWith(height: 1.0),
    );
  }

  Widget _buildTypographySection({
    required ThemeData theme,
    required String title,
    required String content,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(theme, title),
        const SizedBox(height: 12),
        GlassCard(
          padding: const EdgeInsets.all(16),
          child: Text(
            content,
            style: theme.textTheme.bodyMedium?.copyWith(
              height: 1.6,
              color: theme.colorScheme.onSurface.withAlpha(204),
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
            textAlign: TextAlign.justify,
          ),
        ),
      ],
    );
  }

  Widget _buildTeamSection(ThemeData theme) {
    return Column(
      children: [
        const _MinimalDeveloperInfo(name: 'Muhammad Ahmad', regNo: 'FA22-BCS-025'),
        const SizedBox(height: 12),
        const _MinimalDeveloperInfo(name: 'Attique Rehman', regNo: 'FA22-BCS-164'),
        const SizedBox(height: 24),
        GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.school_outlined, color: theme.colorScheme.onSurfaceVariant.withAlpha(150), size: 24),
                const SizedBox(height: 8),
                Text(
                  'COMSATS University Islamabad',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                Text(
                  'Lahore Campus',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSupportSection(BuildContext context, ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(theme, 'SUPPORT'),
        const SizedBox(height: 12),
        GlassCard(
          padding: EdgeInsets.zero,
          child: InkWell(
            onTap: () => showContactSheet(context, isDark),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.mail_outline_rounded, color: theme.colorScheme.onSurfaceVariant, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Contact Us',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios_rounded, color: theme.colorScheme.onSurfaceVariant, size: 14),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter(bool isDark) {
    return Center(
      child: Column(
        children: [
          Text(
            'Bubbles v1.0.5',
            style: GoogleFonts.manrope(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.slate600 : AppColors.slate400,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Your Personal Intelligence Companion',
            style: GoogleFonts.manrope(
              fontSize: 11,
              color: isDark ? AppColors.slate700 : AppColors.slate300,
            ),
          ),
        ],
      ),
    );
  }
}

class _MinimalDeveloperInfo extends StatelessWidget {
  final String name;
  final String regNo;

  const _MinimalDeveloperInfo({required this.name, required this.regNo});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: theme.colorScheme.primary.withAlpha(26),
            child: Text(
              name.isNotEmpty ? name[0] : '',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  regNo,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.2,
                    fontSize: 11,
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




