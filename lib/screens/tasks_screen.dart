import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../models/task_event_models.dart';
import '../providers/task_event_provider.dart';
import '../services/auth_service.dart';
import '../widgets/app_dialog.dart';
import '../widgets/app_snack_bar.dart';
import '../widgets/skeleton_loader.dart';
class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  bool _showCompleted = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final userId = AuthService.instance.currentUserId;
    if (userId == null) return;
    await context.read<TaskEventProvider>().loadData(userId);
  }

  List<EventItem> _filter(List<EventItem> all) {
    final filtered = _showCompleted ? all : all.where((e) => !e.isCompleted).toList();
    filtered.sort((a, b) {
      if (a.isCompleted != b.isCompleted) return a.isCompleted ? 1 : -1;
      final ad = a.startTime ?? a.createdAt;
      final bd = b.startTime ?? b.createdAt;
      return ad.compareTo(bd);
    });
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final provider = context.watch<TaskEventProvider>();
    final events = _filter(provider.events);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: cs.onSurface,
        title: const Text('Action Items'),
        actions: [
          IconButton(
            tooltip: _showCompleted ? 'Hide completed' : 'Show completed',
            icon: Icon(_showCompleted
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded),
            onPressed: () => setState(() => _showCompleted = !_showCompleted),
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: _buildBody(theme, cs, provider, events),
        ),
      ),
    );
  }

  Widget _buildBody(
    ThemeData theme,
    ColorScheme cs,
    TaskEventProvider provider,
    List<EventItem> events,
  ) {
    if (provider.isLoading && provider.events.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: const [
          SkeletonListTile(),
          SizedBox(height: 12),
          SkeletonListTile(),
          SizedBox(height: 12),
          SkeletonListTile(),
        ],
      );
    }

    if (events.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.15),
          Center(
            child: _EmptyState(
              showCompleted: _showCompleted,
              accent: cs.primary,
              onSurface: cs.onSurface,
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: events.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final event = events[i];
        return _TaskTile(
          event: event,
          accent: cs.primary,
          onToggle: () => context
              .read<TaskEventProvider>()
              .toggleEventCompleted(event.id),
          onDelete: () => _confirmDelete(event),
        ).animate().fadeIn(delay: (i * 40).ms).slideY(begin: 0.1);
      },
    );
  }

  Future<void> _confirmDelete(EventItem event) async {
    final ok = await AppDialog.confirm(
      context: context,
      title: 'Delete action item?',
      message: '"${event.title}" will be permanently removed.',
      confirmLabel: 'Delete',
      tone: AppDialogTone.danger,
    );
    if (!ok || !mounted) return;
    try {
      await context.read<TaskEventProvider>().deleteEvent(event.id);
    } catch (e) {
      if (!mounted) return;
      AppSnackBar.show(context, message: 'Delete failed: $e');
    }
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({
    required this.event,
    required this.accent,
    required this.onToggle,
    required this.onDelete,
  });

  final EventItem event;
  final Color accent;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final done = event.isCompleted;
    final dueLabel = _formatDue(event);

    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: onToggle,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done ? accent : Colors.transparent,
                    border: Border.all(
                      color: done ? accent : cs.onSurface.withValues(alpha: 0.3),
                      width: 2,
                    ),
                  ),
                  child: done
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface
                            .withValues(alpha: done ? 0.5 : 1.0),
                        decoration: done ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (event.description != null &&
                        event.description!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        event.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                    if (dueLabel != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 14,
                            color: cs.onSurface.withValues(alpha: 0.55),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            dueLabel,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: cs.onSurface.withValues(alpha: 0.55),
                            ),
                          ),
                          if (event.location != null &&
                              event.location!.isNotEmpty) ...[
                            const SizedBox(width: 10),
                            Icon(
                              Icons.place_rounded,
                              size: 14,
                              color: cs.onSurface.withValues(alpha: 0.55),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                event.location!,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color:
                                      cs.onSurface.withValues(alpha: 0.55),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Delete',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.delete_outline_rounded,
                  size: 20,
                  color: cs.onSurface.withValues(alpha: 0.5),
                ),
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String? _formatDue(EventItem event) {
    if (event.dueText != null && event.dueText!.isNotEmpty) return event.dueText;
    final t = event.startTime;
    if (t == null) return null;
    final now = DateTime.now();
    final local = t.toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(local.year, local.month, local.day);
    final diff = that.difference(today).inDays;
    final time = event.isAllDay
        ? ''
        : ' ${_pad(local.hour)}:${_pad(local.minute)}';
    if (diff == 0) return 'Today$time';
    if (diff == 1) return 'Tomorrow$time';
    if (diff == -1) return 'Yesterday$time';
    if (diff > 1 && diff < 7) return _weekday(local.weekday) + time;
    return '${local.year}-${_pad(local.month)}-${_pad(local.day)}$time';
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');
  static String _weekday(int w) =>
      ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][w - 1];
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.showCompleted,
    required this.accent,
    required this.onSurface,
  });

  final bool showCompleted;
  final Color accent;
  final Color onSurface;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  accent.withValues(alpha: 0.25),
                  accent.withValues(alpha: 0.04),
                ],
              ),
            ),
            child: Icon(Icons.task_alt_rounded, size: 44, color: accent),
          ),
          const SizedBox(height: 20),
          Text(
            showCompleted ? 'No action items yet' : 'All caught up',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            showCompleted
                ? 'Bubbles will extract action items from your conversations and list them here.'
                : 'Nothing pending. Toggle the filter to see completed items.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: onSurface.withValues(alpha: 0.6),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// A reusable "Feature Flag" screen shown for features that are not yet
/// released. Used for the Subscription / Bubbles Pro paywall preview.
class _FeatureFlagScreen extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<String> upcomingFeatures;

  const _FeatureFlagScreen({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.upcomingFeatures = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accent = cs.primary;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(title),
        foregroundColor: cs.onSurface,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      accent.withValues(alpha: 0.3),
                      accent.withValues(alpha: 0.05),
                    ],
                  ),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                ),
                child: Icon(icon, size: 52, color: accent),
              )
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .scaleXY(end: 1.05, duration: 2000.ms, curve: Curves.easeInOut),
              const SizedBox(height: 32),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: accent.withValues(alpha: 0.4)),
                ),
                child: Text(
                  'COMING SOON',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
              ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.3),
              const SizedBox(height: 16),
              Text(
                title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
                textAlign: TextAlign.center,
              ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.2),
              const SizedBox(height: 12),
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurface.withValues(alpha: 0.6),
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ).animate().fadeIn(delay: 400.ms),
              if (upcomingFeatures.isNotEmpty) ...[
                const SizedBox(height: 32),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'What\'s planned:',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ...upcomingFeatures.asMap().entries.map((entry) {
                  final delay = (500 + entry.key * 80).ms;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accent,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            entry.value,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurface.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(delay: delay).slideX(begin: -0.2);
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class SubscriptionScreen extends StatelessWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context) => const _FeatureFlagScreen(
        title: 'Bubbles Pro',
        icon: Icons.workspace_premium_rounded,
        subtitle:
            'Unlock unlimited sessions, priority model access, and advanced '
            'analytics with Bubbles Pro. Early supporters will receive '
            'lifetime pricing when we launch.',
        upcomingFeatures: [
          'Unlimited live wingman sessions',
          'Priority access to 70B consultant model',
          'Advanced coaching analytics',
          'Multi-device handoff (Continuity)',
          'Early access to new features',
        ],
      );
}
