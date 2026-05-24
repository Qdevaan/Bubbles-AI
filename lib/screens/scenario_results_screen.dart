import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../data/help_content.dart';
import '../models/scenario_models.dart';
import '../providers/scenarios_provider.dart';
import '../routes/app_routes.dart';
import '../theme/design_tokens.dart';
import '../widgets/help_sheet.dart';

class ScenarioResultsScreen extends StatefulWidget {
  const ScenarioResultsScreen({
    super.key,
    required this.scenarioId,
    required this.scenarioTitle,
    this.sessionId,
  });

  final String scenarioId;
  final String scenarioTitle;
  final String? sessionId;

  @override
  State<ScenarioResultsScreen> createState() =>
      _ScenarioResultsScreenState();
}

class _ScenarioResultsScreenState extends State<ScenarioResultsScreen> {
  Scenario? _scored;
  bool _pollingDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _poll());
  }

  Future<void> _poll() async {
    final s = await context
        .read<ScenariosProvider>()
        .pollCompletion(widget.scenarioId);
    if (!mounted) return;
    setState(() {
      _scored = s;
      _pollingDone = true;
    });
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
          'Scenario result',
          style: GoogleFonts.manrope(
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : AppColors.slate900,
          ),
        ),
        iconTheme: IconThemeData(
          color: isDark ? Colors.white : AppColors.slate900,
        ),
        actions: const [
          HelpIconButton(screen: HelpScreen.scenarioResults),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _scored == null
              ? _Scoring(done: _pollingDone, onRetry: _poll)
              : _ScoredBody(scenario: _scored!, isDark: isDark),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Row(
            children: [
              if (widget.sessionId != null)
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pushReplacementNamed(
                      AppRoutes.sessionAnalytics,
                      arguments: {
                        'sessionId': widget.sessionId,
                        'sessionTitle': widget.scenarioTitle,
                      },
                    ),
                    child: const Text('See full analytics'),
                  ),
                ),
              if (widget.sessionId != null) const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(context)
                      .pushNamedAndRemoveUntil(AppRoutes.practice,
                          (r) => r.isFirst),
                  child: const Text('Back to Practice'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Scoring extends StatelessWidget {
  const _Scoring({required this.done, required this.onRetry});
  final bool done;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!done) ...[
            const SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 16),
            Text(
              'Scoring your scene…',
              style: GoogleFonts.manrope(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : AppColors.slate900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'This usually takes a few seconds.',
              style: GoogleFonts.manrope(
                color: isDark
                    ? AppColors.slate400
                    : AppColors.slate500,
              ),
            ),
          ] else ...[
            Icon(Icons.hourglass_disabled_rounded,
                size: 48,
                color: isDark
                    ? AppColors.slate400
                    : AppColors.slate500),
            const SizedBox(height: 12),
            Text(
              "Still scoring — couldn't fetch the result yet.",
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                color:
                    isDark ? AppColors.slate300 : AppColors.slate600,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Check again'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ScoredBody extends StatelessWidget {
  const _ScoredBody({required this.scenario, required this.isDark});
  final Scenario scenario;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final passed = scenario.passed ?? false;
    final color = passed ? AppColors.success : AppColors.warning;
    return ListView(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Icon(
                passed
                    ? Icons.emoji_events_rounded
                    : Icons.refresh_rounded,
                color: color,
                size: 36,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      passed ? 'You nailed it' : 'Almost — try again',
                      style: GoogleFonts.manrope(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                    if (passed)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '+40 XP awarded',
                          style: GoogleFonts.manrope(
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? AppColors.slate300
                                : AppColors.slate600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text(
          scenario.title.isEmpty ? 'Scenario' : scenario.title,
          style: GoogleFonts.manrope(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : AppColors.slate900,
          ),
        ),
        const SizedBox(height: 14),
        if ((scenario.scoreFeedback ?? '').isNotEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceDark : Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: isDark
                    ? AppColors.glassBorder
                    : AppColors.slate200,
              ),
            ),
            child: Text(
              scenario.scoreFeedback!,
              style: GoogleFonts.manrope(
                height: 1.5,
                fontSize: 14,
                color:
                    isDark ? AppColors.slate200 : AppColors.slate700,
              ),
            ),
          ),
        if (scenario.successCriteria.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            "WHAT 'GOOD' LOOKED LIKE",
            style: GoogleFonts.manrope(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.9,
              color: isDark
                  ? AppColors.slate400
                  : AppColors.slate500,
            ),
          ),
          const SizedBox(height: 6),
          for (final c in scenario.successCriteria)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
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
                      c,
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
      ],
    );
  }
}
