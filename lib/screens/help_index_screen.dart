import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/help_content.dart';
import '../routes/app_routes.dart';
import '../theme/design_tokens.dart';
import '../widgets/help_sheet.dart';

/// Searchable index of every [HelpEntry]. Reachable from the app drawer.
class HelpIndexScreen extends StatefulWidget {
  const HelpIndexScreen({super.key});

  @override
  State<HelpIndexScreen> createState() => _HelpIndexScreenState();
}

class _HelpIndexScreenState extends State<HelpIndexScreen> {
  String _query = '';

  List<MapEntry<HelpScreen, HelpEntry>> get _filtered {
    final all = HelpContent.entries.entries.toList();
    if (_query.isEmpty) return all;
    final q = _query.toLowerCase();
    return all.where((e) {
      final entry = e.value;
      return entry.title.toLowerCase().contains(q) ||
          entry.subtitle.toLowerCase().contains(q) ||
          entry.overview.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? Colors.white : AppColors.slate900;
    final muted = isDark ? AppColors.slate300 : AppColors.slate600;
    final bg =
        isDark ? AppColors.backgroundDark : AppColors.backgroundLight;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Help & tips',
          style: GoogleFonts.manrope(
            fontWeight: FontWeight.w800,
            color: fg,
          ),
        ),
        iconTheme: IconThemeData(color: fg),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Replay tutorial banner
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                onTap: () => Navigator.pushNamed(
                  context,
                  AppRoutes.onboarding,
                ),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.glassPrimary,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(
                      color: AppColors.glassPrimaryBorder,
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withAlpha(40),
                          borderRadius:
                              BorderRadius.circular(AppRadius.md),
                        ),
                        child: const Icon(
                          Icons.replay_rounded,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Replay tutorial',
                              style: GoogleFonts.manrope(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: fg,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'See the welcome carousel again',
                              style: GoogleFonts.manrope(
                                fontSize: 12.5,
                                color: muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: muted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Search
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                onChanged: (v) => setState(() => _query = v.trim()),
                style: GoogleFonts.manrope(color: fg),
                decoration: InputDecoration(
                  hintText: 'Search help…',
                  hintStyle: GoogleFonts.manrope(color: muted),
                  prefixIcon: Icon(Icons.search_rounded, color: muted),
                  filled: true,
                  fillColor: isDark
                      ? AppColors.surfaceDark
                      : Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    borderSide: BorderSide(
                      color: isDark
                          ? AppColors.surfaceDarkHighlight
                          : AppColors.slate200,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    borderSide: BorderSide(
                      color: isDark
                          ? AppColors.surfaceDarkHighlight
                          : AppColors.slate200,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    borderSide: const BorderSide(
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
            ),
            // List
            Expanded(
              child: ListView.separated(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: _filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final entry = _filtered[i];
                  return _HelpTile(
                    screen: entry.key,
                    entry: entry.value,
                    isDark: isDark,
                    fg: fg,
                    muted: muted,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HelpTile extends StatelessWidget {
  final HelpScreen screen;
  final HelpEntry entry;
  final bool isDark;
  final Color fg;
  final Color muted;

  const _HelpTile({
    required this.screen,
    required this.entry,
    required this.isDark,
    required this.fg,
    required this.muted,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isDark ? AppColors.surfaceDark : Colors.white,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () => HelpSheet.show(context, screen),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: isDark
                  ? AppColors.surfaceDarkHighlight
                  : AppColors.slate200,
              width: 0.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.glassPrimary,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  entry.icon,
                  size: 20,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      style: GoogleFonts.manrope(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: fg,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.subtitle,
                      style: GoogleFonts.manrope(
                        fontSize: 12.5,
                        color: muted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: muted),
            ],
          ),
        ),
      ),
    );
  }
}
