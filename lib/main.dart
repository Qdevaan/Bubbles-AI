import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'services/connection_service.dart';
import 'services/api_service.dart';
import 'services/livekit_service.dart';
import 'services/deepgram_service.dart';
import 'services/voice_assistant_service.dart';
import 'services/wake_word_service.dart';
import 'services/analytics_service.dart';
import 'services/device_service.dart';
import 'providers/theme_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/consultant_provider.dart';
import 'providers/session_provider.dart';
import 'providers/home_provider.dart';
import 'widgets/voice_overlay.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/connections_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/verify_email_screen.dart';
import 'screens/profile_completion_screen.dart';
import 'screens/consultant_screen.dart';
import 'screens/sessions_screen.dart';
import 'screens/new_session_screen.dart';
import 'screens/about_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/entity_screen.dart';
import 'screens/session_analytics_screen.dart';
import 'screens/roleplay_setup_screen.dart';
import 'screens/quests_screen.dart';
import 'screens/graph_explorer_screen.dart';
import 'screens/health_dashboard_screen.dart';
import 'screens/expense_tracker_screen.dart';
import 'screens/tasks_screen.dart';
import 'screens/smart_home_dashboard_screen.dart';
import 'screens/trips_planner_screen.dart';
import 'screens/integrations_hub_screen.dart';
import 'screens/subscription_screen.dart';
import 'screens/insights_screen.dart';
import 'providers/tags_provider.dart';
import 'providers/profile_provider.dart';
import 'providers/health_finance_provider.dart';
import 'providers/task_event_provider.dart';
import 'providers/iot_manager_provider.dart';
import 'providers/enterprise_provider.dart';
import 'widgets/auth_guard.dart';
import 'routes/app_routes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables — .env is no longer bundled as a Flutter asset
  // (to avoid leaking API keys in the APK). It still loads from the project
  // root during development. For release builds, pass keys via --dart-define.
  try {
    await dotenv.load(fileName: "env/.env");
  } catch (e) {
    debugPrint('⚠️ .env not found as asset — using platform environment / --dart-define');
  }

  final supabaseUrl = const String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  final supabaseAnonKey = const String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  // Initialize Supabase using environment variables
  await Supabase.initialize(
    url: supabaseUrl.isNotEmpty ? supabaseUrl : dotenv.env['SUPABASE_URL'] ?? '',
    anonKey: supabaseAnonKey.isNotEmpty ? supabaseAnonKey : dotenv.env['SUPABASE_ANON_KEY'] ?? '',
  );

  // Set up global error handling
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
  };

  // ── Auth-state listener: register device & flush analytics on login/logout ──
  Supabase.instance.client.auth.onAuthStateChange.listen((data) {
    final event = data.event;
    if (event == AuthChangeEvent.signedIn) {
      DeviceService.instance.registerDevice();
    } else if (event == AuthChangeEvent.signedOut) {
      AnalyticsService.instance.flushNow();
    }
  });

  runApp(const BubblesApp());
}

class BubblesApp extends StatelessWidget {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  const BubblesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // 1. Connection Service (Base)
        ChangeNotifierProvider(create: (context) => ConnectionService()),

        // 2. API Service (Depends on ConnectionService)
        ProxyProvider<ConnectionService, ApiService>(
          update: (context, connection, previous) => ApiService(connection),
        ),

        // 3. LiveKit Service (Depends on ApiService)
        // FIX: Reuse previous instance instead of creating new one on every update
        ChangeNotifierProxyProvider<ApiService, LiveKitService>(
          create: (context) =>
              LiveKitService(Provider.of<ApiService>(context, listen: false)),
          update: (context, api, previous) => previous!..updateApiService(api),
        ),

        // 4. Theme Provider
        ChangeNotifierProvider(create: (context) => ThemeProvider()),

          // 4.5. Settings Provider
          ChangeNotifierProvider(create: (context) => SettingsProvider()),
        ChangeNotifierProvider(create: (context) => DeepgramService()),

        // 6. Wake Word Service (Porcupine)
        ChangeNotifierProvider(create: (context) => WakeWordService()),

        // 7. Voice Assistant Service (depends on Connection + WakeWord)
        ChangeNotifierProxyProvider2<
          ConnectionService,
          WakeWordService,
          VoiceAssistantService
        >(
          create: (context) => VoiceAssistantService(
            Provider.of<ConnectionService>(context, listen: false),
            Provider.of<WakeWordService>(context, listen: false),
          ),
          update: (context, connection, wakeWord, previous) => previous!,
        ),

        // 8. Consultant Provider (chat state)
        ChangeNotifierProvider(create: (_) => ConsultantProvider()),

        // 9. Session Provider (live wingman state)
        ChangeNotifierProvider(create: (_) => SessionProvider()),

        // 10. Home Provider (home screen data)
        ChangeNotifierProvider(create: (_) => HomeProvider()),

        // 11. Tags Provider (schema_v2 tagging)
        ChangeNotifierProvider(create: (_) => TagsProvider()),

        // 12. Profile / Identity Provider (Schema v4)
        ChangeNotifierProvider(create: (_) => ProfileProvider()),

        // 13. Health & Finance Provider (Schema v4)
        ChangeNotifierProvider(create: (_) => HealthFinanceProvider()),

        // 14. Tasks & Events Provider
        ChangeNotifierProvider(create: (_) => TaskEventProvider()),

        // 15. IoT Provider
        ChangeNotifierProvider(create: (_) => IoTManagerProvider()),

        // 16. Enterprise & Subscriptions Provider
        ChangeNotifierProvider(create: (_) => EnterpriseProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            navigatorKey: BubblesApp.navigatorKey,
            navigatorObservers: [_AnalyticsNavigatorObserver()],
            debugShowCheckedModeBanner: false,
            title: 'Bubbles',

            // Theme Mode: Follows stored settings (System/Light/Dark)
            themeMode: themeProvider.themeMode,

            // Light Theme Configuration
            theme: themeProvider.lightTheme,

            // Dark Theme Configuration
            darkTheme: themeProvider.darkTheme,

            // The root screen
            home: const SplashScreen(),

            // Global builder: adds VoiceOverlay on all routes except /settings
            builder: (context, child) {
              return _VoiceOverlayWrapper(child: child ?? const SizedBox());
            },

            // Custom routes with animations for specific ones
            onGenerateRoute: (settings) {
              if (settings.name == AppRoutes.settings) {
                return PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      const SettingsScreen(),
                  transitionsBuilder:
                      (context, animation, secondaryAnimation, child) {
                        const begin = Offset(-1.0, 0.0); // Slide from left
                        const end = Offset.zero;
                        const curve = Curves.easeInOut;
                        var tween = Tween(
                          begin: begin,
                          end: end,
                        ).chain(CurveTween(curve: curve));
                        var offsetAnimation = animation.drive(tween);
                        return SlideTransition(
                          position: offsetAnimation,
                          child: child,
                        );
                      },
                );
              } else if (settings.name == AppRoutes.entities) {
                return PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      const EntityScreen(),
                  transitionsBuilder:
                      (context, animation, secondaryAnimation, child) {
                        const begin = Offset(1.0, 0.0); // Slide from right
                        const end = Offset.zero;
                        const curve = Curves.easeInOut;
                        var tween = Tween(
                          begin: begin,
                          end: end,
                        ).chain(CurveTween(curve: curve));
                        var offsetAnimation = animation.drive(tween);
                        return SlideTransition(
                          position: offsetAnimation,
                          child: child,
                        );
                      },
                );
              } else if (settings.name == AppRoutes.sessionAnalytics) {
                final args = settings.arguments as Map<String, String>?;
                return PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      SessionAnalyticsScreen(
                        sessionId: args?['sessionId'] ?? '',
                        sessionTitle: args?['sessionTitle'] ?? 'Session',
                      ),
                  transitionsBuilder:
                      (context, animation, secondaryAnimation, child) {
                        const begin = Offset(0.0, 1.0); // Slide from bottom
                        const end = Offset.zero;
                        const curve = Curves.easeInOut;
                        var tween = Tween(begin: begin, end: end)
                            .chain(CurveTween(curve: curve));
                        return SlideTransition(
                          position: animation.drive(tween),
                          child: child,
                        );
                      },
                );
              }
              return null; // Let the 'routes' map handle the rest
            },

            // Routes for manual navigation
            routes: {
              AppRoutes.login: (context) =>
                  const AuthGuard(requireAuth: false, child: LoginScreen()),
              AppRoutes.signup: (context) =>
                  const AuthGuard(requireAuth: false, child: SignupScreen()),
              AppRoutes.verifyEmail: (context) => const AuthGuard(
                requireAuth: false,
                child: VerifyEmailScreen(),
              ),
              AppRoutes.profileCompletion: (context) =>
                  const AuthGuard(child: ProfileCompletionScreen()),
              AppRoutes.home: (context) => const AuthGuard(child: HomeScreen()),
              AppRoutes.connections: (context) =>
                  const AuthGuard(child: ConnectionsScreen()),
              AppRoutes.newSession: (context) =>
                  const AuthGuard(child: NewSessionScreen()),
              AppRoutes.consultant: (context) =>
                  const AuthGuard(child: ConsultantScreen()),
              AppRoutes.sessions: (context) =>
                  const AuthGuard(child: SessionsScreen()),
              AppRoutes.about: (context) =>
                  const AuthGuard(child: AboutScreen()),
              AppRoutes.roleplaySetup: (context) =>
                  const AuthGuard(child: RoleplaySetupScreen()),
              AppRoutes.quests: (context) =>
                  const AuthGuard(child: QuestsScreen()),
              AppRoutes.graphExplorer: (context) =>
                  const AuthGuard(child: GraphExplorerScreen()),
              AppRoutes.insights: (context) =>
                  const AuthGuard(child: InsightsScreen()),
              AppRoutes.healthDashboard: (context) =>
                  const AuthGuard(child: HealthDashboardScreen()),
              AppRoutes.expensesTracker: (context) =>
                  const AuthGuard(child: ExpenseTrackerScreen()),
              AppRoutes.tasks: (context) => 
                  const AuthGuard(child: TasksScreen()),
              AppRoutes.smartHome: (context) =>
                  const AuthGuard(child: SmartHomeDashboardScreen()),
              AppRoutes.tripsPlanner: (context) =>
                  const AuthGuard(child: TripsPlannerScreen()),
              AppRoutes.integrations: (context) =>
                  const AuthGuard(child: IntegrationsHubScreen()),
              AppRoutes.subscription: (context) =>
                  const AuthGuard(child: SubscriptionScreen()),
            },
          );
        },
      ),
    );
  }
}

/// Wrapper that adds VoiceOverlay on top of all screens except settings & auth.
class _VoiceOverlayWrapper extends StatelessWidget {
  final Widget child;
  const _VoiceOverlayWrapper({required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        // The overlay manages its own visibility; it hides during settings
        const VoiceOverlay(),
      ],
    );
  }
}

/// The Gatekeeper Widget
/// Dynamically switches between Login and Home based on auth state.

/// Navigator observer that logs screen views to audit_log.
class _AnalyticsNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _logScreenView(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute != null) _logScreenView(newRoute);
  }

  void _logScreenView(Route<dynamic> route) {
    final routeName = route.settings.name;
    if (routeName == null || routeName.isEmpty) return;
    AnalyticsService.instance.logAction(
      action: 'screen_view',
      entityType: 'screen',
      details: {'screen': routeName},
    );
  }
}
