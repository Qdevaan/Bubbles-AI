import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:provider/provider.dart';

import '../services/app_cache_service.dart';
import '../services/auth_service.dart';
import '../services/insights_service.dart';
import '../theme/design_tokens.dart';
import '../widgets/glass_morphism.dart';
import '../widgets/animated_background.dart';
import '../widgets/skeleton_loader.dart';

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
  final ScrollController _scrollCtrl = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

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
    final uid = AuthService.instance.currentUserId;
    // context.read is safe in initState() — AppCacheService is a root provider (listen: false)
    final cache = context.read<AppCacheService>();
    if (cache.events != null && cache.cacheUserId == uid) {
      _events        = List.from(cache.events!);
      _highlights    = List.from(cache.highlights!);
      _notifications = List.from(cache.notifications!);
      _loading = false;
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Load ─────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    // Capture cache reference before any await — safe with root provider
    final cache = context.read<AppCacheService>();
    cache.invalidateInsights();
    setState(() { _loading = true; _error = null; });
    final uid = AuthService.instance.currentUserId;
    if (uid == null) {
      setState(() { _loading = false; _error = 'please_login'; });
      return;
    }
    try {
      final events        = await InsightsService.instance.fetchEvents(uid);
      final highlights    = await InsightsService.instance.fetchHighlights(uid);
      final notifications = await InsightsService.instance.fetchNotifications(uid);

      if (!mounted) return;
      _events        = events;
      _highlights    = highlights;
      _notifications = notifications;

      // Populate cache
      cache.setInsights(
        events: _events,
        highlights: _highlights,
        notifications: _notifications,
        userId: uid,
      );

      setState(() { _loading = false; });
    } catch (e) {
      debugPrint('InsightsScreen._load error: $e');
      if (!mounted) return;
      setState(() { _loading = false; _error = 'load_failed'; });
    }
  }

  // ── Delete ───────────────────────────────────────────────────────────────

  Future<void> _deleteItem(_InsightItem item) async {
    try {
      await InsightsService.instance.deleteItem(item.table, item.id);
      setState(() {
        switch (item.table) {
          case 'events':        _events.removeWhere((e) => e['id'] == item.id);
          case 'highlights':    _highlights.removeWhere((e) => e['id'] == item.id);
          case 'notifications': _notifications.removeWhere((e) => e['id'] == item.id);
        }
      });
      // Keep cache in sync — called after setState so lists are updated
      final uid = AuthService.instance.currentUserId;
      if (uid != null && mounted) {
        context.read<AppCacheService>().setInsights(
          events: _events,
          highlights: _highlights,
          notifications: _notifications,
          userId: uid,
        );
      }
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
      debugPrint('InsightsScreen._deleteItem error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Couldn\'t delete that — check your connection and try again.'),
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

    try {
      if (item.table == 'events') {
        await InsightsService.instance.updateEvent(
          id: item.id,
          title: newTitle,
          dueText: dueCtrl.text.trim().isNotEmpty ? dueCtrl.text.trim() : null,
          description: bodyCtrl.text.trim().isEmpty ? null : bodyCtrl.text.trim(),
        );
        final idx = _events.indexWhere((e) => e['id'] == item.id);
        if (idx != -1) {
          setState(() {
            _events[idx] = {
              ..._events[idx],
              'title': newTitle,
              'due_text': dueCtrl.text.trim().isEmpty ? null : dueCtrl.text.trim(),
              'description': bodyCtrl.text.trim().isEmpty ? null : bodyCtrl.text.trim(),
            };
          });
        }
      } else {
        await InsightsService.instance.updateHighlight(
          id: item.id,
          title: newTitle,
          body: bodyCtrl.text.trim(),
          highlightType: hlType,
        );
        final idx = _highlights.indexWhere((e) => e['id'] == item.id);
        if (idx != -1) {
          setState(() {
            _highlights[idx] = {
              ..._highlights[idx],
              'title': newTitle,
              'body': bodyCtrl.text.trim(),
              'highlight_type': hlType,
            };
          });
        }
      }
      // Keep cache in sync after edit
      final editUid = AuthService.instance.currentUserId;
      if (editUid != null && mounted) {
        context.read<AppCacheService>().setInsights(
          events: _events,
          highlights: _highlights,
          notifications: _notifications,
          userId: editUid,
        );
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
      debugPrint('InsightsScreen._editItem error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Couldn\'t save your changes — please try again in a moment.'),
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
    try {
      await InsightsService.instance.updateNotificationReadStatus(
        id: item.id,
        isRead: nowRead,
      );
      final idx = _notifications.indexWhere((n) => n['id'] == item.id);
      if (idx != -1) {
        setState(() {
          _notifications[idx] = {..._notifications[idx], 'is_read': nowRead};
        });
        // Keep cache in sync after toggle
        final toggleUid = AuthService.instance.currentUserId;
        if (toggleUid != null && mounted) {
          context.read<AppCacheService>().setInsights(
            events: _events,
            highlights: _highlights,
            notifications: _notifications,
            userId: toggleUid,
          );
        }
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
    List<_InsightItem> items;
    switch (idx) {
      case 0: items = _allItems;
      case 1: items = _events.map(_InsightItem.fromEvent).toList();
      case 2: items = _highlights
            .where((h) => (h['highlight_type'] ?? '') == 'key_fact')
            .map(_InsightItem.fromHighlight).toList();
      case 3: items = _highlights
            .where((h) => (h['highlight_type'] ?? '') == 'action_item')
            .map(_InsightItem.fromHighlight).toList();
      case 4: items = _highlights.where((h) {
              final t = h['highlight_type'] ?? '';
              return t == 'risk' || t == 'conflict' ||
                  (t != 'key_fact' && t != 'action_item' && t != 'opportunity');
            }).map(_InsightItem.fromHighlight).toList();
      case 5: items = _notifications.map(_InsightItem.fromNotification).toList();
      default: items = [];
    }
    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      items = items.where((i) =>
        i.title.toLowerCase().contains(q) ||
        i.body.toLowerCase().contains(q) ||
        i.badge.toLowerCase().contains(q)
      ).toList();
    }
    return items;
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
          AnimatedAmbientBackground(
            isDark: isDark,
            scrollController: _scrollCtrl,
          ),
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

              // Summary stats header
              if (!_loading && _error == null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Row(
                    children: [
                      _StatChip(
                        icon: Icons.event_rounded,
                        color: const Color(0xFFF59E0B),
                        count: _events.length,
                        label: 'Events',
                        isDark: isDark,
                      ),
                      const SizedBox(width: 8),
                      _StatChip(
                        icon: Icons.lightbulb_outline_rounded,
                        color: const Color(0xFF6366F1),
                        count: _highlights.length,
                        label: 'Highlights',
                        isDark: isDark,
                      ),
                      const SizedBox(width: 8),
                      _StatChip(
                        icon: Icons.notifications_active_outlined,
                        color: const Color(0xFF10B981),
                        count: _notifications.length,
                        label: 'Updates',
                        isDark: isDark,
                      ),
                    ],
                  ),
                ),

              // Search bar
              if (!_loading && _error == null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.glassWhite : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                      border: Border.all(
                        color: isDark ? AppColors.glassBorder : Colors.grey.shade200,
                      ),
                    ),
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (v) => setState(() => _searchQuery = v),
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        color: isDark ? Colors.white : AppColors.slate900,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search insights...',
                        hintStyle: GoogleFonts.manrope(
                          fontSize: 13,
                          color: isDark ? AppColors.slate500 : Colors.grey.shade400,
                        ),
                        prefixIcon: Icon(Icons.search,
                            size: 18,
                            color: isDark ? AppColors.slate500 : Colors.grey.shade400),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? GestureDetector(
                                onTap: () {
                                  _searchCtrl.clear();
                                  setState(() => _searchQuery = '');
                                },
                                child: Icon(Icons.close,
                                    size: 16,
                                    color: isDark ? AppColors.slate400 : Colors.grey.shade500),
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
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
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: SkeletonCardGroup(count: 5),
                      )
                    : _error != null
                        ? _ErrorState(error: _error!, onRetry: _load, isDark: isDark)
                        : AnimatedBuilder(
                            animation: _tabController,
                            builder: (_, __) {
                              final items = _itemsForTab(_tabController.index);
                              if (items.isEmpty) {
                                return _searchQuery.isNotEmpty
                                    ? _SearchEmptyState(isDark: isDark, query: _searchQuery)
                                    : _EmptyState(isDark: isDark);
                              }
                              return ListView.builder(
                                controller: _scrollCtrl,
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                                itemCount: items.length,
                                itemBuilder: (ctx, i) => _AnimatedInsightTile(
                                  index: i,
                                  child: _InsightTile(
                                    key: ValueKey(items[i].id),
                                    item: items[i],
                                    isDark: isDark,
                                    onEdit: () => _editItem(items[i]),
                                    onDelete: () => _confirmDelete(items[i]),
                                  ),
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

class _InsightTile extends StatefulWidget {
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

  @override
  State<_InsightTile> createState() => _InsightTileState();
}

class _InsightTileState extends State<_InsightTile>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late AnimationController _ctrl;
  late Animation<double> _expandAnim;
  late Animation<double> _chevronTurn;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _expandAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _chevronTurn = Tween<double>(begin: 0.0, end: 0.5).animate(_expandAnim);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    _expanded ? _ctrl.forward() : _ctrl.reverse();
  }

  String _formatTime(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isDark = widget.isDark;
    final hasBody = item.body.isNotEmpty;
    final timeStr = _formatTime(item.createdAt);

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
        widget.onDelete();
        return false;
      },
      child: GestureDetector(
        onTap: hasBody ? _toggle : null,
        onLongPress: () => _showActions(context),
        child: Opacity(
          opacity: item.isDimmed ? 0.55 : 1.0,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: isDark ? AppColors.glassWhite : Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.xxl),
              border: Border(left: BorderSide(color: item.color, width: 3)),
              boxShadow: _expanded
                  ? [
                      BoxShadow(
                        color: item.color.withAlpha(isDark ? 30 : 15),
                        blurRadius: 16,
                        spreadRadius: -2,
                      ),
                    ]
                  : isDark
                      ? null
                      : [
                          BoxShadow(
                            color: Colors.black.withAlpha(10),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: item.color.withAlpha(30),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(item.icon, size: 14, color: item.color),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.title,
                              style: GoogleFonts.manrope(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: isDark
                                      ? Colors.white
                                      : AppColors.slate900)),
                          if (timeStr.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(timeStr,
                                  style: GoogleFonts.manrope(
                                      fontSize: 11,
                                      color: isDark
                                          ? AppColors.slate500
                                          : Colors.grey.shade400)),
                            ),
                        ],
                      ),
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
                          style: GoogleFonts.manrope(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: item.color)),
                    ),
                    if (hasBody) ...[
                      const SizedBox(width: 4),
                      RotationTransition(
                        turns: _chevronTurn,
                        child: Icon(Icons.expand_more_rounded,
                            size: 20,
                            color: isDark
                                ? AppColors.slate500
                                : Colors.grey.shade400),
                      ),
                    ] else ...[
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => _showActions(context),
                        child: Icon(Icons.more_vert_rounded,
                            size: 18,
                            color: isDark
                                ? AppColors.slate500
                                : Colors.grey.shade400),
                      ),
                    ],
                  ]),

                  // Preview (collapsed: 1 line)
                  if (hasBody && !_expanded)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(item.body,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.manrope(
                              fontSize: 13,
                              height: 1.4,
                              color: isDark
                                  ? AppColors.slate400
                                  : AppColors.slate500)),
                    ),

                  // Expanded body
                  SizeTransition(
                    sizeFactor: _expandAnim,
                    axisAlignment: -1.0,
                    child: hasBody
                        ? Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Full body in styled container
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.white.withAlpha(5)
                                        : Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isDark
                                          ? AppColors.glassBorder
                                          : Colors.grey.shade100,
                                    ),
                                  ),
                                  child: Text(item.body,
                                      style: GoogleFonts.manrope(
                                          fontSize: 13,
                                          color: isDark
                                              ? AppColors.slate300
                                              : AppColors.slate600,
                                          height: 1.6)),
                                ),
                                const SizedBox(height: 10),
                                // Action buttons row
                                Row(
                                  children: [
                                    _ActionChip(
                                      icon: item.table == 'notifications'
                                          ? Icons.mark_email_read_outlined
                                          : Icons.edit_outlined,
                                      label: item.table == 'notifications'
                                          ? (item.isDimmed
                                              ? 'Mark unread'
                                              : 'Mark read')
                                          : 'Edit',
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                      isDark: isDark,
                                      onTap: widget.onEdit,
                                    ),
                                    const SizedBox(width: 8),
                                    _ActionChip(
                                      icon: Icons.delete_outline_rounded,
                                      label: 'Delete',
                                      color: AppColors.error,
                                      isDark: isDark,
                                      onTap: widget.onDelete,
                                    ),
                                    const Spacer(),
                                    Icon(Icons.touch_app_outlined,
                                        size: 12,
                                        color: isDark
                                            ? AppColors.slate500
                                            : Colors.grey.shade400),
                                    const SizedBox(width: 4),
                                    Text('Tap to collapse',
                                        style: GoogleFonts.manrope(
                                            fontSize: 11,
                                            color: isDark
                                                ? AppColors.slate500
                                                : Colors.grey.shade400)),
                                  ],
                                ),
                              ],
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

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
                  color: widget.item.color.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: widget.item.color.withAlpha(80)),
                ),
                child: Icon(widget.item.icon, color: widget.item.color, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.item.title,
                      style: GoogleFonts.manrope(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  Text(widget.item.badge,
                      style: GoogleFonts.manrope(fontSize: 12, color: widget.item.color)),
                ]),
              ),
            ]),
            const SizedBox(height: 16),
            const Divider(),
            if (widget.item.table != 'notifications')
              ListTile(
                leading: Icon(Icons.edit_outlined,
                    color: Theme.of(context).colorScheme.primary),
                title: Text('Edit',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.primary)),
                contentPadding: EdgeInsets.zero,
                onTap: () { Navigator.pop(context); widget.onEdit(); },
              )
            else
              ListTile(
                leading: Icon(Icons.mark_email_read_outlined,
                    color: Theme.of(context).colorScheme.primary),
                title: Text(widget.item.isDimmed ? 'Mark as unread' : 'Mark as read',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.primary)),
                contentPadding: EdgeInsets.zero,
                onTap: () { Navigator.pop(context); widget.onEdit(); },
              ),
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error),
              title: Text('Delete',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error)),
              contentPadding: EdgeInsets.zero,
              onTap: () { Navigator.pop(context); widget.onDelete(); },
            ),
          ],
        ),
      ),
    );
  }
}

// ── Inline Action Chip ────────────────────────────────────────────────────────

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withAlpha(isDark ? 20 : 12),
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(color: color.withAlpha(60)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: GoogleFonts.manrope(
                    fontSize: 11, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      ),
    );
  }
}

// ── Stat Chip (summary header) ────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final int count;
  final String label;
  final bool isDark;

  const _StatChip({
    required this.icon,
    required this.color,
    required this.count,
    required this.label,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: isDark ? AppColors.glassWhite : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? AppColors.glassBorder : Colors.grey.shade200,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color.withAlpha(25),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 14, color: color),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$count',
                    style: GoogleFonts.manrope(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : AppColors.slate900,
                    ),
                  ),
                  Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      fontSize: 10,
                      color: isDark ? AppColors.slate500 : AppColors.slate400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Animated Insight Tile (stagger fade-in) ───────────────────────────────────

class _AnimatedInsightTile extends StatefulWidget {
  final int index;
  final Widget child;

  const _AnimatedInsightTile({
    required this.index,
    required this.child,
  });

  @override
  State<_AnimatedInsightTile> createState() => _AnimatedInsightTileState();
}

class _AnimatedInsightTileState extends State<_AnimatedInsightTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    // Stagger: delay based on index, capped at 300ms
    final delay = Duration(milliseconds: (widget.index * 50).clamp(0, 300));
    Future.delayed(delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _slide,
        child: widget.child,
      ),
    );
  }
}

// ── Empty / Error states ──────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool isDark;
  const _EmptyState({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ShaderMask(
            shaderCallback: (bounds) => LinearGradient(
              colors: [primary, primary.withAlpha(80)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ).createShader(bounds),
            child: Icon(Icons.auto_awesome_outlined, size: 64,
                color: Colors.white),
          ),
          const SizedBox(height: 16),
          Text('Nothing here yet',
              style: GoogleFonts.manrope(fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppColors.slate400 : AppColors.slate600)),
          const SizedBox(height: 8),
          Text('Start a session to generate\npersonalized insights.',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(fontSize: 13, height: 1.5,
                  color: isDark ? AppColors.slate500 : AppColors.slate400)),
        ]),
      ),
    );
  }
}

class _SearchEmptyState extends StatelessWidget {
  final bool isDark;
  final String query;
  const _SearchEmptyState({required this.isDark, required this.query});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.search_off_rounded, size: 52,
                color: (isDark ? Colors.white : Colors.black).withAlpha(40)),
            const SizedBox(height: 16),
            Text('No results for "$query"',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppColors.slate400 : AppColors.slate600)),
            const SizedBox(height: 8),
            Text('Try a different search term.',
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

  String get _friendlyTitle {
    if (error == 'please_login') return 'You\'re not signed in';
    return 'Something went wrong';
  }

  String get _friendlySubtitle {
    if (error == 'please_login') {
      return 'Sign in to see your insights and highlights.';
    }
    return 'We couldn\'t load your insights right now.\nPlease check your internet and try again.';
  }

  IconData get _icon {
    if (error == 'please_login') return Icons.lock_outline_rounded;
    return Icons.cloud_off_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (isDark ? Colors.white : Colors.black).withAlpha(10),
            ),
            child: Icon(_icon,
                size: 36,
                color: isDark ? AppColors.slate400 : AppColors.slate500),
          ),
          const SizedBox(height: 16),
          Text(_friendlyTitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : AppColors.slate900)),
          const SizedBox(height: 8),
          Text(_friendlySubtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                  fontSize: 13,
                  height: 1.5,
                  color: isDark ? AppColors.slate400 : AppColors.slate500)),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try Again'),
            style: FilledButton.styleFrom(
              backgroundColor: primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

