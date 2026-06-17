// Purpose: Performa persona wizard — multi-step flow that collects the user's identity, language goals, and communication style.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:bubbles/cache/cache_constants.dart';
import 'package:bubbles/cache/persistent_cache_service.dart';
import 'package:bubbles/models/persona.dart';
import 'package:bubbles/providers/persona_provider.dart';
import 'package:bubbles/routes/app_routes.dart';
import 'package:bubbles/services/auth_service.dart';
import 'package:bubbles/services/app_cache_service.dart';
import 'package:bubbles/services/persona_skip_service.dart';
import 'package:bubbles/theme/design_tokens.dart';
import 'package:bubbles/widgets/animated_background.dart';

import 'draft.dart';
import 'widgets/step1_identity.dart';
import 'widgets/step2_language.dart';
import 'widgets/step3_goals.dart';

import '../../widgets/app_dialog.dart';
import '../../widgets/app_snack_bar.dart';
/// Three-step persona wizard ("Performa"). Collects identity, language,
/// and goal information then upserts via [PersonaProvider]. In setup mode
/// it hard-blocks back navigation; in edit mode it pre-fills from the
/// existing persona, allows back navigation, and pops on save.
class PerformaWizardScreen extends StatefulWidget {
  const PerformaWizardScreen({
    super.key,
    this.initial,
    this.editMode = false,
  });

  final Persona? initial;
  final bool editMode;

  @override
  State<PerformaWizardScreen> createState() => _PerformaWizardScreenState();
}

class _PerformaWizardScreenState extends State<PerformaWizardScreen> {
  int _step = 0;
  late final PerformaDraft _draft;
  bool _submitting = false;
  late bool _showIntro;

  static const _titles = ['About you', 'Language & style', 'Goals & context'];

  @override
  void initState() {
    super.initState();
    // Intro panel only shown in fresh setup mode (not edit, not when
    // initial values were pre-filled).
    _showIntro = !widget.editMode && widget.initial == null;
    _draft = PerformaDraft();
    final p = widget.initial;
    if (p != null) {
      _draft.displayName = p.displayName;
      _draft.ageRange = p.ageRange;
      _draft.rolePrimary = p.rolePrimary;
      _draft.professionDetail = p.professionDetail;
      _draft.expertiseTags = List<String>.from(p.expertiseTags);
      _draft.nativeLanguage = p.nativeLanguage;
      _draft.learningLanguage = p.learningLanguage;
      _draft.proficiencySelfRated = p.proficiencySelfRated;
      _draft.formalityPreference = p.formalityPreference;
      _draft.communicationStyle = List<String>.from(p.communicationStyle);
      _draft.primaryGoals = List<String>.from(p.primaryGoals);
      _draft.typicalScenarios = List<String>.from(p.typicalScenarios);
      _draft.culturalContext = p.culturalContext;
      _draft.avoidList = p.avoidList;
    }
  }

  bool get _canAdvance {
    if (_step == 0) return _draft.rolePrimary != null;
    if (_step == 1) {
      return (_draft.nativeLanguage ?? '').isNotEmpty &&
          (_draft.learningLanguage ?? '').isNotEmpty;
    }
    return true;
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      // Capture services before the await so we don't touch a stale context.
      final persona = context.read<PersonaProvider>();
      final l1 = context.read<AppCacheService>();
      final l2 = context.read<PersistentCacheService>();
      final userId = AuthService.instance.currentUserId;

      await persona.upsert(_draft.toUpdate());

      // Persona changed → user-relational graph must be redrawn from
      // scratch with the freshly-personalized data centered on the user.
      // Wipe both cache layers; the next graph open will network-fetch.
      if (userId != null) {
        l1.invalidateAll();
        await l2.delete(CacheKeys.graphExport(userId));
      }
      await PersonaSkipService.instance.clear();

      if (!mounted) return;
      if (widget.editMode) {
        Navigator.of(context).pop(true);
      } else {
        Navigator.of(context).pushReplacementNamed(AppRoutes.home);
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.show(context, message: 'Save failed: $e');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _confirmSkip() async {
    final confirmed = await AppDialog.confirm(
      context: context,
      title: 'Skip personalization?',
      message: 'Without a Performa profile, suggestions, scenarios, and your '
          'knowledge graph will use generic defaults — they will not be '
          'tailored to your role, language, or goals. You can fill it in '
          'any time from Settings → Performa.',
      cancelLabel: 'Personalize now',
      confirmLabel: 'Skip anyway',
      tone: AppDialogTone.warning,
    );
    if (!confirmed) return;
    await PersonaSkipService.instance.markSkipped();
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(AppRoutes.home);
  }

  void _onStepChanged() => setState(() {});

  Widget _buildStepBody() {
    switch (_step) {
      case 0:
        return Step1Identity(draft: _draft, onChanged: _onStepChanged);
      case 1:
        return Step2Language(draft: _draft, onChanged: _onStepChanged);
      default:
        return Step3Goals(draft: _draft, onChanged: _onStepChanged);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cs = theme.colorScheme;
    final progress = (_step + 1) / 3;

    final body = Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0B1620) : const Color(0xFFF5F8FB),
      body: Stack(
        children: [
          Positioned.fill(child: AnimatedAmbientBackground(isDark: isDark)),
          SafeArea(
            child: _showIntro
                ? _IntroPanel(
                    isDark: isDark,
                    onContinue: () => setState(() => _showIntro = false),
                    onSkip: _confirmSkip,
                  )
                : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
                  child: Row(
                    children: [
                      if (widget.editMode || _step > 0)
                        IconButton(
                          icon: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 20,
                            color: isDark ? Colors.white : AppColors.slate900,
                          ),
                          onPressed: _submitting
                              ? null
                              : () {
                                  if (_step > 0) {
                                    setState(() => _step--);
                                  } else if (widget.editMode) {
                                    Navigator.of(context).pop();
                                  }
                                },
                        )
                      else
                        const SizedBox(width: 8),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _titles[_step],
                              style: GoogleFonts.manrope(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color:
                                    isDark ? Colors.white : AppColors.slate900,
                              ),
                            ),
                            Text(
                              'Step ${_step + 1} of 3',
                              style: GoogleFonts.manrope(
                                fontSize: 12,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      backgroundColor:
                          isDark ? AppColors.glassBorder : AppColors.slate200,
                      valueColor: AlwaysStoppedAnimation(cs.primary),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: _buildStepBody(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (_step > 0)
                        TextButton.icon(
                          onPressed: _submitting
                              ? null
                              : () => setState(() => _step--),
                          icon: const Icon(Icons.arrow_back_rounded, size: 18),
                          label: Text(
                            'Back',
                            style: GoogleFonts.manrope(
                                fontSize: 14, fontWeight: FontWeight.w700),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor:
                                isDark ? Colors.white70 : AppColors.slate600,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
                        )
                      else
                        const SizedBox.shrink(),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: !_canAdvance || _submitting
                              ? null
                              : () {
                                  if (_step < 2) {
                                    setState(() => _step++);
                                  } else {
                                    _submit();
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: cs.primary,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor:
                                cs.primary.withAlpha(70),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 28),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _submitting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: Colors.white,
                                  ),
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _step < 2
                                          ? 'Next'
                                          : (widget.editMode
                                              ? 'Save'
                                              : 'Finish'),
                                      style: GoogleFonts.manrope(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(
                                      _step < 2
                                          ? Icons.arrow_forward_rounded
                                          : Icons.check_rounded,
                                      size: 18,
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
          ),
        ],
      ),
    );

    if (widget.editMode) return body;
    return PopScope(canPop: false, child: body);
  }
}

class _IntroPanel extends StatelessWidget {
  final bool isDark;
  final VoidCallback onContinue;
  final VoidCallback onSkip;

  const _IntroPanel({
    required this.isDark,
    required this.onContinue,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final fg = isDark ? Colors.white : AppColors.slate900;
    final muted = isDark ? AppColors.slate300 : AppColors.slate600;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.glassPrimary,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: AppColors.glassPrimaryBorder,
                width: 0.5,
              ),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              size: 36,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Set up your Performa',
            style: GoogleFonts.manrope(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: fg,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Three quick questions so Bubbles knows who it is coaching.',
            style: GoogleFonts.manrope(
              fontSize: 15,
              height: 1.5,
              color: muted,
            ),
          ),
          const SizedBox(height: 24),
          _Bullet(
            icon: Icons.tips_and_updates_rounded,
            title: 'Sharper suggestions',
            body:
                'Live Wingman tailors reply ideas to your role, language '
                'level, and tone.',
            fg: fg,
            muted: muted,
            isDark: isDark,
          ),
          const SizedBox(height: 12),
          _Bullet(
            icon: Icons.theater_comedy_rounded,
            title: 'Relevant practice scenarios',
            body:
                'Roleplays match the conversations you actually have — '
                'meetings, interviews, customer calls.',
            fg: fg,
            muted: muted,
            isDark: isDark,
          ),
          const SizedBox(height: 12),
          _Bullet(
            icon: Icons.hub_rounded,
            title: 'A knowledge graph centered on you',
            body:
                'Your entities, topics, and contacts get woven into one '
                'relational map with you at the center.',
            fg: fg,
            muted: muted,
            isDark: isDark,
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.amber.withAlpha(28)
                  : AppColors.amber.withAlpha(38),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: AppColors.amber.withAlpha(120),
                width: 0.5,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: AppColors.amber,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Skip and results will not be personalized — you can '
                    'fill it in any time from Settings → Performa.',
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppColors.amber : AppColors.slate800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: onContinue,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
              ),
              child: Text(
                'Personalize now',
                style: GoogleFonts.manrope(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: TextButton(
              onPressed: onSkip,
              style: TextButton.styleFrom(
                foregroundColor: muted,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
              ),
              child: Text(
                'Skip for now',
                style: GoogleFonts.manrope(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Color fg;
  final Color muted;
  final bool isDark;

  const _Bullet({
    required this.icon,
    required this.title,
    required this.body,
    required this.fg,
    required this.muted,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.surfaceDark.withAlpha(180)
            : Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isDark
              ? AppColors.surfaceDarkHighlight
              : AppColors.slate200,
          width: 0.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.glassPrimary,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(icon, size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: GoogleFonts.manrope(
                    fontSize: 13.5,
                    height: 1.45,
                    color: muted,
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
