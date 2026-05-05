import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/performa.dart';
import '../providers/performa_provider.dart';
import '../repositories/performa_repository.dart';
import '../theme/design_tokens.dart';
import '../widgets/animated_background.dart';

// ── Main Screen ───────────────────────────────────────────────────────────────

class PerformaScreen extends StatefulWidget {
  const PerformaScreen({super.key});

  @override
  State<PerformaScreen> createState() => _PerformaScreenState();
}

class _PerformaScreenState extends State<PerformaScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userId = Supabase.instance.client.auth.currentUser?.id ?? '';
      if (userId.isNotEmpty) context.read<PerformaProvider>().load(userId);
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: Stack(
        children: [
          Positioned.fill(child: AnimatedAmbientBackground(isDark: isDark)),
          SafeArea(
            child: Column(
              children: [
                _buildHeader(context, isDark),
                Expanded(
                  child: Consumer<PerformaProvider>(
                    builder: (ctx, prov, _) {
                      if (prov.isLoading) {
                        return Center(
                          child: CircularProgressIndicator(
                              color: AppColors.primary),
                        );
                      }
                      final p = prov.performa ?? Performa(userId: '');
                      return TabBarView(
                        controller: _tabs,
                        physics: const BouncingScrollPhysics(),
                        children: [
                          _AboutTab(
                              performa: p,
                              onSave: (u) => _save(ctx, u),
                              isDark: isDark),
                          _PeopleTab(
                              performa: p,
                              onSave: (u) => _save(ctx, u),
                              isDark: isDark),
                          _InsightsTab(performa: p, isDark: isDark),
                          _ExportTab(performa: p, isDark: isDark),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
          child: Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 20,
                  color: isDark ? Colors.white : AppColors.slate900,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Performa',
                      style: GoogleFonts.manrope(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : AppColors.slate900,
                      ),
                    ),
                    Text(
                      'Your performance profile',
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        color: isDark ? AppColors.slate400 : AppColors.slate500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _PerformaTabBar(tabs: _tabs, isDark: isDark),
        const SizedBox(height: 4),
      ],
    );
  }

  Future<void> _save(BuildContext ctx, Performa updated) async {
    final userId = Supabase.instance.client.auth.currentUser?.id ?? '';
    if (userId.isEmpty) return;
    await ctx.read<PerformaProvider>().save(userId, updated);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            Text('Saved', style: GoogleFonts.manrope(fontWeight: FontWeight.w600)),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ));
    }
  }
}

// ── Custom Tab Bar ─────────────────────────────────────────────────────────────

class _PerformaTabBar extends StatefulWidget {
  final TabController tabs;
  final bool isDark;
  const _PerformaTabBar({required this.tabs, required this.isDark});

  @override
  State<_PerformaTabBar> createState() => _PerformaTabBarState();
}

class _PerformaTabBarState extends State<_PerformaTabBar> {
  static const _labels = ['About', 'People', 'Insights', 'Export'];

  @override
  void initState() {
    super.initState();
    widget.tabs.addListener(_onTabChange);
  }

  void _onTabChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.tabs.removeListener(_onTabChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _labels.length,
        itemBuilder: (ctx, i) {
          final selected = widget.tabs.index == i;
          return Padding(
            padding: EdgeInsets.only(right: i < _labels.length - 1 ? 8 : 0),
            child: GestureDetector(
              onTap: () => widget.tabs.animateTo(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                decoration: BoxDecoration(
                  color: selected
                      ? primary.withAlpha(25)
                      : (widget.isDark ? AppColors.glassWhite : Colors.white),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  border: Border.all(
                    color: selected
                        ? primary.withAlpha(120)
                        : (widget.isDark
                            ? AppColors.glassBorder
                            : Colors.grey.shade200),
                  ),
                ),
                child: Text(
                  _labels[i],
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? primary
                        : (widget.isDark
                            ? AppColors.slate400
                            : AppColors.slate500),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Shared helpers ─────────────────────────────────────────────────────────────

Widget _inputField(
  BuildContext context,
  TextEditingController c,
  String label, {
  int maxLines = 1,
  bool isDark = false,
}) {
  final primary = Theme.of(context).colorScheme.primary;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 6),
        child: Text(
          label.toUpperCase(),
          style: GoogleFonts.manrope(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: isDark ? AppColors.slate400 : AppColors.slate500,
          ),
        ),
      ),
      TextFormField(
        controller: c,
        maxLines: maxLines,
        style: GoogleFonts.manrope(
          fontSize: 15,
          color: isDark ? Colors.white : AppColors.slate900,
        ),
        decoration: InputDecoration(
          hintText: 'Enter ${label.toLowerCase()}',
          hintStyle: GoogleFonts.manrope(
            fontSize: 15,
            color: isDark ? AppColors.slate500 : AppColors.slate400,
          ),
          filled: true,
          fillColor: isDark ? AppColors.glassInput : Colors.white.withAlpha(200),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            borderSide: BorderSide(
                color: isDark ? AppColors.glassBorder : AppColors.slate200),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            borderSide: BorderSide(
                color: isDark ? AppColors.glassBorder : AppColors.slate200),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            borderSide: BorderSide(color: primary, width: 2),
          ),
        ),
      ),
    ],
  );
}

Widget _sectionLabel(String text, bool isDark) => Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: GoogleFonts.manrope(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: isDark ? AppColors.slate400 : AppColors.slate500,
        ),
      ),
    );

Widget _primaryButton(BuildContext context, String label, VoidCallback onPressed) {
  final primary = Theme.of(context).colorScheme.primary;
  return SizedBox(
    width: double.infinity,
    child: ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
      child: Text(
        label,
        style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
  );
}

// ── Glass card container ───────────────────────────────────────────────────────

class _GlassCard extends StatelessWidget {
  final bool isDark;
  final Widget child;
  const _GlassCard({required this.isDark, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.glassWhite : Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        border: Border.all(
          color: isDark ? AppColors.glassBorder : Colors.grey.shade200,
        ),
      ),
      child: child,
    );
  }
}

// ── Tab 1: About ───────────────────────────────────────────────────────────────

class _AboutTab extends StatefulWidget {
  final Performa performa;
  final void Function(Performa) onSave;
  final bool isDark;
  const _AboutTab(
      {required this.performa, required this.onSave, required this.isDark});

  @override
  State<_AboutTab> createState() => _AboutTabState();
}

class _AboutTabState extends State<_AboutTab> {
  late TextEditingController _name, _role, _industry, _company, _bg;
  String _style = '';
  late List<String> _goals, _scenarios, _languages;

  static const _styleOptions = ['direct', 'diplomatic', 'analytical'];
  static const _styleLabels = ['Direct', 'Diplomatic', 'Analytical'];

  @override
  void initState() {
    super.initState();
    final p = widget.performa;
    _name = TextEditingController(text: p.fullName);
    _role = TextEditingController(text: p.role);
    _industry = TextEditingController(text: p.industry);
    _company = TextEditingController(text: p.company);
    _bg = TextEditingController(text: p.background);
    _style = p.communicationStyle;
    _goals = List.from(p.goals);
    _scenarios = List.from(p.conversationScenarios);
    _languages = List.from(p.languages);
  }

  @override
  void dispose() {
    _name.dispose();
    _role.dispose();
    _industry.dispose();
    _company.dispose();
    _bg.dispose();
    super.dispose();
  }

  Performa _build() => widget.performa.copyWith(
        fullName: _name.text.trim(),
        role: _role.text.trim(),
        industry: _industry.text.trim(),
        company: _company.text.trim(),
        background: _bg.text.trim(),
        communicationStyle: _style,
        goals: _goals,
        conversationScenarios: _scenarios,
        languages: _languages,
      );

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final primary = Theme.of(context).colorScheme.primary;
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Identity
          _GlassCard(
            isDark: isDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionLabel('Identity', isDark),
                _inputField(context, _name, 'Full name', isDark: isDark),
                const SizedBox(height: 14),
                _inputField(context, _role, 'Role / Title', isDark: isDark),
                const SizedBox(height: 14),
                _inputField(context, _company, 'Company', isDark: isDark),
                const SizedBox(height: 14),
                _inputField(context, _industry, 'Industry', isDark: isDark),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Communication style pill selector
          _GlassCard(
            isDark: isDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionLabel('Communication Style', isDark),
                Row(
                  children: List.generate(_styleOptions.length, (i) {
                    final sel = _style == _styleOptions[i];
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: i < 2 ? 8 : 0),
                        child: GestureDetector(
                          onTap: () =>
                              setState(() => _style = _styleOptions[i]),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: sel
                                  ? primary.withAlpha(25)
                                  : Colors.transparent,
                              borderRadius:
                                  BorderRadius.circular(AppRadius.full),
                              border: Border.all(
                                color: sel
                                    ? primary.withAlpha(120)
                                    : (isDark
                                        ? AppColors.glassBorder
                                        : AppColors.slate200),
                              ),
                            ),
                            child: Text(
                              _styleLabels[i],
                              textAlign: TextAlign.center,
                              style: GoogleFonts.manrope(
                                fontSize: 12,
                                fontWeight:
                                    sel ? FontWeight.w700 : FontWeight.w500,
                                color: sel
                                    ? primary
                                    : (isDark
                                        ? AppColors.slate400
                                        : AppColors.slate500),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Chips: goals, scenarios, languages
          _GlassCard(
            isDark: isDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ChipSection(
                  label: 'Goals',
                  items: _goals,
                  isDark: isDark,
                  onChanged: (v) => setState(() => _goals = v),
                ),
                const SizedBox(height: 16),
                _ChipSection(
                  label: 'Conversation Scenarios',
                  items: _scenarios,
                  isDark: isDark,
                  onChanged: (v) => setState(() => _scenarios = v),
                ),
                const SizedBox(height: 16),
                _ChipSection(
                  label: 'Languages',
                  items: _languages,
                  isDark: isDark,
                  onChanged: (v) => setState(() => _languages = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Background
          _GlassCard(
            isDark: isDark,
            child: _inputField(
              context, _bg, 'Background',
              maxLines: 4, isDark: isDark,
            ),
          ),
          const SizedBox(height: 24),
          _primaryButton(context, 'Save Changes', () => widget.onSave(_build())),
        ],
      ),
    );
  }
}

// ── Tab 2: People ──────────────────────────────────────────────────────────────

class _PeopleTab extends StatefulWidget {
  final Performa performa;
  final void Function(Performa) onSave;
  final bool isDark;
  const _PeopleTab(
      {required this.performa, required this.onSave, required this.isDark});

  @override
  State<_PeopleTab> createState() => _PeopleTabState();
}

class _PeopleTabState extends State<_PeopleTab> {
  late List<PerformaContact> _contacts;
  late List<String> _keywords;

  @override
  void initState() {
    super.initState();
    _contacts = List.from(widget.performa.recurringContacts);
    _keywords = List.from(widget.performa.customKeywords);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final primary = Theme.of(context).colorScheme.primary;
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Key People card
          _GlassCard(
            isDark: isDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: _sectionLabel('Key People', isDark)),
                    GestureDetector(
                      onTap: _addContact,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: primary.withAlpha(20),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.person_add_rounded,
                            size: 18, color: primary),
                      ),
                    ),
                  ],
                ),
                if (_contacts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text(
                        'No contacts yet.\nAdd key people you interact with.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.manrope(
                          fontSize: 13,
                          color: isDark
                              ? AppColors.slate400
                              : AppColors.slate500,
                        ),
                      ),
                    ),
                  )
                else
                  ..._contacts.asMap().entries.map((e) => _ContactTile(
                        contact: e.value,
                        isDark: isDark,
                        onEdit: () => _editContact(e.key, e.value),
                        onDelete: () => setState(() {
                          _contacts.removeAt(e.key);
                          _save();
                        }),
                      )),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Watch Keywords card
          _GlassCard(
            isDark: isDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionLabel('Watch Keywords', isDark),
                Text(
                  'Topics to track across your sessions',
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    color: isDark ? AppColors.slate400 : AppColors.slate500,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ..._keywords.map((k) => _StyledChip(
                          label: k,
                          isDark: isDark,
                          onDeleted: () => setState(() {
                            _keywords.remove(k);
                            _save();
                          }),
                        )),
                    _AddChip(isDark: isDark, onTap: _addKeyword),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _addContact() => _editContact(null, null);

  void _editContact(int? idx, PerformaContact? existing) {
    final namec = TextEditingController(text: existing?.name ?? '');
    final relc = TextEditingController(text: existing?.relationship ?? '');
    final notec = TextEditingController(text: existing?.notes ?? '');
    final isDark = widget.isDark;
    final primary = Theme.of(context).colorScheme.primary;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : Colors.white,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SheetHandle(isDark: isDark),
                const SizedBox(height: 20),
                Text(
                  existing == null ? 'Add Contact' : 'Edit Contact',
                  style: GoogleFonts.manrope(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : AppColors.slate900,
                  ),
                ),
                const SizedBox(height: 20),
                _inputField(context, namec, 'Name', isDark: isDark),
                const SizedBox(height: 12),
                _inputField(context, relc, 'Relationship', isDark: isDark),
                const SizedBox(height: 12),
                _inputField(context, notec, 'Notes', isDark: isDark),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(AppRadius.lg)),
                          side: BorderSide(
                              color: isDark
                                  ? AppColors.glassBorder
                                  : AppColors.slate200),
                          foregroundColor: isDark
                              ? Colors.white70
                              : AppColors.slate600,
                        ),
                        child: Text('Cancel',
                            style: GoogleFonts.manrope(
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          final contact = PerformaContact(
                            name: namec.text.trim(),
                            relationship: relc.text.trim(),
                            notes: notec.text.trim(),
                          );
                          setState(() {
                            if (idx != null)
                              _contacts[idx] = contact;
                            else
                              _contacts.add(contact);
                          });
                          _save();
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(AppRadius.lg)),
                        ),
                        child: Text('Save',
                            style: GoogleFonts.manrope(
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _addKeyword() {
    final c = TextEditingController();
    final isDark = widget.isDark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : Colors.white,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SheetHandle(isDark: isDark),
                const SizedBox(height: 20),
                Text(
                  'Add Keyword',
                  style: GoogleFonts.manrope(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : AppColors.slate900,
                  ),
                ),
                const SizedBox(height: 20),
                _inputField(context, c, 'Keyword', isDark: isDark),
                const SizedBox(height: 24),
                _primaryButton(context, 'Add Keyword', () {
                  final v = c.text.trim();
                  if (v.isNotEmpty)
                    setState(() {
                      _keywords.add(v);
                      _save();
                    });
                  Navigator.pop(context);
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _save() => widget.onSave(widget.performa.copyWith(
        recurringContacts: _contacts,
        customKeywords: _keywords,
      ));
}

// ── Tab 3: AI Insights ─────────────────────────────────────────────────────────

class _InsightsTab extends StatelessWidget {
  final Performa performa;
  final bool isDark;
  const _InsightsTab({required this.performa, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final insights = performa.aiInsights.where((i) => i.approved).toList();
    if (insights.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lightbulb_outline_rounded,
                  size: 48,
                  color: isDark ? AppColors.slate500 : AppColors.slate300),
              const SizedBox(height: 16),
              Text(
                'No AI insights yet',
                style: GoogleFonts.manrope(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : AppColors.slate900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Complete a few sessions to see patterns and insights here.',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  color: isDark ? AppColors.slate400 : AppColors.slate500,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: insights.length,
      itemBuilder: (ctx, i) {
        final insight = insights[i];
        final pct = (insight.confidence * 100).round();
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _GlassCard(
            isDark: isDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  insight.text,
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : AppColors.slate900,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: insight.confidence,
                          minHeight: 4,
                          backgroundColor:
                              isDark ? AppColors.glassBorder : AppColors.slate200,
                          valueColor:
                              const AlwaysStoppedAnimation(AppColors.primary),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '$pct%',
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'confidence',
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    color: isDark ? AppColors.slate500 : AppColors.slate400,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Tab 4: Export ──────────────────────────────────────────────────────────────

class _ExportTab extends StatelessWidget {
  final Performa performa;
  final bool isDark;
  const _ExportTab({required this.performa, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: _GlassCard(
        isDark: isDark,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel('Export Profile', isDark),
            Text(
              'Share or back up your Performa profile.',
              style: GoogleFonts.manrope(
                fontSize: 13,
                color: isDark ? AppColors.slate400 : AppColors.slate500,
              ),
            ),
            const SizedBox(height: 20),
            _ExportTile(
              icon: Icons.code_rounded,
              title: 'JSON',
              subtitle: 'Machine-readable format',
              accent: AppColors.primary,
              isDark: isDark,
              onTap: () => _doJson(context),
            ),
            const SizedBox(height: 10),
            _ExportTile(
              icon: Icons.description_rounded,
              title: 'Markdown',
              subtitle: 'Human-readable text file',
              accent: const Color(0xFF34D399),
              isDark: isDark,
              onTap: () => _doMarkdown(context),
            ),
            const SizedBox(height: 10),
            _ExportTile(
              icon: Icons.picture_as_pdf_rounded,
              title: 'PDF',
              subtitle: 'Formatted document',
              accent: const Color(0xFFF43F5E),
              isDark: isDark,
              onTap: () => _doPdf(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _doJson(BuildContext ctx) async {
    try {
      final repo = ctx.read<PerformaRepository>();
      final file = await repo.exportJson(performa);
      await Share.shareXFiles([XFile(file.path)]);
    } catch (e) {
      _showError(ctx, e);
    }
  }

  Future<void> _doMarkdown(BuildContext ctx) async {
    try {
      final repo = ctx.read<PerformaRepository>();
      final file = await repo.exportMarkdown(performa);
      await Share.shareXFiles([XFile(file.path)]);
    } catch (e) {
      _showError(ctx, e);
    }
  }

  Future<void> _doPdf(BuildContext ctx) async {
    try {
      final repo = ctx.read<PerformaRepository>();
      final file = await repo.exportPdf(performa);
      await Share.shareXFiles([XFile(file.path)]);
    } catch (e) {
      _showError(ctx, e);
    }
  }

  void _showError(BuildContext ctx, Object e) =>
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text('Export failed: $e', style: GoogleFonts.manrope()),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
}

// ── Shared sub-widgets ─────────────────────────────────────────────────────────

class _SheetHandle extends StatelessWidget {
  final bool isDark;
  const _SheetHandle({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: isDark ? AppColors.glassBorder : AppColors.slate200,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _ExportTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final bool isDark;
  final VoidCallback onTap;
  const _ExportTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: accent.withAlpha(12),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: accent.withAlpha(50)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.manrope(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : AppColors.slate900,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        color: isDark ? AppColors.slate400 : AppColors.slate500,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: isDark ? AppColors.slate500 : AppColors.slate400),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChipSection extends StatelessWidget {
  final String label;
  final List<String> items;
  final bool isDark;
  final void Function(List<String>) onChanged;
  const _ChipSection({
    required this.label,
    required this.items,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(label, isDark),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...items.map((s) => _StyledChip(
                  label: s,
                  isDark: isDark,
                  onDeleted: () =>
                      onChanged(items.where((x) => x != s).toList()),
                )),
            _AddChipWithInput(
              isDark: isDark,
              hint: 'Add ${label.toLowerCase()}',
              onAdd: (v) => onChanged([...items, v]),
            ),
          ],
        ),
      ],
    );
  }
}

class _StyledChip extends StatelessWidget {
  final String label;
  final bool isDark;
  final VoidCallback onDeleted;
  const _StyledChip(
      {required this.label, required this.isDark, required this.onDeleted});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: primary.withAlpha(15),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: primary.withAlpha(60)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: primary,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onDeleted,
            child: Icon(Icons.close_rounded, size: 14, color: primary),
          ),
        ],
      ),
    );
  }
}

class _AddChip extends StatelessWidget {
  final bool isDark;
  final VoidCallback onTap;
  const _AddChip({required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(
            color: isDark ? AppColors.glassBorder : AppColors.slate200,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded,
                size: 14,
                color: isDark ? AppColors.slate400 : AppColors.slate500),
            const SizedBox(width: 4),
            Text(
              'Add',
              style: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? AppColors.slate400 : AppColors.slate500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddChipWithInput extends StatelessWidget {
  final bool isDark;
  final void Function(String) onAdd;
  final String hint;
  const _AddChipWithInput(
      {required this.isDark, required this.onAdd, required this.hint});

  @override
  Widget build(BuildContext context) {
    return _AddChip(
      isDark: isDark,
      onTap: () {
        final c = TextEditingController();
        final primary = Theme.of(context).colorScheme.primary;
        showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          builder: (_) => Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SheetHandle(isDark: isDark),
                    const SizedBox(height: 20),
                    Text(
                      hint,
                      style: GoogleFonts.manrope(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : AppColors.slate900,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _inputField(context, c, 'Value', isDark: isDark),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          final v = c.text.trim();
                          if (v.isNotEmpty) onAdd(v);
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(AppRadius.lg)),
                        ),
                        child: Text('Add',
                            style: GoogleFonts.manrope(
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ContactTile extends StatelessWidget {
  final PerformaContact contact;
  final bool isDark;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _ContactTile({
    required this.contact,
    required this.isDark,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withAlpha(8) : AppColors.slate50,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
              color: isDark ? AppColors.glassBorder : Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primary.withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  contact.name.isNotEmpty
                      ? contact.name[0].toUpperCase()
                      : '?',
                  style: GoogleFonts.manrope(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contact.name,
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : AppColors.slate900,
                    ),
                  ),
                  if (contact.relationship.isNotEmpty)
                    Text(
                      contact.relationship,
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        color:
                            isDark ? AppColors.slate400 : AppColors.slate500,
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.edit_outlined,
                  size: 18,
                  color: isDark ? AppColors.slate400 : AppColors.slate500),
              onPressed: onEdit,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded,
                  size: 18, color: AppColors.error),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
