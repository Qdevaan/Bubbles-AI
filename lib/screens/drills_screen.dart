// Purpose: Drills screen — shows the spaced-repetition flashcard queue and handles card review submissions.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/help_content.dart';
import '../models/drill_models.dart';
import '../providers/drills_provider.dart';
import '../theme/design_tokens.dart';
import '../widgets/app_dialog.dart';
import '../widgets/app_snack_bar.dart';
import '../widgets/help_sheet.dart';
import '../widgets/skeleton_loader.dart';

class DrillsScreen extends StatefulWidget {
  const DrillsScreen({super.key});

  @override
  State<DrillsScreen> createState() => _DrillsScreenState();
}

class _DrillsScreenState extends State<DrillsScreen> {
  bool _flipped = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<DrillsProvider>();
      // Skip the network round-trip when an earlier prefetch already
      // populated the provider — the screen renders from cached state.
      if (!provider.hasData) {
        provider.load();
      }
    });
  }

  Future<void> _refresh() async {
    await context.read<DrillsProvider>().load();
    if (mounted) setState(() => _flipped = false);
  }

  Future<void> _grade(DrillCard card, DrillResult result) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    HapticFeedback.lightImpact();
    final provider = context.read<DrillsProvider>();
    final res = await provider.review(card, result: result);
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _flipped = false;
    });
    if (res == null) {
      final code = provider.lastReviewError;
      if (code == 429) {
        AppSnackBar.show(
          context,
          message: 'Slow down — too many reviews. Try again in a moment.',
          tone: AppSnackTone.warning,
        );
      } else if (code == 409) {
        AppSnackBar.show(
          context,
          message: 'Card already retired.',
          tone: AppSnackTone.info,
        );
      } else {
        AppSnackBar.show(
          context,
          message: "Couldn't sync — try again.",
          tone: AppSnackTone.danger,
        );
      }
      return;
    }
    final xp = res.xpAwarded;
    if (xp > 0) {
      AppSnackBar.show(
        context,
        message: '+$xp XP',
        tone: AppSnackTone.success,
        icon: Icons.bolt_rounded,
        duration: const Duration(milliseconds: 1400),
      );
    }
  }

  Future<void> _confirmRetire(DrillCard card) async {
    final ok = await AppDialog.confirm(
      context: context,
      title: 'Stop showing this card?',
      message: 'Retiring is permanent — this card will never appear in your '
          'drill queue again.',
      confirmLabel: 'Retire',
      tone: AppDialogTone.danger,
    );
    if (!ok || !mounted) return;
    final ok2 = await context.read<DrillsProvider>().retire(card);
    if (!mounted) return;
    if (ok2) {
      setState(() => _flipped = false);
      AppSnackBar.show(context, message: 'Card retired.', tone: AppSnackTone.info);
    } else {
      AppSnackBar.show(
        context,
        message: "Couldn't retire — try again.",
        tone: AppSnackTone.danger,
      );
    }
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
          'Drills',
          style: GoogleFonts.manrope(
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : AppColors.slate900,
          ),
        ),
        iconTheme: IconThemeData(
          color: isDark ? Colors.white : AppColors.slate900,
        ),
        actions: [
          Consumer<DrillsProvider>(
            builder: (_, p, __) {
              if (p.totalDue == 0) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.glassPrimary,
                      borderRadius:
                          BorderRadius.circular(AppRadius.full),
                      border: Border.all(
                        color: AppColors.glassPrimaryBorder,
                      ),
                    ),
                    child: Text(
                      '${p.totalDue} due',
                      style: GoogleFonts.manrope(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const HelpIconButton(screen: HelpScreen.drills),
        ],
      ),
      body: SafeArea(
        child: Consumer<DrillsProvider>(
          builder: (context, p, _) {
            if (p.state == DrillsLoadState.loading && p.cards.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: SkeletonDropdownForm(),
              );
            }
            if (p.state == DrillsLoadState.error) {
              return _ErrorState(message: p.error ?? 'Error', onRetry: _refresh);
            }
            if (p.cards.isEmpty) {
              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  children: const [
                    SizedBox(height: 120),
                    _EmptyState(),
                  ],
                ),
              );
            }
            final card = p.cards.first;
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  if (p.isUpcoming)
                    _PracticeEarlyBanner(card: card, isDark: isDark),
                  if (p.isUpcoming) const SizedBox(height: 16),
                  _DrillFlashcard(
                    card: card,
                    flipped: _flipped,
                    submitting: _submitting,
                    onFlip: () => setState(() => _flipped = !_flipped),
                    onRetire: () => _confirmRetire(card),
                    isDark: isDark,
                  ),
                  const SizedBox(height: 20),
                  _GradeButtons(
                    enabled: _flipped && !_submitting,
                    onCorrect: () => _grade(card, DrillResult.correct),
                    onWrong: () => _grade(card, DrillResult.wrong),
                  ),
                  const SizedBox(height: 32),
                  _UpNextStrip(
                    remaining: p.cards.length - 1,
                    isDark: isDark,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DrillFlashcard extends StatelessWidget {
  const _DrillFlashcard({
    required this.card,
    required this.flipped,
    required this.submitting,
    required this.onFlip,
    required this.onRetire,
    required this.isDark,
  });

  final DrillCard card;
  final bool flipped;
  final bool submitting;
  final VoidCallback onFlip;
  final VoidCallback onRetire;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final front = card.frontSnippet ?? '(no example yet)';
    final back = card.backSuggestion ?? '(no suggestion)';
    return GestureDetector(
      onTap: submitting ? null : onFlip,
      child: AnimatedContainer(
        duration: AppDurations.normal,
        curve: Curves.easeOutCubic,
        constraints: const BoxConstraints(minHeight: 260),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(
            color: flipped
                ? AppColors.glassPrimaryBorder
                : (isDark
                    ? AppColors.glassBorder
                    : AppColors.slate200),
          ),
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _CategoryBadge(category: card.category, isDark: isDark),
                const SizedBox(width: 8),
                _BoxBadge(box: card.box, isDark: isDark),
                const Spacer(),
                _ExamplesPill(
                  count: card.examplesCount,
                  isDark: isDark,
                ),
                IconButton(
                  tooltip: 'Retire card',
                  icon: Icon(
                    Icons.more_vert_rounded,
                    color: isDark
                        ? AppColors.slate400
                        : AppColors.slate500,
                  ),
                  onPressed: () async {
                    final v = await showMenu<String>(
                      context: context,
                      position: const RelativeRect.fromLTRB(
                          1000, 200, 24, 0),
                      items: const [
                        PopupMenuItem(
                          value: 'retire',
                          child: Text('Retire card'),
                        ),
                      ],
                    );
                    if (v == 'retire') onRetire();
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              flipped ? 'Better way to say it' : 'You wrote',
              style: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: flipped
                    ? AppColors.primary
                    : (isDark
                        ? AppColors.slate400
                        : AppColors.slate500),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              flipped ? back : front,
              style: GoogleFonts.manrope(
                fontSize: 20,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : AppColors.slate900,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Icon(
                  flipped
                      ? Icons.lightbulb_outline_rounded
                      : Icons.touch_app_rounded,
                  size: 16,
                  color: isDark
                      ? AppColors.slate500
                      : AppColors.slate400,
                ),
                const SizedBox(width: 6),
                Text(
                  flipped
                      ? 'Tap to see your original again'
                      : 'Tap the card to reveal the fix',
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: isDark
                        ? AppColors.slate500
                        : AppColors.slate400,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GradeButtons extends StatelessWidget {
  const _GradeButtons({
    required this.enabled,
    required this.onCorrect,
    required this.onWrong,
  });

  final bool enabled;
  final VoidCallback onCorrect;
  final VoidCallback onWrong;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _GradeButton(
            label: 'Still tricky',
            icon: Icons.refresh_rounded,
            color: AppColors.warning,
            enabled: enabled,
            onTap: onWrong,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _GradeButton(
            label: 'Got it',
            icon: Icons.check_circle_outline_rounded,
            color: AppColors.success,
            enabled: enabled,
            onTap: onCorrect,
          ),
        ),
      ],
    );
  }
}

class _GradeButton extends StatelessWidget {
  const _GradeButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Column(
              children: [
                Icon(icon, color: color),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: GoogleFonts.manrope(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryBadge extends StatelessWidget {
  const _CategoryBadge({required this.category, required this.isDark});
  final String category;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.glassPrimary,
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: AppColors.glassPrimaryBorder),
      ),
      child: Text(
        category.isEmpty ? 'general' : category,
        style: GoogleFonts.manrope(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

class _BoxBadge extends StatelessWidget {
  const _BoxBadge({required this.box, required this.isDark});
  final int box;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: (isDark ? AppColors.slate800 : AppColors.slate100),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(
        'Box $box / 5',
        style: GoogleFonts.manrope(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: isDark ? AppColors.slate300 : AppColors.slate600,
        ),
      ),
    );
  }
}

class _ExamplesPill extends StatelessWidget {
  const _ExamplesPill({required this.count, required this.isDark});
  final int count;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    if (count <= 1) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(
        '×$count',
        style: GoogleFonts.manrope(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.warning,
        ),
      ),
    );
  }
}

class _PracticeEarlyBanner extends StatelessWidget {
  const _PracticeEarlyBanner({required this.card, required this.isDark});
  final DrillCard card;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    String hint = 'Nothing due — practicing early.';
    if (card.dueAt != null) {
      final delta = card.dueAt!.difference(DateTime.now().toUtc());
      if (delta.inDays >= 1) {
        hint = 'Practice early — next due in ${delta.inDays}d.';
      } else if (delta.inHours >= 1) {
        hint = 'Practice early — next due in ${delta.inHours}h.';
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule_rounded,
              size: 16, color: AppColors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hint,
              style: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UpNextStrip extends StatelessWidget {
  const _UpNextStrip({required this.remaining, required this.isDark});
  final int remaining;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    if (remaining <= 0) {
      return Center(
        child: Text(
          'Last card in this stack.',
          style: GoogleFonts.manrope(
            fontSize: 12,
            color: isDark ? AppColors.slate500 : AppColors.slate400,
          ),
        ),
      );
    }
    return Center(
      child: Text(
        '$remaining more after this one.',
        style: GoogleFonts.manrope(
          fontSize: 12,
          color: isDark ? AppColors.slate500 : AppColors.slate400,
        ),
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
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.celebration_outlined,
              size: 56,
              color: isDark ? AppColors.slate500 : AppColors.slate400),
          const SizedBox(height: 16),
          Text(
            'Nothing due right now.',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : AppColors.slate900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Practice cards appear here after wingman sessions surface '
            'a recurring mistake. Pull to refresh.',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 14,
              color: isDark ? AppColors.slate400 : AppColors.slate500,
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
  final VoidCallback onRetry;

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
                size: 48, color: AppColors.error),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                fontSize: 14,
                color: isDark ? AppColors.slate300 : AppColors.slate600,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

// Keep the import-cycle happy (DateFormat reserved for future use).
// ignore: unused_element
String _fmt(DateTime d) => DateFormat.yMMMd().format(d.toLocal());
