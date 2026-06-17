// Purpose: Performa settings screen — lets the user view and edit their saved Performa persona profile.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:bubbles/models/persona.dart';
import 'package:bubbles/providers/persona_provider.dart';

import '../theme/design_tokens.dart';
import '../widgets/animated_background.dart';
import '../widgets/skeleton_loader.dart';
import 'performa/performa_wizard_screen.dart';

class SettingsPerformaScreen extends StatefulWidget {
  const SettingsPerformaScreen({super.key});

  @override
  State<SettingsPerformaScreen> createState() => _SettingsPerformaScreenState();
}

class _SettingsPerformaScreenState extends State<SettingsPerformaScreen> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      await context.read<PersonaProvider>().refresh();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _edit(Persona? p) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PerformaWizardScreen(initial: p, editMode: true),
      ),
    );
    if (saved == true && mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final provider = context.watch<PersonaProvider>();
    final persona = provider.persona;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: Stack(
        children: [
          Positioned.fill(child: AnimatedAmbientBackground(isDark: isDark)),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        tooltip: 'Go back',
                        icon: Icon(
                          Icons.arrow_back,
                          size: 26,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'Performa',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.manrope(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: isDark
                                ? Colors.white
                                : AppColors.slate900,
                          ),
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: provider.loading || _refreshing
                            ? null
                            : () => _edit(persona),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: Text(
                          persona == null ? 'Setup' : 'Edit',
                          style: GoogleFonts.manrope(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: cs.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: provider.loading
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: SkeletonCardGroup(count: 4),
                        )
                      : persona == null
                          ? _EmptyState(
                              isDark: isDark,
                              onSetup: () => _edit(null),
                            )
                          : RefreshIndicator(
                              onRefresh: _refresh,
                              child: ListView(
                                physics:
                                    const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(
                                    16, 12, 16, 32),
                                children: [
                                  _Section(
                                    isDark: isDark,
                                    title: 'Identity',
                                    icon: Icons.person_outline,
                                    color: const Color(0xFF38BDF8),
                                    rows: [
                                      _Row('Display name',
                                          persona.displayName ?? '—'),
                                      _Row('Age range',
                                          persona.ageRange ?? '—'),
                                      _Row(
                                          'Primary role',
                                          _titleCase(
                                              persona.rolePrimary)),
                                      _Row('Profession',
                                          persona.professionDetail ?? '—'),
                                      _Row(
                                          'Expertise',
                                          persona.expertiseTags.isEmpty
                                              ? '—'
                                              : persona.expertiseTags
                                                  .join(', ')),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  _Section(
                                    isDark: isDark,
                                    title: 'Language & style',
                                    icon: Icons.translate_rounded,
                                    color: const Color(0xFFFB7185),
                                    rows: [
                                      _Row('Native language',
                                          persona.nativeLanguage),
                                      _Row('Learning language',
                                          persona.learningLanguage),
                                      _Row(
                                          'Proficiency',
                                          persona.proficiencySelfRated ??
                                              '—'),
                                      _Row(
                                          'Formality',
                                          _titleCase(
                                              persona.formalityPreference)),
                                      _Row(
                                          'Style',
                                          persona.communicationStyle.isEmpty
                                              ? '—'
                                              : persona.communicationStyle
                                                  .join(', ')),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  _Section(
                                    isDark: isDark,
                                    title: 'Goals & context',
                                    icon: Icons.flag_outlined,
                                    color: const Color(0xFF10B981),
                                    rows: [
                                      _Row(
                                          'Primary goals',
                                          persona.primaryGoals.isEmpty
                                              ? '—'
                                              : persona.primaryGoals
                                                  .join(', ')),
                                      _Row(
                                          'Typical scenarios',
                                          persona.typicalScenarios.isEmpty
                                              ? '—'
                                              : persona.typicalScenarios
                                                  .join(', ')),
                                      _Row('Cultural context',
                                          persona.culturalContext ?? '—'),
                                      _Row('Avoid list',
                                          persona.avoidList ?? '—'),
                                    ],
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

String _titleCase(String s) {
  if (s.isEmpty) return s;
  return s[0].toUpperCase() + s.substring(1);
}

class _Row {
  final String label;
  final String value;
  const _Row(this.label, this.value);
}

class _Section extends StatelessWidget {
  final bool isDark;
  final String title;
  final IconData icon;
  final Color color;
  final List<_Row> rows;

  const _Section({
    required this.isDark,
    required this.title,
    required this.icon,
    required this.color,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.glassWhite : Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(
          color: isDark ? AppColors.glassBorder : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withAlpha(38),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                    color: isDark ? Colors.white : AppColors.slate900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < rows.length; i++) ...[
            _RowTile(isDark: isDark, row: rows[i]),
            if (i < rows.length - 1)
              Divider(
                height: 16,
                color: isDark
                    ? Colors.white.withAlpha(13)
                    : Colors.grey.shade100,
              ),
          ],
        ],
      ),
    );
  }
}

class _RowTile extends StatelessWidget {
  final bool isDark;
  final _Row row;
  const _RowTile({required this.isDark, required this.row});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(
            row.label,
            style: GoogleFonts.manrope(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
        ),
        Expanded(
          child: Text(
            row.value,
            style: GoogleFonts.manrope(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : AppColors.slate900,
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool isDark;
  final VoidCallback onSetup;
  const _EmptyState({required this.isDark, required this.onSetup});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.badge_outlined, size: 64, color: cs.primary),
            const SizedBox(height: 12),
            Text(
              'No Performa yet',
              style: GoogleFonts.manrope(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : AppColors.slate900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Set up your Performa to personalise the assistant.',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                fontSize: 13,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onSetup,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('Set up Performa'),
            ),
          ],
        ),
      ),
    );
  }
}
