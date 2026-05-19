import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:bubbles/models/persona.dart';
import 'package:bubbles/providers/persona_provider.dart';
import 'package:bubbles/theme/design_tokens.dart';
import 'package:bubbles/widgets/animated_background.dart';

import 'draft.dart';
import 'widgets/step1_identity.dart';
import 'widgets/step2_language.dart';
import 'widgets/step3_goals.dart';

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

  static const _titles = ['About you', 'Language & style', 'Goals & context'];

  @override
  void initState() {
    super.initState();
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
      await context.read<PersonaProvider>().upsert(_draft.toUpdate());
      if (!mounted) return;
      if (widget.editMode) {
        Navigator.of(context).pop(true);
      } else {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.show(context, message: 'Save failed: $e');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
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
            child: Column(
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
