import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../theme/design_tokens.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/glass_morphism.dart';
import '../widgets/tags_bottom_sheet.dart';
import '../widgets/export_bottom_sheet.dart';
import '../providers/tags_provider.dart';
import '../services/api_service.dart';
import '../routes/app_routes.dart';
import '../services/auth_service.dart';
import '../services/sessions_service.dart';
import '../repositories/sessions_repository.dart';

enum _SortOrder { newestFirst, oldestFirst }

class SessionsScreen extends StatefulWidget {
  final String? initialSearchQuery;
  const SessionsScreen({super.key, this.initialSearchQuery});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  _SortOrder _sortOrder = _SortOrder.newestFirst;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    if (widget.initialSearchQuery != null && widget.initialSearchQuery!.isNotEmpty) {
      _searchController.text = widget.initialSearchQuery!;
      _searchQuery = widget.initialSearchQuery!;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openSortSheet(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return GlassBottomSheet(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.glassBorder : Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                  const SizedBox(height: 16),
                  Text(
                    'Sort by',
                    style: GoogleFonts.manrope(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : AppColors.slate900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...[
                    (
                      _SortOrder.newestFirst,
                      Icons.arrow_downward_rounded,
                      'Newest first',
                    ),
                    (
                      _SortOrder.oldestFirst,
                      Icons.arrow_upward_rounded,
                      'Oldest first',
                    ),
                  ].map((rec) {
                    final (order, icon, label) = rec;
                    final selected = _sortOrder == order;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        icon,
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : (isDark
                                  ? AppColors.slate400
                                  : Colors.grey.shade500),
                        size: 20,
                      ),
                      title: Text(
                        label,
                        style: GoogleFonts.manrope(
                          fontSize: 14,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : (isDark
                                    ? AppColors.slate300
                                    : AppColors.slate700),
                        ),
                      ),
                      trailing: selected
                          ? Icon(
                              Icons.check_circle_rounded,
                              color: Theme.of(context).colorScheme.primary,
                              size: 20,
                            )
                          : null,
                      onTap: () {
                        setState(() => _sortOrder = order);
                        setModal(() {});
                        Navigator.pop(ctx);
                      },
                    );
                  }),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return MeshGradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: DefaultTabController(
          length: 2,
          child: SafeArea(
            child: Column(
              children: [
                // --- Header ---
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(
                          Icons.arrow_back,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            'History',
                            style: GoogleFonts.manrope(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: isDark ? Colors.white : AppColors.slate900,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Sort',
                        onPressed: () => _openSortSheet(context, isDark),
                        icon: Icon(
                          Icons.sort_rounded,
                          color: _sortOrder != _SortOrder.newestFirst
                              ? primary
                              : (isDark
                                    ? AppColors.slate300
                                    : Colors.grey.shade700),
                        ),
                      ),
                    ],
                  ),
                ),

                // --- Search ---
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) =>
                        setState(() => _searchQuery = value.trim().toLowerCase()),
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      color: isDark ? Colors.white : AppColors.slate900,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search conversation titles...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: _searchQuery.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear',
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            ),
                      filled: true,
                      fillColor: isDark ? AppColors.glassWhite : Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.full),
                        borderSide: BorderSide(
                          color: isDark
                              ? AppColors.glassBorder
                              : Colors.grey.shade300,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.full),
                        borderSide: BorderSide(
                          color: isDark
                              ? AppColors.glassBorder
                              : Colors.grey.shade300,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.full),
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                          width: 1.2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),

                // --- Tabs ---
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.glassWhite : Colors.white,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                      border: Border.all(
                        color: isDark
                            ? AppColors.glassBorder
                            : Colors.grey.shade300,
                      ),
                    ),
                    child: TabBar(
                      indicatorSize: TabBarIndicatorSize.tab,
                      dividerColor: Colors.transparent,
                      indicator: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                      labelColor: Colors.white,
                      unselectedLabelColor: isDark
                          ? AppColors.slate300
                          : AppColors.slate700,
                      labelStyle: GoogleFonts.manrope(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                      unselectedLabelStyle: GoogleFonts.manrope(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                      tabs: const [
                        Tab(text: 'Live Session History'),
                        Tab(text: 'Conversation History'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                Expanded(
                  child: TabBarView(
                    children: [
                      LiveSessionsList(
                        searchQuery: _searchQuery,
                        sortOrder: _sortOrder,
                      ),
                      ConsultantHistoryList(
                        searchQuery: _searchQuery,
                        sortOrder: _sortOrder,
                      ),
                    ],
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

// --- TAB 1: LIVE SESSIONS LIST ---
class LiveSessionsList extends StatefulWidget {
  final bool shrinkwrap;
  final String searchQuery;
  final _SortOrder sortOrder;
  const LiveSessionsList({
    super.key,
    this.shrinkwrap = false,
    this.searchQuery = '',
    this.sortOrder = _SortOrder.newestFirst,
  });

  @override
  State<LiveSessionsList> createState() => _LiveSessionsListState();
}

class _LiveSessionsListState extends State<LiveSessionsList> {
  List<Map<String, dynamic>> _sessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSessions(swr: true);
  }

  Future<void> _loadSessions({bool swr = false}) async {
    final userId = AuthService.instance.currentUserId;
    if (userId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final repo = context.read<SessionsRepository>();
    try {
      final result = await repo.getLiveSessions(userId, forceRefresh: !swr);
      if (mounted) {
        setState(() {
          _sessions = result.data ?? [];
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loading && _sessions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    var sessions = _sessions;

    // Apply search
    if (widget.searchQuery.isNotEmpty) {
      sessions = sessions.where((s) {
        final title = (s['title'] ?? '').toString().toLowerCase();
        return title.contains(widget.searchQuery.toLowerCase());
      }).toList();
    }

    // Apply sort
    sessions = List.from(sessions);
    switch (widget.sortOrder) {
      case _SortOrder.newestFirst:
        sessions.sort(
          (a, b) => (b['created_at'] as String).compareTo(
            a['created_at'] as String,
          ),
        );
      case _SortOrder.oldestFirst:
        sessions.sort(
          (a, b) => (a['created_at'] as String).compareTo(
            b['created_at'] as String,
          ),
        );
    }

    if (sessions.isEmpty) {
      return _buildEmptyState('No live sessions yet', Icons.mic_off);
    }

    return RefreshIndicator(
      onRefresh: () => _loadSessions(swr: false),
      child: ListView.builder(
        shrinkWrap: widget.shrinkwrap,
        physics: widget.shrinkwrap
            ? const NeverScrollableScrollPhysics()
            : const AlwaysScrollableScrollPhysics(),
        padding: widget.shrinkwrap
            ? EdgeInsets.zero
            : const EdgeInsets.all(16),
        itemCount: sessions.length,
        itemBuilder: (context, index) {
          final session = sessions[index];
          final date = DateTime.parse(session['created_at']).toLocal();
          final formattedDate = DateFormat('MMM d, h:mm a').format(date);
          final title = session['title'] ?? 'Conversation';

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GestureDetector(
              onTap: () => _showSessionOptions(context, session, title, isDark),
              child: GlassPanel(
                padding: const EdgeInsets.all(16),
                borderRadius: AppRadius.xxl,
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withAlpha(51),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.mic,
                        color: Theme.of(context).colorScheme.primary,
                        size: 22,
                      ),
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
                              color: isDark
                                  ? Colors.white
                                  : AppColors.slate900,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary.withAlpha(38),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'Wingman',
                                    style: GoogleFonts.manrope(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  formattedDate,
                                  style: GoogleFonts.manrope(
                                    fontSize: 12,
                                    color: isDark
                                        ? AppColors.slate400
                                        : AppColors.slate500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    Icon(
                      Icons.chevron_right,
                      color: isDark
                          ? AppColors.slate500
                          : Colors.grey.shade400,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showSessionOptions(BuildContext context, Map<String, dynamic> session, String title, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => GlassBottomSheet(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? AppColors.glassBorder : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Session Options',
              style: GoogleFonts.manrope(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : AppColors.slate900,
              ),
            ),
            const SizedBox(height: 12),
            _buildOptionTile(
              context,
              Icons.school_outlined,
              'Coaching',
              'View AI-generated coaching and feedback',
              () {
                Navigator.pop(context);
                Navigator.pushNamed(context, AppRoutes.sessionAnalytics, arguments: {
                  'sessionId': session['id'],
                  'sessionTitle': title,
                  'initialTab': 1,
                });
              },
              isDark,
            ),
            _buildOptionTile(
              context,
              Icons.analytics_outlined,
              'Analytics',
              'Check sentiment and engagement stats',
              () {
                Navigator.pop(context);
                Navigator.pushNamed(context, AppRoutes.sessionAnalytics, arguments: {
                  'sessionId': session['id'],
                  'sessionTitle': title,
                  'initialTab': 0,
                });
              },
              isDark,
            ),
            _buildOptionTile(
              context,
              Icons.description_outlined,
              'History & Transcript',
              'Review the full conversation log',
              () {
                Navigator.pop(context);
                Navigator.pushNamed(context, AppRoutes.sessionAnalytics, arguments: {
                  'sessionId': session['id'],
                  'sessionTitle': title,
                  'initialTab': 2,
                });
              },
              isDark,
            ),
            _buildOptionTile(
              context,
              Icons.details_outlined,
              'Full Details',
              'Manage tags and feedback for this session',
              () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GenericSessionDetail(
                      isConsultant: false,
                      sessionId: session['id'],
                      title: title,
                    ),
                  ),
                );
              },
              isDark,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionTile(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
    bool isDark,
  ) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withAlpha(30),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 20),
      ),
      title: Text(
        title,
        style: GoogleFonts.manrope(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: isDark ? Colors.white : AppColors.slate900,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.manrope(
          fontSize: 12,
          color: isDark ? AppColors.slate400 : AppColors.slate500,
        ),
      ),
      onTap: onTap,
    );
  }
}

// --- TAB 2: CONSULTANT HISTORY LIST ---
class ConsultantHistoryList extends StatefulWidget {
  final bool shrinkwrap;
  final String searchQuery;
  final _SortOrder sortOrder;
  const ConsultantHistoryList({
    super.key,
    this.shrinkwrap = false,
    this.searchQuery = '',
    this.sortOrder = _SortOrder.newestFirst,
  });

  @override
  State<ConsultantHistoryList> createState() => _ConsultantHistoryListState();
}

class _ConsultantHistoryListState extends State<ConsultantHistoryList> {
  List<Map<String, dynamic>> _sessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSessions(swr: true);
  }

  Future<void> _loadSessions({bool swr = false}) async {
    final userId = AuthService.instance.currentUserId;
    if (userId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final repo = context.read<SessionsRepository>();
    try {
      final result = await repo.getConsultantSessions(userId, forceRefresh: !swr);
      if (mounted) {
        setState(() {
          _sessions = result.data ?? [];
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loading && _sessions.isEmpty) return const Center(child: CircularProgressIndicator());
    var sessions = _sessions;

    // Apply search
    if (widget.searchQuery.isNotEmpty) {
      sessions = sessions.where((s) {
        final title = (s['title'] ?? '').toString().toLowerCase();
        return title.contains(widget.searchQuery);
      }).toList();
    }

    // Apply sort
    sessions = List.from(sessions);
    switch (widget.sortOrder) {
      case _SortOrder.newestFirst:
        sessions.sort(
          (a, b) => (b['created_at'] as String).compareTo(
            a['created_at'] as String,
          ),
        );
      case _SortOrder.oldestFirst:
        sessions.sort(
          (a, b) => (a['created_at'] as String).compareTo(
            b['created_at'] as String,
          ),
        );
    }

    if (sessions.isEmpty) {
      return _buildEmptyState(
        'No consultant chats yet',
        Icons.chat_bubble_outline,
      );
    }

    return ListView.builder(
      shrinkWrap: widget.shrinkwrap,
      physics: widget.shrinkwrap ? const NeverScrollableScrollPhysics() : null,
      padding: widget.shrinkwrap ? EdgeInsets.zero : const EdgeInsets.all(16),
      itemCount: sessions.length,
      itemBuilder: (context, index) {
        final session = sessions[index];
        final date = DateTime.parse(session['created_at']).toLocal();
        final formattedDate = DateFormat('MMM d, h:mm a').format(date);
        final title = session['title'] ?? 'Consultant Chat';

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GenericSessionDetail(
                    isConsultant: true,
                    sessionId: session['id'],
                    title: title,
                  ),
                ),
              );
            },
            child: GlassPanel(
              padding: const EdgeInsets.all(16),
              borderRadius: AppRadius.xxl,
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.purple.withAlpha(38),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.psychology_outlined,
                      color: Colors.purple,
                      size: 22,
                    ),
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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.purple.withAlpha(38),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Consultant',
                                style: GoogleFonts.manrope(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.purple,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              formattedDate,
                              style: GoogleFonts.manrope(
                                fontSize: 12,
                                color: isDark ? AppColors.slate400 : AppColors.slate500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: isDark ? AppColors.slate500 : Colors.grey.shade400,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// --- HELPER: EMPTY STATE ---
Widget _buildEmptyState(String message, IconData icon) {
  return Builder(
    builder: (context) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 52,
              color: isDark ? AppColors.slate700 : Colors.grey.shade300,
            ),
            const SizedBox(height: 14),
            Text(
              message,
              style: GoogleFonts.manrope(
                fontSize: 15,
                color: isDark
                    ? AppColors.slate400
                    : AppColors.slate500,
              ),
            ),
          ],
        ),
      );
    },
  );
}

// --- SUB-SCREEN: CONSULTANT SESSION DETAIL ---

class GenericSessionDetail extends StatefulWidget {
  final String sessionId;
  final String title;
  final bool isConsultant;

  const GenericSessionDetail({
    super.key,
    required this.sessionId,
    required this.title,
    required this.isConsultant,
  });

  @override
  State<GenericSessionDetail> createState() => _GenericSessionDetailState();
}

class _GenericSessionDetailState extends State<GenericSessionDetail> {
  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;
  final Map<String, int> _feedbackMap = {};
  List<Map<String, dynamic>> _sessionTags = [];
  Map<String, dynamic>? _report;
  Map<String, dynamic>? _analytics;

  @override
  void initState() {
    super.initState();
    _loadLogs(swr: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTags();
      _loadReport(swr: true);
      _loadAnalytics(swr: true);
    });
  }

  Future<void> _loadReport({bool swr = false}) async {
    if (widget.isConsultant) return;
    final userId = AuthService.instance.currentUserId;
    if (userId == null) return;

    try {
      final repo = context.read<SessionsRepository>();
      final result = await repo.getCoachingReport(widget.sessionId, userId, forceRefresh: !swr);
      if (mounted) setState(() => _report = result.data);
    } catch (_) {}
  }

  Future<void> _loadAnalytics({bool swr = false}) async {
    if (widget.isConsultant) return;
    final userId = AuthService.instance.currentUserId;
    if (userId == null) return;

    try {
      final repo = context.read<SessionsRepository>();
      final result = await repo.getSessionAnalytics(widget.sessionId, userId, forceRefresh: !swr);
      if (mounted) setState(() => _analytics = result.data);
    } catch (_) {}
  }

  Future<void> _loadLogs({bool swr = false}) async {
    final userId = AuthService.instance.currentUserId;
    if (userId == null) return;

    final repo = context.read<SessionsRepository>();
    try {
      final result = await repo.getSessionLogs(widget.sessionId, widget.isConsultant, userId, forceRefresh: !swr);
      if (mounted) {
        setState(() {
          _logs = result.data ?? [];
          // Pre-populate feedback map from DB if available
          for (var log in _logs) {
            final logId = log['id'] as String?;
            if (logId != null) {
              final fb = log['feedback'] ?? log['feedback_value'] ?? log['rating'];
              if (fb != null && fb is int) {
                _feedbackMap[logId] = fb;
              }
            }
          }
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadTags() async {
    final tags = await context.read<TagsProvider>().getTagsForSession(widget.sessionId);
    if (mounted) setState(() => _sessionTags = tags);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return MeshGradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(
                      Icons.arrow_back,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        widget.title,
                        style: GoogleFonts.manrope(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? Colors.white
                              : AppColors.slate900,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  // Tags button
                  IconButton(
                    icon: Stack(
                      children: [
                        const Icon(Icons.label_outline, size: 22),
                        if (_sessionTags.isNotEmpty)
                          Positioned(
                            right: 0, top: 0,
                            child: Container(
                              width: 8, height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.blue,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                    tooltip: 'Tags',
                    onPressed: () async {
                      await showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Theme.of(context).colorScheme.surface,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                        ),
                        builder: (_) => TagsBottomSheet(
                          sessionId: widget.sessionId,
                          currentTags: _sessionTags,
                        ),
                      );
                      _loadTags();
                    },
                  ),
                  // Export button
                  IconButton(
                    icon: const Icon(Icons.download_outlined, size: 22),
                    tooltip: 'Export Session',
                    onPressed: () => ExportBottomSheet.show(
                      context,
                      widget.sessionId,
                      widget.title,
                      isConsultant: widget.isConsultant,
                    ),
                  ),
                  // View Report button (wingman only)
                  if (!widget.isConsultant)
                    IconButton(
                      icon: const Icon(Icons.analytics_outlined, size: 22),
                      tooltip: 'View Report',
                      onPressed: () => Navigator.pushNamed(
                        context,
                        AppRoutes.sessionAnalytics,
                        arguments: {
                          'sessionId': widget.sessionId,
                          'sessionTitle': widget.title,
                        },
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Builder(
                builder: (context) {
                  if (_loading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final logs = _logs;

                  if (logs.isEmpty) {
                    return Center(
                      child: Text(
                        "No records found.",
                        style: GoogleFonts.manrope(color: AppColors.textMuted),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: logs.length + (_report != null ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (_report != null && index == 0) {
                        return _buildSummaryCard(_report!);
                      }
                      final logIndex = _report != null ? index - 1 : index;
                      final log = logs[logIndex];

                      if (widget.isConsultant) {
                        final question = log['question']?.toString() ?? log['query']?.toString() ?? '';
                        final answer = log['answer']?.toString() ?? log['response']?.toString() ?? '';
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (question.isNotEmpty)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  ChatBubble(text: question, isUser: true),
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      right: 4,
                                      bottom: 8,
                                    ),
                                    child: Text(
                                      'You',
                                      style: GoogleFonts.manrope(
                                        fontSize: 10,
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            if (answer.isNotEmpty)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ChatBubble(
                                    text: answer,
                                    isUser: false,
                                    isAI: true,
                                    speakerLabel: 'Consultant AI',
                                    isHighlighted: _feedbackMap[log['id'] as String? ?? ''] == 1,
                                  ),
                                  // ── Star rating for consultant answer ──
                                  Padding(
                                    padding: const EdgeInsets.only(left: 8, bottom: 4),
                                    child: _StarRating(
                                      logId: log['id'] as String? ?? '',
                                      sessionId: widget.sessionId,
                                      initialValue: _feedbackMap[log['id'] as String? ?? ''],
                                      onRate: (val) {
                                        setState(() => _feedbackMap[log['id'] as String] = val);
                                        final userId = AuthService.instance.currentUserId ?? '';
                                        context.read<ApiService>().saveFeedback(
                                          userId: userId,
                                          sessionId: widget.sessionId,
                                          consultantLogId: log['id'] as String?,
                                          feedbackType: 'star',
                                          value: val,
                                        );
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Feedback saved'), duration: Duration(seconds: 1)),
                                        );
                                      },
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      left: 4,
                                      bottom: 8,
                                    ),
                                    child: Text(
                                      'Consultant AI',
                                      style: GoogleFonts.manrope(
                                        fontSize: 10,
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        );
                        } else {
                          final role =
                              log['role']?.toString().toLowerCase() ?? 'unknown';
                          bool isUser = role == 'user';
                          bool isOther = role == 'other';
                          final isLlm = role == 'llm';
                          return Column(
                            crossAxisAlignment: isUser
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                              ChatBubble(
                                text: log['content'],
                                isUser: isUser,
                                isAI: isLlm,
                                speakerLabel: isUser
                                    ? null
                                    : (isOther ? 'Other' : 'Wingman'),
                                isHighlighted: _feedbackMap[log['id'] as String? ?? ''] == 1,
                              ),
                              // ── Thumbs feedback for LLM advice ──
                              if (isLlm)
                                Padding(
                                  padding: const EdgeInsets.only(left: 8, bottom: 4),
                                  child: _ThumbsFeedback(
                                    logId: log['id'] as String? ?? '',
                                    currentValue: _feedbackMap[log['id'] as String? ?? ''],
                                    onFeedback: (val) {
                                      setState(() => _feedbackMap[log['id'] as String] = val);
                                      final userId = AuthService.instance.currentUserId ?? '';
                                      context.read<ApiService>().saveFeedback(
                                        userId: userId,
                                        sessionId: widget.sessionId,
                                        sessionLogId: log['id'] as String?,
                                        feedbackType: 'thumbs',
                                        value: val,
                                      );
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Feedback saved'), duration: Duration(seconds: 1)),
                                      );
                                    },
                                  ),
                                ),
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: 4,
                                  right: 4,
                                  bottom: 8,
                                ),
                                child: Text(
                                  isUser ? 'You' : (isOther ? 'Other' : 'Wingman'),
                                  style: GoogleFonts.manrope(
                                    fontSize: 10,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ),
                            ],
                          );
                        }
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ));
  }

  Widget _buildSummaryCard(Map<String, dynamic> report) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final summary = report['report_text'] as String?;
    final keyTopics = report['key_topics'] as List?;
    
    if (summary == null && (keyTopics == null || keyTopics.isEmpty)) return const SizedBox();

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.slate800 : AppColors.slate100,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppColors.glassBorder : Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 18, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'AI Summary',
                style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: isDark ? Colors.white : AppColors.slate900,
                ),
              ),
            ],
          ),
          if (summary != null) ...[
            const SizedBox(height: 12),
            Text(
              summary,
              style: GoogleFonts.manrope(
                fontSize: 13,
                color: isDark ? AppColors.slate300 : AppColors.slate700,
                height: 1.5,
              ),
            ),
          ],
          if (keyTopics != null && keyTopics.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: keyTopics.map((t) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  t.toString(),
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              )).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _StarRating extends StatelessWidget {
  final String logId;
  final String sessionId;
  final int? initialValue;
  final ValueChanged<int> onRate;

  const _StarRating({
    required this.logId,
    required this.sessionId,
    this.initialValue,
    required this.onRate,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final starValue = index + 1;
        final isSelected = initialValue != null && initialValue! >= starValue;
        return GestureDetector(
          onTap: () => onRate(starValue),
          child: Icon(
            isSelected ? Icons.star : Icons.star_border,
            size: 20,
            color: isSelected ? Colors.amber : Colors.grey,
          ),
        );
      }),
    );
  }
}

class _ThumbsFeedback extends StatelessWidget {
  final String logId;
  final int? currentValue; // 1 for thumbs up, -1 for thumbs down
  final ValueChanged<int> onFeedback;

  const _ThumbsFeedback({
    required this.logId,
    this.currentValue,
    required this.onFeedback,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(
            currentValue == 1 ? Icons.thumb_up : Icons.thumb_up_outlined,
            size: 18,
            color: currentValue == 1 ? Colors.green : Colors.grey,
          ),
          onPressed: () => onFeedback(1),
          constraints: const BoxConstraints(),
          padding: const EdgeInsets.all(4),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: Icon(
            currentValue == -1 ? Icons.thumb_down : Icons.thumb_down_outlined,
            size: 18,
            color: currentValue == -1 ? Colors.red : Colors.grey,
          ),
          onPressed: () => onFeedback(-1),
          constraints: const BoxConstraints(),
          padding: const EdgeInsets.all(4),
        ),
      ],
    );
  }
}
