import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import '../theme/design_tokens.dart';
import '../widgets/glass_morphism.dart';

/// Full-screen insights viewer with edit, delete, and static caching.
/// Navigated to from the home screen "See All" button.
class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // ── Static cache (survives re-navigation) ────────────────────────────────
  static List<Map<String, dynamic>>? _cachedEvents;
  static List<Map<String, dynamic>>? _cachedHighlights;
  static List<Map<String, dynamic>>? _cachedNotifications;
  static String? _cacheUserId;

  List<Map<String, dynamic>> _events = [];
  List<Map<String, dynamic>> _highlights = [];
  List<Map<String, dynamic>> _notifications = [];
  bool _loading = true;
  String? _error;

  static const _tabs = [
    ('All',       Icons.grid_view_rounded),
    ('Events',    Icons.event_rounded),
    ('Key Facts', Icons.lightbulb_outline_rounded),
    ('Actions',   Icons.check_circle_outline_rounded),
    ('Alerts',    Icons.warning_amber_rounded),
    ('Updates',   Icons.notifications_active_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    final uid = AuthService.instance.currentUser?.id;
    if (_cachedEvents != null && _cacheUserId == uid) {
      _events        = List.from(_cachedEvents!);
      _highlights    = List.from(_cachedHighlights!);
      _notifications = List.from(_cachedNotifications!);
      _loading = false;
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── Load ─────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final user = AuthService.instance.currentUser;
    if (user == null) {
      setState(() { _loading = false; _error = 'Not logged in.'; });
      return;
    }
    final sb = Supabase.instance.client;
    try {
      final evRes = await sb
          .from('events')
          .select('id, title, due_text, description, created_at')
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(50);
      final hlRes = await sb
          .from('highlights')
          .select('id, title, body, highlight_type, is_resolved, created_at')
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(50);
      final ntRes = await sb
          .from('notifications')
          .select('id, title, body, notif_type, is_read, created_at')
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(50);

      if (!mounted) return;
      _events        = List<Map<String, dynamic>>.from(evRes);
      _highlights    = List<Map<String, dynamic>>.from(hlRes);
      _notifications = List<Map<String, dynamic>>.from(ntRes);

      // Populate cache
      _cachedEvents        = List.from(_events);
      _cachedHighlights    = List.from(_highlights);
      _cachedNotifications = List.from(_notifications);
      _cacheUserId         = user.id;

      setState(() { _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  // ── Delete ───────────────────────────────────────────────────────────────

  Future<void> _deleteItem(_InsightItem item) async {
    final sb = Supabase.instance.client;
    try {
      await sb.from(item.table).delete().eq('id', item.id);
      setState(() {
        switch (item.table) {
          case 'events':        _events.removeWhere((e) => e['id'] == item.id);
          case 'highlights':    _highlights.removeWhere((e) => e['id'] == item.id);
          case 'notifications': _notifications.removeWhere((e) => e['id'] == item.id);
        }
        // Keep cache in sync
        _cachedEvents        = List.from(_events);
        _cachedHighlights    = List.from(_highlights);
        _cachedNotifications = List.from(_notifications);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Deleted.'),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(label: 'OK', onPressed: () {}),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Delete failed: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ── Edit ─────────────────────────────────────────────────────────────────

  Future<void> _editItem(_InsightItem item) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (item.table == 'notifications') {
      // Notifications: only toggle read status
      await _toggleNotificationRead(item, isDark);
      return;
    }

    // Find the raw map for this item
    final rawList = item.table == 'events' ? _events : _highlights;
    final raw = rawList.firstWhere(
      (e) => e['id'] == item.id,
      orElse: () => <String, dynamic>{},
    );
    if (raw.isEmpty) return;

    final titleCtrl = TextEditingController(text: raw['title'] as String? ?? '');
    final bodyCtrl  = TextEditingController(
        text: (raw['description'] ?? raw['body']) as String? ?? '');
    final dueCtrl   = TextEditingController(text: raw['due_text'] as String? ?? '');
    String hlType   = (raw['highlight_type'] as String? ?? 'key_fact');

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: StatefulBuilder(
          builder: (ctx, setModal) => GlassBottomSheet(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36, height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.glassBorder : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    item.table == 'events' ? 'Edit Event' : 'Edit Highlight',
                    style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : AppColors.slate900),
                  ),
                  const SizedBox(height: 16),

                  // Title
                  TextField(
                    controller: titleCtrl,
                    style: GoogleFonts.manrope(
                        color: isDark ? Colors.white : AppColors.slate900),
                    decoration: _inputDeco('Title', isDark),
                  ),
                  const SizedBox(height: 12),

                  // Event: due_text; Highlight: type selector
                  if (item.table == 'events') ...[
                    TextField(
                      controller: dueCtrl,
                      style: GoogleFonts.manrope(
                          color: isDark ? Colors.white : AppColors.slate900),
                      decoration: _inputDeco('Due / when (optional)', isDark),
                    ),
                    const SizedBox(height: 12),
                  ] else ...[
                    Text('Type', style: GoogleFonts.manrope(fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isDark ? AppColors.slate400 : AppColors.slate500)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8, runSpacing: 6,
                      children: ['key_fact', 'action_item', 'risk', 'opportunity', 'conflict']
                          .map((t) {
                        final active = hlType == t;
                        final color  = _InsightItem._colorForType(t);
                        return GestureDetector(
                          onTap: () => setModal(() => hlType = t),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: active ? color.withAlpha(46)
                                  : (isDark ? AppColors.glassWhite : Colors.grey.shade100),
                              borderRadius: BorderRadius.circular(AppRadius.full),
                              border: Border.all(
                                  color: active ? color : Colors.transparent, width: 1.5),
                            ),
                            child: Text(_InsightItem._badgeForType(t),
                                style: GoogleFonts.manrope(fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: active ? color
                                        : (isDark ? AppColors.slate400 : Colors.grey.shade600))),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Body / description
                  TextField(
                    controller: bodyCtrl,
                    maxLines: 4,
                    style: GoogleFonts.manrope(
                        color: isDark ? Colors.white : AppColors.slate900),
                    decoration: _inputDeco(
                        item.table == 'events' ? 'Description (optional)' : 'Body',
                        isDark),
                  ),
                  const SizedBox(height: 20),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text('Cancel', style: GoogleFonts.manrope(
                            fontWeight: FontWeight.w700,
                            color: isDark ? AppColors.slate400 : AppColors.slate500)),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (saved != true) return;
    final newTitle = titleCtrl.text.trim();
    if (newTitle.isEmpty) return;

    final sb = Supabase.instance.client;
    try {
      if (item.table == 'events') {
        await sb.from('events').update({
          'title': newTitle,
          if (dueCtrl.text.trim().isNotEmpty) 'due_text': dueCtrl.text.trim()
              else 'due_text': null,
          'description': bodyCtrl.text.trim().isEmpty ? null : bodyCtrl.text.trim(),
        }).eq('id', item.id);
        final idx = _events.indexWhere((e) => e['id'] == item.id);
        if (idx != -1) {
          setState(() {
            _events[idx] = {
              ..._events[idx],
              'title': newTitle,
              'due_text': dueCtrl.text.trim().isEmpty ? null : dueCtrl.text.trim(),
              'description': bodyCtrl.text.trim().isEmpty ? null : bodyCtrl.text.trim(),
            };
            _cachedEvents = List.from(_events);
          });
        }
      } else {
        await sb.from('highlights').update({
          'title': newTitle,
          'body': bodyCtrl.text.trim(),
          'highlight_type': hlType,
        }).eq('id', item.id);
        final idx = _highlights.indexWhere((e) => e['id'] == item.id);
        if (idx != -1) {
          setState(() {
            _highlights[idx] = {
              ..._highlights[idx],
              'title': newTitle,
              'body': bodyCtrl.text.trim(),
              'highlight_type': hlType,
            };
            _cachedHighlights = List.from(_highlights);
          });
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Updated.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _toggleNotificationRead(_InsightItem item, bool isDark) async {
    final raw = _notifications.firstWhere(
      (n) => n['id'] == item.id,
      orElse: () => <String, dynamic>{},
    );
    if (raw.isEmpty) return;
    final nowRead = !(raw['is_read'] == true);
    final sb = Supabase.instance.client;
    try {
      await sb.from('notifications').update({'is_read': nowRead}).eq('id', item.id);
      final idx = _notifications.indexWhere((n) => n['id'] == item.id);
      if (idx != -1) {
        setState(() {
          _notifications[idx] = {..._notifications[idx], 'is_read': nowRead};
          _cachedNotifications = List.from(_notifications);
        });
      }
    } catch (_) {}
  }

  // ── Confirm delete dialog ─────────────────────────────────────────────────

  Future<void> _confirmDelete(_InsightItem item) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => GlassDialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.error.withAlpha(26),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.delete_outline_rounded,
                    color: AppColors.error, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Delete insight?',
                    style: GoogleFonts.manrope(fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : AppColors.slate900)),
              ),
            ]),
            const SizedBox(height: 12),
            Text('This cannot be undone.',
                style: GoogleFonts.manrope(fontSize: 14,
                    color: isDark ? AppColors.slate400 : AppColors.slate500,
                    height: 1.5)),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Cancel', style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppColors.slate400 : AppColors.slate500)),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.error),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete'),
              ),
            ]),
          ],
        ),
      ),
    );
    if (ok == true) await _deleteItem(item);
  }

  // ── Item lists ────────────────────────────────────────────────────────────

  List<_InsightItem> get _allItems {
    final out = [
      ..._events.map(_InsightItem.fromEvent),
      ..._highlights.map(_InsightItem.fromHighlight),
      ..._notifications.map(_InsightItem.fromNotification),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  List<_InsightItem> _itemsForTab(int idx) {
    switch (idx) {
      case 0: return _allItems;
      case 1: return _events.map(_InsightItem.fromEvent).toList();
      case 2: return _highlights
            .where((h) => (h['highlight_type'] ?? '') == 'key_fact')
            .map(_InsightItem.fromHighlight).toList();
      case 3: return _highlights
            .where((h) => (h['highlight_type'] ?? '') == 'action_item')
            .map(_InsightItem.fromHighlight).toList();
      case 4: return _highlights.where((h) {
              final t = h['highlight_type'] ?? '';
              return t == 'risk' || t == 'conflict' ||
                  (t != 'key_fact' && t != 'action_item' && t != 'opportunity');
            }).map(_InsightItem.fromHighlight).toList();
      case 5: return _notifications.map(_InsightItem.fromNotification).toList();
      default: return [];
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) > 300) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor:
            isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
        body: Stack(children: [
          const MeshGradientBackground(),
          SafeArea(
            child: Column(children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                child: Row(children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.arrow_back,
                        color: isDark ? Colors.white : Colors.black87),
                  ),
                  Expanded(
                    child: Text('Insights',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.manrope(fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white : AppColors.slate900)),
                  ),
                  IconButton(
                    onPressed: _load,
                    icon: Icon(Icons.refresh,
                        color: isDark ? Colors.white70 : Colors.grey.shade700),
                  ),
                ]),
              ),

              // Tab bar
              SizedBox(
                height: 38,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _tabs.length,
                  itemBuilder: (ctx, i) => AnimatedBuilder(
                    animation: _tabController,
                    builder: (_, __) {
                      final sel = _tabController.index == i;
                      return GestureDetector(
                        onTap: () {
                          _tabController.animateTo(i);
                          setState(() {});
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: sel
                                ? primary.withAlpha(46)
                                : (isDark ? AppColors.glassWhite : Colors.grey.shade100),
                            borderRadius: BorderRadius.circular(AppRadius.full),
                            border: Border.all(
                              color: sel ? primary
                                  : (isDark ? AppColors.glassBorder : Colors.transparent),
                              width: 1.5,
                            ),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(_tabs[i].$2, size: 14,
                                color: sel ? primary
                                    : (isDark ? AppColors.slate400 : Colors.grey.shade600)),
                            const SizedBox(width: 5),
                            Text(_tabs[i].$1,
                                style: GoogleFonts.manrope(fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: sel ? primary
                                        : (isDark ? AppColors.slate400 : Colors.grey.shade600))),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Content
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? _ErrorState(error: _error!, onRetry: _load, isDark: isDark)
                        : AnimatedBuilder(
                            animation: _tabController,
                            builder: (_, __) {
                              final items = _itemsForTab(_tabController.index);
                              if (items.isEmpty) return _EmptyState(isDark: isDark);
                              return ListView.builder(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                                itemCount: items.length,
                                itemBuilder: (ctx, i) => _InsightTile(
                                  key: ValueKey(items[i].id),
                                  item: items[i],
                                  isDark: isDark,
                                  onEdit: () => _editItem(items[i]),
                                  onDelete: () => _confirmDelete(items[i]),
                                ),
                              );
                            },
                          ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ── Input decoration helper ───────────────────────────────────────────────────

InputDecoration _inputDeco(String label, bool isDark) => InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.manrope(
          color: isDark ? AppColors.slate400 : AppColors.slate500),
      filled: true,
      fillColor: isDark ? AppColors.glassInput : Colors.grey.shade100,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        borderSide: isDark
            ? const BorderSide(color: AppColors.glassBorder)
            : BorderSide.none,
      ),
    );

// ── Data model ────────────────────────────────────────────────────────────────

class _InsightItem {
  final String id;
  final String table; // 'events' | 'highlights' | 'notifications'
  final String title;
  final String body;
  final String badge;
  final Color color;
  final IconData icon;
  final String createdAt;
  final bool isDimmed;

  const _InsightItem({
    required this.id,
    required this.table,
    required this.title,
    required this.body,
    required this.badge,
    required this.color,
    required this.icon,
    required this.createdAt,
    this.isDimmed = false,
  });

  factory _InsightItem.fromEvent(Map<String, dynamic> ev) => _InsightItem(
        id: ev['id'] as String? ?? '',
        table: 'events',
        title: ev['title'] as String? ?? 'Event',
        body: ev['description'] as String? ?? '',
        badge: ev['due_text'] as String? ?? 'Event',
        color: const Color(0xFFF59E0B),
        icon: Icons.event_rounded,
        createdAt: ev['created_at'] as String? ?? '',
      );

  factory _InsightItem.fromHighlight(Map<String, dynamic> hl) {
    final type = (hl['highlight_type'] as String? ?? '').toLowerCase();
    return _InsightItem(
      id: hl['id'] as String? ?? '',
      table: 'highlights',
      title: hl['title'] as String? ?? 'Highlight',
      body: hl['body'] as String? ?? '',
      badge: _badgeForType(type),
      color: _colorForType(type),
      icon: _iconForType(type),
      createdAt: hl['created_at'] as String? ?? '',
      isDimmed: hl['is_resolved'] == true,
    );
  }

  factory _InsightItem.fromNotification(Map<String, dynamic> nt) => _InsightItem(
        id: nt['id'] as String? ?? '',
        table: 'notifications',
        title: nt['title'] as String? ?? 'Update',
        body: nt['body'] as String? ?? '',
        badge: 'Update',
        color: const Color(0xFF6366F1),
        icon: Icons.notifications_active_outlined,
        createdAt: nt['created_at'] as String? ?? '',
        isDimmed: nt['is_read'] == true,
      );

  static Color _colorForType(String t) {
    switch (t) {
      case 'key_fact':    return const Color(0xFF6366F1);
      case 'action_item': return const Color(0xFF10B981);
      case 'risk':        return const Color(0xFFEF4444);
      case 'opportunity': return const Color(0xFFF59E0B);
      case 'conflict':    return const Color(0xFFEC4899);
      default:            return const Color(0xFF64748B);
    }
  }

  static IconData _iconForType(String t) {
    switch (t) {
      case 'key_fact':    return Icons.lightbulb_outline_rounded;
      case 'action_item': return Icons.check_circle_outline_rounded;
      case 'risk':        return Icons.warning_amber_rounded;
      case 'opportunity': return Icons.trending_up_rounded;
      case 'conflict':    return Icons.report_gmailerrorred_outlined;
      default:            return Icons.bookmark_outline_rounded;
    }
  }

  static String _badgeForType(String t) {
    switch (t) {
      case 'key_fact':    return 'Key Fact';
      case 'action_item': return 'Action Item';
      case 'risk':        return 'Risk';
      case 'opportunity': return 'Opportunity';
      case 'conflict':    return 'Conflict';
      default:
        return t.isEmpty
            ? 'Note'
            : t[0].toUpperCase() + t.substring(1).replaceAll('_', ' ');
    }
  }
}

// ── Tile ──────────────────────────────────────────────────────────────────────

class _InsightTile extends StatelessWidget {
  final _InsightItem item;
  final bool isDark;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _InsightTile({
    super.key,
    required this.item,
    required this.isDark,
    required this.onEdit,
    required this.onDelete,
  });

  void _showActions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurface.withAlpha(50),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: item.color.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: item.color.withAlpha(80)),
                ),
                child: Icon(item.icon, color: item.color, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.title,
                      style: GoogleFonts.manrope(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  Text(item.badge,
                      style: GoogleFonts.manrope(fontSize: 12, color: item.color)),
                ]),
              ),
            ]),
            const SizedBox(height: 16),
            const Divider(),
            // Edit (not for notifications — those get toggled)
            if (item.table != 'notifications')
              ListTile(
                leading: Icon(Icons.edit_outlined,
                    color: Theme.of(context).colorScheme.primary),
                title: Text('Edit',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.primary)),
                contentPadding: EdgeInsets.zero,
                onTap: () { Navigator.pop(context); onEdit(); },
              )
            else
              ListTile(
                leading: Icon(Icons.mark_email_read_outlined,
                    color: Theme.of(context).colorScheme.primary),
                title: Text(item.isDimmed ? 'Mark as unread' : 'Mark as read',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.primary)),
                contentPadding: EdgeInsets.zero,
                onTap: () { Navigator.pop(context); onEdit(); },
              ),
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error),
              title: Text('Delete',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error)),
              contentPadding: EdgeInsets.zero,
              onTap: () { Navigator.pop(context); onDelete(); },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('dismiss_${item.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColors.error.withAlpha(200),
          borderRadius: BorderRadius.circular(AppRadius.xxl),
        ),
        child: const Icon(Icons.delete_outline_rounded,
            color: Colors.white, size: 24),
      ),
      confirmDismiss: (_) async {
        onDelete();
        return false; // let _confirmDelete handle actual removal
      },
      child: GestureDetector(
        onLongPress: () => _showActions(context),
        child: Opacity(
          opacity: item.isDimmed ? 0.55 : 1.0,
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: isDark ? AppColors.glassWhite : Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.xxl),
              border: Border(left: BorderSide(color: item.color, width: 3)),
              boxShadow: isDark
                  ? null
                  : [BoxShadow(color: Colors.black.withAlpha(10),
                        blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: item.color.withAlpha(30),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(item.icon, size: 14, color: item.color),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(item.title,
                          style: GoogleFonts.manrope(fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : AppColors.slate900)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: item.color.withAlpha(25),
                        borderRadius: BorderRadius.circular(AppRadius.full),
                        border: Border.all(color: item.color.withAlpha(80)),
                      ),
                      child: Text(item.badge,
                          style: GoogleFonts.manrope(fontSize: 11,
                              fontWeight: FontWeight.w700, color: item.color)),
                    ),
                    const SizedBox(width: 4),
                    // Quick action menu button
                    GestureDetector(
                      onTap: () => _showActions(context),
                      child: Icon(Icons.more_vert_rounded,
                          size: 18,
                          color: isDark ? AppColors.slate500 : Colors.grey.shade400),
                    ),
                  ]),
                  if (item.body.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(item.body,
                        style: GoogleFonts.manrope(fontSize: 13, height: 1.4,
                            color: isDark ? AppColors.slate400 : AppColors.slate500)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Empty / Error states ──────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool isDark;
  const _EmptyState({required this.isDark});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.auto_awesome_outlined, size: 56,
                color: (isDark ? Colors.white : Colors.black).withAlpha(40)),
            const SizedBox(height: 16),
            Text('Nothing here yet',
                style: GoogleFonts.manrope(fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppColors.slate400 : AppColors.slate600)),
            const SizedBox(height: 8),
            Text('Start a session to generate insights.',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(fontSize: 13,
                    color: isDark ? AppColors.slate500 : AppColors.slate400)),
          ]),
        ),
      );
}

class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  final bool isDark;
  const _ErrorState(
      {required this.error, required this.onRetry, required this.isDark});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.error_outline,
                size: 48, color: AppColors.error.withAlpha(150)),
            const SizedBox(height: 12),
            Text(error,
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(fontSize: 13,
                    color: isDark ? AppColors.slate400 : AppColors.slate600)),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ]),
        ),
      );
}
