import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:provider/provider.dart';

import '../services/app_cache_service.dart';
import '../services/auth_service.dart';
import '../services/insights_service.dart';
import '../repositories/insights_repository.dart';
import '../cache/cache_constants.dart';
import '../theme/design_tokens.dart';
import '../widgets/glass_morphism.dart';
import '../widgets/animated_background.dart';
import '../widgets/skeleton_loader.dart';
import '../widgets/insights/insights_widgets.dart';

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
    
    _load(swr: true);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Load ─────────────────────────────────────────────────────────────────

  Future<void> _load({bool swr = false}) async {
    final repo = context.read<InsightsRepository>();
    final uid = AuthService.instance.currentUserId;
    if (uid == null) {
      setState(() { _loading = false; _error = 'please_login'; });
      return;
    }

    setState(() { _loading = !swr; _error = null; });
    try {
      final results = await Future.wait([
        repo.getEvents(uid, forceRefresh: !swr),
        repo.getHighlights(uid, forceRefresh: !swr),
        repo.getNotifications(uid, forceRefresh: !swr),
      ]);

      if (!mounted) return;
      setState(() {
        _events = results[0].data ?? [];
        _highlights = results[1].data ?? [];
        _notifications = results[2].data ?? [];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'load_failed'; });
    }
  }

  // ── Delete ───────────────────────────────────────────────────────────────

  Future<void> _deleteItem(InsightItem item) async {
    final uid = AuthService.instance.currentUserId;
    if (uid == null) return;
    final repo = context.read<InsightsRepository>();

    try {
      await repo.deleteItem(item.table, item.id, uid);
      if (!mounted) return;
      setState(() {
        switch (item.table) {
          case 'events':        _events.removeWhere((e) => e['id'] == item.id);
          case 'highlights':    _highlights.removeWhere((e) => e['id'] == item.id);
          case 'notifications': _notifications.removeWhere((e) => e['id'] == item.id);
        }
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

  Future<void> _editItem(InsightItem item) async {
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
                        final color  = InsightItem.colorForType(t);
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
                            child: Text(InsightItem.badgeForType(t),
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
      if (editUid != null) {
        final repo = context.read<InsightsRepository>();
        if (item.table == 'events') {
          repo.l1.deleteGeneric(CacheKeys.insightsEvents(editUid));
          await repo.l2.delete(CacheKeys.insightsEvents(editUid));
        } else if (item.table == 'highlights') {
          repo.l1.deleteGeneric(CacheKeys.insightsHighlights(editUid));
          await repo.l2.delete(CacheKeys.insightsHighlights(editUid));
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

  Future<void> _toggleNotificationRead(InsightItem item, bool isDark) async {
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
    } catch (e) {
      debugPrint('Error toggling notification read: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update notification')),
        );
      }
    }
  }

  // ── Confirm delete dialog ─────────────────────────────────────────────────

  Future<void> _confirmDelete(InsightItem item) async {
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

  List<InsightItem> get _allItems {
    final out = [
      ..._events.map(InsightItem.fromEvent),
      ..._highlights.map(InsightItem.fromHighlight),
      ..._notifications.map(InsightItem.fromNotification),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  List<InsightItem> _itemsForTab(int idx) {
    List<InsightItem> items;
    switch (idx) {
      case 0: items = _allItems;
      case 1: items = _events.map(InsightItem.fromEvent).toList();
      case 2: items = _highlights
            .where((h) => (h['highlight_type'] ?? '') == 'key_fact')
            .map(InsightItem.fromHighlight).toList();
      case 3: items = _highlights
            .where((h) => (h['highlight_type'] ?? '') == 'action_item')
            .map(InsightItem.fromHighlight).toList();
      case 4: items = _highlights.where((h) {
              final t = h['highlight_type'] ?? '';
              return t == 'risk' || t == 'conflict' ||
                  (t != 'key_fact' && t != 'action_item' && t != 'opportunity');
            }).map(InsightItem.fromHighlight).toList();
      case 5: items = _notifications.map(InsightItem.fromNotification).toList();
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
                      InsightStatChip(
                        icon: Icons.event_rounded,
                        color: const Color(0xFFF59E0B),
                        count: _events.length,
                        label: 'Events',
                        isDark: isDark,
                      ),
                      const SizedBox(width: 8),
                      InsightStatChip(
                        icon: Icons.lightbulb_outline_rounded,
                        color: const Color(0xFF6366F1),
                        count: _highlights.length,
                        label: 'Highlights',
                        isDark: isDark,
                      ),
                      const SizedBox(width: 8),
                      InsightStatChip(
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
                        ? InsightsErrorState(error: _error!, onRetry: _load, isDark: isDark)
                        : AnimatedBuilder(
                            animation: _tabController,
                            builder: (_, __) {
                              final items = _itemsForTab(_tabController.index);
                              if (items.isEmpty) {
                                return _searchQuery.isNotEmpty
                                    ? InsightsSearchEmptyState(isDark: isDark, query: _searchQuery)
                                    : InsightsEmptyState(isDark: isDark);
                              }
                              return ListView.builder(
                                controller: _scrollCtrl,
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                                itemCount: items.length,
                                itemBuilder: (ctx, i) => AnimatedInsightTile(
                                  index: i,
                                  child: InsightTile(
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
