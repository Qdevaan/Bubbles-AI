import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// A reusable "Feature Flag" screen shown for features that are not yet
/// released. Displays a polished, animated coming-soon UI instead of a
/// jarring "coming soon" text or an empty scaffold.
class _FeatureFlagScreen extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color? accentColor;
  final List<String> upcomingFeatures;

  const _FeatureFlagScreen({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.accentColor,
    this.upcomingFeatures = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accent = accentColor ?? cs.primary;

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
              // Animated glowing icon
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      accent.withOpacity(0.3),
                      accent.withOpacity(0.05),
                    ],
                  ),
                  border: Border.all(
                    color: accent.withOpacity(0.4),
                    width: 1.5,
                  ),
                ),
                child: Icon(icon, size: 52, color: accent),
              )
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .scaleXY(end: 1.05, duration: 2000.ms, curve: Curves.easeInOut),

              const SizedBox(height: 32),

              // "Coming Soon" badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: accent.withOpacity(0.4)),
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
                  color: cs.onSurface.withOpacity(0.6),
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
                      color: cs.onSurface.withOpacity(0.8),
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
                              color: cs.onSurface.withOpacity(0.7),
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

// ═══════════════════════════════════════════════════════════════════════════════
// Public screen classes — each is a thin wrapper around _FeatureFlagScreen
// ═══════════════════════════════════════════════════════════════════════════════

class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context) => const _FeatureFlagScreen(
        title: 'Task Manager',
        icon: Icons.task_alt_rounded,
        accentColor: Color(0xFF6366F1),
        subtitle:
            'Bubbles will intelligently extract and track action items from '
            'your conversations, automatically turning spoken commitments into '
            'structured, prioritized tasks.',
        upcomingFeatures: [
          'Auto-extraction from live sessions',
          'Priority scoring (low / medium / high / urgent)',
          'Due date parsing from natural language',
          'Push notification reminders',
        ],
      );
}

class HealthDashboardScreen extends StatelessWidget {
  const HealthDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) => const _FeatureFlagScreen(
        title: 'Health Dashboard',
        icon: Icons.monitor_heart_outlined,
        accentColor: Color(0xFF10B981),
        subtitle:
            'A personalized health intelligence layer that learns from your '
            'conversations and connects with wearables to surface meaningful '
            'wellness insights and trends.',
        upcomingFeatures: [
          'Wearable device integration (Apple Health, Fitbit)',
          'Conversational health history tracking',
          'Sleep & recovery trend charts',
          'AI-generated wellness recommendations',
        ],
      );
}

class TripsPlannerScreen extends StatelessWidget {
  const TripsPlannerScreen({super.key});

  @override
  Widget build(BuildContext context) => const _FeatureFlagScreen(
        title: 'Trip Planner',
        icon: Icons.flight_takeoff_rounded,
        accentColor: Color(0xFFF59E0B),
        subtitle:
            'Bubbles will listen to your travel discussions and automatically '
            'build itineraries, track bookings, and surface local '
            'recommendations — all from natural conversation.',
        upcomingFeatures: [
          'Itinerary extraction from conversations',
          'Flight & hotel booking tracking',
          'Destination entity knowledge graph',
          'Offline map integration',
        ],
      );
}

class ExpenseTrackerScreen extends StatelessWidget {
  const ExpenseTrackerScreen({super.key});

  @override
  Widget build(BuildContext context) => const _FeatureFlagScreen(
        title: 'Expense Tracker',
        icon: Icons.receipt_long_rounded,
        accentColor: Color(0xFFEC4899),
        subtitle:
            'Track and categorize your spending effortlessly. Bubbles will '
            'extract financial discussions from your sessions and help you '
            'build a clear picture of your financial life.',
        upcomingFeatures: [
          'Auto-extraction of expenses from conversations',
          'Category-based spending breakdown',
          'Monthly budget forecasting',
          'Bank statement import',
        ],
      );
}

class SmartHomeDashboardScreen extends StatelessWidget {
  const SmartHomeDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) => const _FeatureFlagScreen(
        title: 'Smart Home',
        icon: Icons.home_outlined,
        accentColor: Color(0xFF8B5CF6),
        subtitle:
            'Control your smart home devices using natural voice commands '
            'through Bubbles. Integrates with Matter, HomeKit, and Google '
            'Home for a truly unified smart home experience.',
        upcomingFeatures: [
          'Matter & HomeKit device control',
          'Voice command automation',
          'Scene & routine management',
          'Energy usage monitoring',
        ],
      );
}

class IntegrationsHubScreen extends StatelessWidget {
  const IntegrationsHubScreen({super.key});

  @override
  Widget build(BuildContext context) => const _FeatureFlagScreen(
        title: 'Integrations Hub',
        icon: Icons.hub_outlined,
        accentColor: Color(0xFF06B6D4),
        subtitle:
            'Connect Bubbles to your favorite apps and services. From '
            'calendar and email to CRM and project management — '
            'unify your digital life in one intelligent assistant.',
        upcomingFeatures: [
          'Google Calendar & Outlook sync',
          'Slack & Teams integration',
          'Notion & Linear connector',
          'OAuth-based LinkedIn & Resume import',
        ],
      );
}

class SubscriptionScreen extends StatelessWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context) => const _FeatureFlagScreen(
        title: 'Bubbles Pro',
        icon: Icons.workspace_premium_rounded,
        // Uses Theme.of(context).colorScheme.primary automatically —
        // changes when user picks a new accent color in Settings.
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
