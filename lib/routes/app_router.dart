import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../screens/about_screen.dart';
import '../screens/connections_screen.dart';
import '../screens/consultant_screen.dart';
import '../screens/data_management_screen.dart';
import '../screens/entity_screen.dart';
import '../screens/expense_tracker_screen.dart';
import '../screens/game_center_screen.dart';
import '../screens/graph_explorer_screen.dart';
import '../screens/health_dashboard_screen.dart';
import '../screens/home_screen.dart';
import '../screens/insights_screen.dart';
import '../screens/integrations_hub_screen.dart';
import '../screens/language_screen.dart';
import '../screens/login_screen.dart';
import '../screens/new_session_screen.dart';
import '../screens/permissions_screen.dart';
import '../screens/profile_completion_screen.dart';
import '../screens/roleplay_setup_screen.dart';
import '../screens/session_analytics_screen.dart';
import '../screens/sessions_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/signup_screen.dart';
import '../screens/smart_home_dashboard_screen.dart';
import '../screens/splash_screen.dart';
import '../screens/subscription_screen.dart';
import '../screens/tasks_screen.dart';
import '../screens/trips_planner_screen.dart';
import '../screens/verify_email_screen.dart';
import '../services/analytics_service.dart';
import '../providers/iot_manager_provider.dart';
import 'router_notifier.dart';

class AppRouter {
  AppRouter._();

  static final RouterNotifier _notifier = RouterNotifier();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static final GoRouter router = GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: '/splash',
    refreshListenable: _notifier,
    redirect: _notifier.redirect,
    observers: [_AnalyticsRouterObserver()],
    routes: [
      GoRoute(
        path: '/splash',
        builder: (_, __) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: '/signup',
        builder: (_, __) => const SignupScreen(),
      ),
      GoRoute(
        path: '/verify-email',
        builder: (_, __) => const VerifyEmailScreen(),
      ),
      GoRoute(
        path: '/profile-completion',
        builder: (_, __) => const ProfileCompletionScreen(),
      ),
      GoRoute(
        path: '/home',
        builder: (_, __) => const HomeScreen(),
      ),
      GoRoute(
        path: '/connections',
        builder: (_, __) => const ConnectionsScreen(),
      ),
      GoRoute(
        path: '/new-session',
        builder: (context, state) {
          final args = state.extra as Map<String, dynamic>?;
          return NewSessionScreen(
            targetEntityId: args?['targetEntityId'] as String?,
            targetEntityName: args?['targetEntityName'] as String?,
          );
        },
      ),
      GoRoute(
        path: '/consultant',
        builder: (_, __) => const ConsultantScreen(),
      ),
      GoRoute(
        path: '/sessions',
        builder: (_, __) => const SessionsScreen(),
      ),
      GoRoute(
        path: '/about',
        builder: (_, __) => const AboutScreen(),
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const SettingsScreen(),
          transitionsBuilder: (context, animation, _, child) => SlideTransition(
            position: Tween(begin: const Offset(-1.0, 0.0), end: Offset.zero)
                .chain(CurveTween(curve: Curves.easeInOut))
                .animate(animation),
            child: child,
          ),
        ),
      ),
      GoRoute(
        path: '/entities',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const EntityScreen(),
          transitionsBuilder: (context, animation, _, child) => SlideTransition(
            position: Tween(begin: const Offset(1.0, 0.0), end: Offset.zero)
                .chain(CurveTween(curve: Curves.easeInOut))
                .animate(animation),
            child: child,
          ),
        ),
      ),
      GoRoute(
        path: '/session-analytics',
        pageBuilder: (context, state) {
          final args = state.extra as Map<String, String>?;
          return CustomTransitionPage(
            key: state.pageKey,
            child: SessionAnalyticsScreen(
              sessionId: args?['sessionId'] ?? '',
              sessionTitle: args?['sessionTitle'] ?? 'Session',
            ),
            transitionsBuilder: (context, animation, _, child) =>
                SlideTransition(
              position: Tween(begin: const Offset(0.0, 1.0), end: Offset.zero)
                  .chain(CurveTween(curve: Curves.easeInOut))
                  .animate(animation),
              child: child,
            ),
          );
        },
      ),
      GoRoute(
        path: '/roleplay-setup',
        builder: (_, __) => const RoleplaySetupScreen(),
      ),
      // /quests and /game-center both point to GameCenterScreen
      GoRoute(
        path: '/quests',
        builder: (_, __) => const GameCenterScreen(),
      ),
      GoRoute(
        path: '/game-center',
        builder: (_, __) => const GameCenterScreen(),
      ),
      GoRoute(
        path: '/graph-explorer',
        builder: (_, __) => const GraphExplorerScreen(),
      ),
      GoRoute(
        path: '/health-dashboard',
        builder: (_, __) => const HealthDashboardScreen(),
      ),
      GoRoute(
        path: '/expenses-tracker',
        builder: (_, __) => const ExpenseTrackerScreen(),
      ),
      GoRoute(
        path: '/tasks',
        builder: (_, __) => const TasksScreen(),
      ),
      GoRoute(
        path: '/smart-home',
        builder: (context, state) => ChangeNotifierProvider(
          create: (_) => IoTManagerProvider(),
          child: const SmartHomeDashboardScreen(),
        ),
      ),
      GoRoute(
        path: '/trips-planner',
        builder: (_, __) => const TripsPlannerScreen(),
      ),
      GoRoute(
        path: '/integrations',
        builder: (_, __) => const IntegrationsHubScreen(),
      ),
      GoRoute(
        path: '/subscription',
        builder: (_, __) => const SubscriptionScreen(),
      ),
      GoRoute(
        path: '/insights',
        builder: (_, __) => const InsightsScreen(),
      ),
      GoRoute(
        path: '/settings/language',
        builder: (_, __) => const LanguageScreen(),
      ),
      GoRoute(
        path: '/settings/permissions',
        builder: (_, __) => const PermissionsScreen(),
      ),
      GoRoute(
        path: '/settings/data',
        builder: (_, __) => const DataManagementScreen(),
      ),
    ],
  );
}

/// Navigator observer that logs screen views to analytics.
class _AnalyticsRouterObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _log(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute != null) _log(newRoute);
  }

  void _log(Route<dynamic> route) {
    final name = route.settings.name;
    if (name == null || name.isEmpty) return;
    AnalyticsService.instance.logAction(
      action: 'screen_view',
      entityType: 'screen',
      details: {'screen': name},
    );
  }
}
