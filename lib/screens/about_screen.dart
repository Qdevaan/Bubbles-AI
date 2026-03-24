import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../services/analytics_service.dart';
import '../widgets/app_logo.dart';
import '../widgets/glass_morphism.dart';
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
                          size: 36,
                        ),
                        onPressed: () => setDialogState(() => selectedRating = i + 1),
                      );
                    }),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: textController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'Tell us what you think...',
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
          const SnackBar(content: Text('Thank you for your feedback!')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const String appVersion = "1.0.4";

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: isDark ? AppColors.backgroundDark : theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          // Mesh gradient background
          const MeshGradientBackground(),

          CustomScrollView(
            slivers: [
              _buildSliverAppBar(context),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _buildSectionHeader(
                      theme,
                      icon: Icons.auto_awesome,
                      title: 'Project Abstract',
                    ),
                    const SizedBox(height: 16),
                    GlassCard(
                      child: Text(
                        'The aim of our project is to enhance communication skills by using AI and NLP to assist during and after conversations. It aims to recognize the tone and flow of discussions, provide real-time suggestions for impactful responses, and help users understand industry-specific jargon. By analysing conversations, it offers tailored tips to improve communication, ensuring users can refine their skills over time.',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          height: 1.6,
                          color: theme.colorScheme.onSurface.withAlpha(204),
                        ),
                        textAlign: TextAlign.justify,
                      ),
                    ),
                    const SizedBox(height: 16),
                    GlassCard(
                      child: Text(
                        'The tool not only transcribes and summarizes conversations but also finds key participants, highlights key details, and provides actionable insights. It includes a "replay" feature that suggests alternative phrases or approaches, helping users reflect on what could have been said more effectively. Whether it is a formal business meeting, an informal chat, or a professional negotiation, this AI-powered assistant is designed to support users in becoming more confident and articulate communicators.',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          height: 1.6,
                          color: theme.colorScheme.onSurface.withAlpha(204),
                        ),
                        textAlign: TextAlign.justify,
                      ),
                    ),
                    const SizedBox(height: 32),
                    _buildSectionHeader(
                      theme,
                      icon: Icons.lightbulb_circle,
                      title: 'Project Rationale',
                    ),
                    const SizedBox(height: 16),
                    GlassCard(
                      child: Column(
                        children: [
                          Text(
                            'As a student, sometime after a conversation ends, I realize the words that I used were not appropriate for the conversation and I could have done it in a better way, or how could I have delivered my message more clearly and made my conversation more engaging? But then, after some time passes, I forget all the points that I wanted to keep in mind.',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              height: 1.6,
                              color: theme.colorScheme.onSurface.withAlpha(204),
                            ),
                            textAlign: TextAlign.justify,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'The purpose of our project is to create a smart assistant that can not only capture, summarize, and analyze conversations in real-time but also assist people in improving their communication skills. The system will determine the tone of the conversation, map the flow of the conversation, provide instant responses, suggest strong phrases, and comment on the clarity, structure, and engagement of the conversation.',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              height: 1.6,
                              color: theme.colorScheme.onSurface.withAlpha(204),
                            ),
                            textAlign: TextAlign.justify,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    _buildSectionHeader(
                      theme,
                      icon: Icons.groups_rounded,
                      title: 'Meet the Team',
                    ),
                    const SizedBox(height: 16),
                    const Row(
                      children: [
                        Expanded(
                          child: _DeveloperInfoCard(
                            name: 'Muhammad Ahmad',
                            regNo: 'FA22-BCS-025',
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: _DeveloperInfoCard(
                            name: 'Attique Rehman',
                            regNo: 'FA22-BCS-164',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),
                    _buildAffiliationSection(theme),
                    const SizedBox(height: 30),
                    Center(
                      child: Column(
                        children: [
                          Text(
                            'Crafted with â¤ï¸ by the Bubbles Team',
                            style: GoogleFonts.manrope(
                              fontSize: 12,
                              color: AppColors.slate400,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary.withAlpha(38),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: theme.colorScheme.primary.withAlpha(77)),
                                ),
                                child: Text(
                                  'Bubbles v$appVersion',
                                  style: GoogleFonts.manrope(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.primary,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Made with AI Love',
                            style: GoogleFonts.manrope(
                              fontSize: 11,
                              color: AppColors.slate500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                  ]),
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showFeedbackDialog(context),
        icon: const Icon(Icons.rate_review_rounded),
        label: const Text('Rate App'),
      ),
    );
  }

  Widget _buildSliverAppBar(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SliverAppBar(
      expandedHeight: 300.0,
      pinned: true,
      stretch: true,
      backgroundColor: isDark ? AppColors.backgroundDark.withAlpha(220) : theme.colorScheme.primary.withAlpha(200),
      foregroundColor: Colors.white,
      elevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        title: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Text(
              'About Bubbles',
              style: GoogleFonts.manrope(fontWeight: FontWeight.w200, fontSize: 20, color: Colors.white),
            ),
          ),
        ),
        centerTitle: true,
        background: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.backgroundDark,
                    theme.colorScheme.primary.withAlpha(128),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            // Abstract shapes
            Positioned(
              top: -100,
              right: -50,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.white.withAlpha(51),
                      Colors.white.withAlpha(0),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -50,
              left: -50,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      theme.colorScheme.tertiary.withAlpha(76),
                      theme.colorScheme.tertiary.withAlpha(0),
                    ],
                  ),
                ),
              ),
            ),
            // Content
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 40),
                const AppLogo(size: 120),
                const SizedBox(height: 16),
                Text(
                  'AI-powered Conversational Assistant',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onPrimary.withAlpha(230),
                    letterSpacing: 1.0,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
    ThemeData theme, {
    required IconData icon,
    required String title,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withAlpha(26),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.colorScheme.primary.withAlpha(51)),
          ),
          child: Icon(icon, color: theme.colorScheme.primary, size: 26),
        ),
        const SizedBox(width: 16),
        Text(
          title,
          style: GoogleFonts.manrope(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : AppColors.slate900,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildAffiliationSection(ThemeData theme) {
    return Column(
      children: [
        Text(
          'In partial fulfillment of the degree of BS in Computer Science at',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        GlassCard(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.school_rounded,
                  color: theme.colorScheme.primary,
                  size: 40,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'COMSATS University',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        'Islamabad, Lahore Campus',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DeveloperInfoCard extends StatelessWidget {
  final String name;
  final String regNo;

  const _DeveloperInfoCard({required this.name, required this.regNo});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: theme.colorScheme.primary.withAlpha(128),
                width: 2,
              ),
            ),
            child: CircleAvatar(
              radius: 28,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Text(
                name.isNotEmpty ? name[0] : '',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            name,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            regNo,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}


