import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/help_content.dart';
import '../models/scenario_models.dart';
import '../providers/scenarios_provider.dart';
import '../routes/app_routes.dart';
import '../theme/design_tokens.dart';
import '../widgets/app_snack_bar.dart';
import '../widgets/help_sheet.dart';
import '../widgets/skeleton_loader.dart';

class PracticeScreen extends StatefulWidget {
  const PracticeScreen({super.key});

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> {
  final _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ScenariosProvider>().loadSuggested();
    });
  }

  Future<void> _refresh() => context.read<ScenariosProvider>().loadSuggested();

  Future<List<Map<String, dynamic>>> _fetchPersonEntities() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return [];
    final res = await _supabase
        .from('entities')
        .select('id, display_name')
        .eq('user_id', uid)
        .eq('entity_type', 'person')
        .order('display_name');
    return List<Map<String, dynamic>>.from(res);
  }

  Future<void> _onGenerate() async {
    final entity = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EntityPickerSheet(loader: _fetchPersonEntities),
    );
    if (entity == null || !mounted) return;
    final entityId = entity['id'].toString();
    final entityName = entity['display_name']?.toString() ?? 'someone';

    // Loading dialog (call takes 1-3 s; allow up to 30 s).
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _GeneratingDialog(),
    );
    final s = await context
        .read<ScenariosProvider>()
        .generate(targetEntityId: entityId);
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    final code = context.read<ScenariosProvider>().lastGenerateStatus;
    if (s == null) {
      final msg = switch (code) {
        404 => "$entityName isn't in your graph yet.",
        403 => 'You can only generate for your own people.',
        503 => "Generation failed — please try again.",
        429 => 'Slow down — try again in a moment.',
        _ => "Couldn't generate a scenario — try again.",
      };
      AppSnackBar.show(context,
          message: msg, tone: AppSnackTone.warning);
      return;
    }
    HapticFeedback.lightImpact();
    AppSnackBar.show(context,
        message: 'New scenario with $entityName',
        tone: AppSnackTone.success);
  }

  Future<void> _onTapScenario(Scenario s) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ScenarioBriefingSheet(scenario: s),
    );
    if (ok != true || !mounted) return;
    await _startScenario(s);
  }

  Future<void> _startScenario(Scenario s) async {
    final provider = context.read<ScenariosProvider>();
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _StartingDialog(),
    );
    final res = await provider.start(s);
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    if (res == null) {
      AppSnackBar.show(context,
          message: "Couldn't start scenario — try again.",
          tone: AppSnackTone.danger);
      return;
    }
    Navigator.of(context).pushNamed(
      AppRoutes.newSession,
      arguments: <String, dynamic>{
        'targetEntityId': res.scenario.targetEntityId ?? s.targetEntityId,
        'targetEntityName': s.targetEntityName,
        'scenarioId': res.scenario.id,
        'sessionId': res.sessionId,
        'openingLine': s.openingLine,
        'situation': s.situation,
        'goal': s.goal,
        'roleMode': s.roleMode,
        'successCriteria': s.successCriteria,
      },
    );
  }

  Future<void> _onDismiss(Scenario s) async {
    final ok = await context.read<ScenariosProvider>().dismiss(s);
    if (!mounted) return;
    AppSnackBar.show(
      context,
      message: ok ? 'Scenario dismissed.' : "Couldn't dismiss — try again.",
      tone: ok ? AppSnackTone.info : AppSnackTone.danger,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Practice',
          style: GoogleFonts.manrope(
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : AppColors.slate900,
          ),
        ),
        iconTheme: IconThemeData(
          color: isDark ? Colors.white : AppColors.slate900,
        ),
        actions: const [
          HelpIconButton(screen: HelpScreen.practice),
        ],
      ),
      floatingActionButton: Consumer<ScenariosProvider>(
        builder: (_, p, __) => FloatingActionButton.extended(
          onPressed: p.generating ? null : _onGenerate,
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add_rounded),
          label: Text(
            'New scenario',
            style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
          ),
        ),
      ),
      body: SafeArea(
        child: Consumer<ScenariosProvider>(
          builder: (context, p, _) {
            if (p.state == ScenariosLoadState.loading &&
                p.suggested.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: SkeletonDropdownForm(),
              );
            }
            if (p.state == ScenariosLoadState.error &&
                p.suggested.isEmpty) {
              return _ErrorState(
                  message: p.error ?? 'Error', onRetry: _refresh);
            }
            if (p.suggested.isEmpty) {
              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  children: const [
                    SizedBox(height: 80),
                    _EmptyState(),
                  ],
                ),
              );
            }
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
                itemCount: p.suggested.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) {
                  final s = p.suggested[i];
                  return Dismissible(
                    key: ValueKey('scenario-${s.id}'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 24),
                      child: Icon(Icons.delete_outline_rounded,
                          color: AppColors.error),
                    ),
                    onDismissed: (_) => _onDismiss(s),
                    child: _ScenarioCard(
                      scenario: s,
                      onTap: () => _onTapScenario(s),
                      isDark: isDark,
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ScenarioCard extends StatelessWidget {
  const _ScenarioCard({
    required this.scenario,
    required this.onTap,
    required this.isDark,
  });

  final Scenario scenario;
  final VoidCallback onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Ink(
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color:
                  isDark ? AppColors.glassBorder : AppColors.slate200,
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      scenario.title.isEmpty
                          ? 'Scenario'
                          : scenario.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color:
                            isDark ? Colors.white : AppColors.slate900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _DifficultyBadge(d: scenario.difficulty),
                ],
              ),
              if (scenario.targetEntityName != null &&
                  scenario.targetEntityName!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.person_rounded,
                        size: 14,
                        color: isDark
                            ? AppColors.slate400
                            : AppColors.slate500),
                    const SizedBox(width: 4),
                    Text(
                      'with ${scenario.targetEntityName}',
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppColors.slate400
                            : AppColors.slate500,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              Text(
                scenario.situation.isEmpty
                    ? scenario.openingLine
                    : scenario.situation,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  height: 1.45,
                  color: isDark
                      ? AppColors.slate300
                      : AppColors.slate600,
                ),
              ),
              if (scenario.openingLine.isNotEmpty &&
                  scenario.situation.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.glassPrimary,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(
                      color: AppColors.glassPrimaryBorder,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.chat_bubble_outline_rounded,
                          size: 14, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '"${scenario.openingLine}"',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.manrope(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DifficultyBadge extends StatelessWidget {
  const _DifficultyBadge({required this.d});
  final ScenarioDifficulty d;

  @override
  Widget build(BuildContext context) {
    if (d == ScenarioDifficulty.unknown) return const SizedBox.shrink();
    final (label, color) = switch (d) {
      ScenarioDifficulty.easy => ('Easy', AppColors.success),
      ScenarioDifficulty.medium => ('Medium', AppColors.warning),
      ScenarioDifficulty.hard => ('Hard', AppColors.error),
      _ => ('—', AppColors.slate500),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: GoogleFonts.manrope(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _EntityPickerSheet extends StatefulWidget {
  const _EntityPickerSheet({required this.loader});

  final Future<List<Map<String, dynamic>>> Function() loader;

  @override
  State<_EntityPickerSheet> createState() => _EntityPickerSheetState();
}

class _EntityPickerSheetState extends State<_EntityPickerSheet> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.loader();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (ctx, scroll) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.backgroundDark : Colors.white,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadius.xl)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color:
                      isDark ? AppColors.slate700 : AppColors.slate300,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Pick a person to roleplay with',
                style: GoogleFonts.manrope(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : AppColors.slate900,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _future,
                  builder: (_, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(
                          child: CircularProgressIndicator());
                    }
                    final list = snap.data ?? const [];
                    if (list.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            'No people in your graph yet. Add someone in '
                            'Knowledge Graph, then come back.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.manrope(
                              color: isDark
                                  ? AppColors.slate400
                                  : AppColors.slate600,
                            ),
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      controller: scroll,
                      itemCount: list.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 6),
                      itemBuilder: (_, i) {
                        final e = list[i];
                        final name = e['display_name']?.toString() ??
                            '(unnamed)';
                        return ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadius.md),
                          ),
                          tileColor: isDark
                              ? AppColors.surfaceDark
                              : AppColors.slate100,
                          leading: CircleAvatar(
                            backgroundColor:
                                AppColors.primary.withValues(alpha: 0.2),
                            child: Text(
                              (name.isNotEmpty ? name[0] : '?')
                                  .toUpperCase(),
                              style: GoogleFonts.manrope(
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          title: Text(
                            name,
                            style: GoogleFonts.manrope(
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? Colors.white
                                  : AppColors.slate900,
                            ),
                          ),
                          onTap: () => Navigator.of(context).pop(e),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ScenarioBriefingSheet extends StatelessWidget {
  const _ScenarioBriefingSheet({required this.scenario});
  final Scenario scenario;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scroll) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.backgroundDark : Colors.white,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadius.xl)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.slate700
                        : AppColors.slate300,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      scenario.title.isEmpty
                          ? 'Scenario'
                          : scenario.title,
                      style: GoogleFonts.manrope(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: isDark
                            ? Colors.white
                            : AppColors.slate900,
                      ),
                    ),
                  ),
                  _DifficultyBadge(d: scenario.difficulty),
                ],
              ),
              if (scenario.targetEntityName != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'with ${scenario.targetEntityName}',
                    style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.slate400
                          : AppColors.slate600,
                    ),
                  ),
                ),
              const SizedBox(height: 18),
              Expanded(
                child: ListView(
                  controller: scroll,
                  children: [
                    if (scenario.situation.isNotEmpty)
                      _BriefSection(
                        label: 'Situation',
                        body: scenario.situation,
                        isDark: isDark,
                      ),
                    if (scenario.goal.isNotEmpty)
                      _BriefSection(
                        label: 'Your goal',
                        body: scenario.goal,
                        isDark: isDark,
                      ),
                    if (scenario.successCriteria.isNotEmpty)
                      _BriefList(
                        label: "What 'good' looks like",
                        items: scenario.successCriteria,
                        isDark: isDark,
                      ),
                    if (scenario.openingLine.isNotEmpty)
                      _OpeningLineCard(
                        line: scenario.openingLine,
                        who: scenario.targetEntityName,
                        isDark: isDark,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding:
                        const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(
                    'Start session',
                    style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BriefSection extends StatelessWidget {
  const _BriefSection({
    required this.label,
    required this.body,
    required this.isDark,
  });
  final String label;
  final String body;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.manrope(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.9,
              color: isDark
                  ? AppColors.slate400
                  : AppColors.slate500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: GoogleFonts.manrope(
              fontSize: 14,
              height: 1.45,
              color: isDark ? Colors.white : AppColors.slate900,
            ),
          ),
        ],
      ),
    );
  }
}

class _BriefList extends StatelessWidget {
  const _BriefList({
    required this.label,
    required this.items,
    required this.isDark,
  });
  final String label;
  final List<String> items;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.manrope(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.9,
              color: isDark
                  ? AppColors.slate400
                  : AppColors.slate500,
            ),
          ),
          const SizedBox(height: 6),
          for (final it in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 8),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      it,
                      style: GoogleFonts.manrope(
                        fontSize: 13.5,
                        height: 1.4,
                        color: isDark
                            ? AppColors.slate200
                            : AppColors.slate700,
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

class _OpeningLineCard extends StatelessWidget {
  const _OpeningLineCard({
    required this.line,
    required this.who,
    required this.isDark,
  });
  final String line;
  final String? who;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.glassPrimary,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.glassPrimaryBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            who == null
                ? 'OPENING LINE'
                : '${who!.toUpperCase()} OPENS WITH',
            style: GoogleFonts.manrope(
              fontSize: 10.5,
              letterSpacing: 0.9,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '"$line"',
            style: GoogleFonts.manrope(
              fontSize: 14,
              fontStyle: FontStyle.italic,
              color: isDark ? Colors.white : AppColors.slate900,
            ),
          ),
        ],
      ),
    );
  }
}

class _GeneratingDialog extends StatelessWidget {
  const _GeneratingDialog();
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AlertDialog(
      backgroundColor:
          isDark ? AppColors.surfaceDark : Colors.white,
      content: Row(
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'Generating a scenario…',
              style: GoogleFonts.manrope(
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : AppColors.slate900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StartingDialog extends StatelessWidget {
  const _StartingDialog();
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AlertDialog(
      backgroundColor:
          isDark ? AppColors.surfaceDark : Colors.white,
      content: Row(
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'Opening the scene…',
              style: GoogleFonts.manrope(
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : AppColors.slate900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          Icon(Icons.theater_comedy_outlined,
              size: 56,
              color:
                  isDark ? AppColors.slate500 : AppColors.slate400),
          const SizedBox(height: 16),
          Text(
            'No practice scenarios yet.',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : AppColors.slate900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap "New scenario" to generate one for someone in your '
            "graph, or finish a wingman session and we'll suggest "
            'some automatically.',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 14,
              color:
                  isDark ? AppColors.slate400 : AppColors.slate500,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded,
                color: AppColors.error, size: 48),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                color:
                    isDark ? AppColors.slate300 : AppColors.slate600,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => onRetry(),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
