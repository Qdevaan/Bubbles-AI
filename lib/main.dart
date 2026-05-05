import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import 'services/auth_service.dart';
import 'services/app_cache_service.dart';
import 'services/hydration_service.dart';
import 'cache/persistent_cache_service.dart';
import 'repositories/profile_repository.dart';
import 'repositories/settings_repository.dart';
import 'repositories/home_repository.dart';
import 'repositories/insights_repository.dart';
import 'repositories/graph_repository.dart';
import 'repositories/entity_repository.dart';
import 'repositories/gamification_repository.dart';
import 'repositories/sessions_repository.dart';
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
import 'screens/settings_preferences_screen.dart';
import 'screens/settings_assistant_screen.dart';
import 'screens/settings_voice_assistant_screen.dart';
import 'screens/entity_screen.dart';
import 'screens/session_analytics_screen.dart';
import 'screens/roleplay_setup_screen.dart';
import 'screens/game_center_screen.dart';
import 'screens/performa_screen.dart';
import 'providers/gamification_provider.dart';
import 'providers/performa_provider.dart';
import 'repositories/performa_repository.dart';
import 'screens/graph_explorer_screen.dart';
import 'screens/health_dashboard_screen.dart';
import 'screens/expense_tracker_screen.dart';
import 'screens/tasks_screen.dart';
import 'screens/smart_home_dashboard_screen.dart';
import 'screens/trips_planner_screen.dart';
import 'screens/integrations_hub_screen.dart';
import 'screens/subscription_screen.dart';
import 'screens/insights_screen.dart';
import 'screens/language_screen.dart';
import 'screens/permissions_screen.dart';
import 'screens/data_management_screen.dart';
import 'screens/update_password_screen.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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

  // Initialize Persistent Cache
  await PersistentCacheService.instance.init();

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
    url: supabaseUrl.isNotEmpty ? supabaseUrl : dotenv.get('SUPABASE_URL', fallback: ''),
    anonKey: supabaseAnonKey.isNotEmpty ? supabaseAnonKey : dotenv.get('SUPABASE_ANON_KEY', fallback: ''),
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
      final userId = data.session?.user.id;
      if (userId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = BubblesApp.navigatorKey.currentContext;
          ctx?.read<HydrationService>().setUserId(userId);
        });
      }
    } else if (event == AuthChangeEvent.signedOut) {
      AnalyticsService.instance.flushNow();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = BubblesApp.navigatorKey.currentContext;
        ctx?.read<HydrationService>().clearUserId();
      });
    } else if (event == AuthChangeEvent.passwordRecovery) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        BubblesApp.navigatorKey.currentState?.pushNamedAndRemoveUntil(
          AppRoutes.updatePassword,
          (route) => route.isFirst,
        );
      });
    }
  });

  // Pre-load theme prefs so first frame renders with correct theme (no flash).
  final prefs = await SharedPreferences.getInstance();
  final int? savedMode = prefs.getInt('theme_mode_pref');
  final int? savedColor = prefs.getInt('theme_seed_color');
  final ThemeMode initialThemeMode =
      savedMode != null ? ThemeMode.values[savedMode] : ThemeMode.system;
  final Color? initialSeedColor =
      savedColor != null ? Color(savedColor) : null;

  runApp(BubblesApp(
    initialThemeMode: initialThemeMode,
    initialSeedColor: initialSeedColor,
  ));
}

class BubblesApp extends StatelessWidget {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  final ThemeMode initialThemeMode;
  final Color? initialSeedColor;

  const BubblesApp({
    super.key,
    this.initialThemeMode = ThemeMode.system,
    this.initialSeedColor,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // 0. Core Cache Layers
        ChangeNotifierProvider(create: (_) => AppCacheService()),
        Provider.value(value: PersistentCacheService.instance),

        // 1. Connection Service (Base)
        ChangeNotifierProvider(create: (context) => ConnectionService()),

        // 2. API Service (Depends on ConnectionService)
        ProxyProvider<ConnectionService, ApiService>(
          update: (context, connection, previous) => ApiService(connection),
        ),

        // 0.5. Repositories (Domain Data Logic)
        ProxyProvider<AppCacheService, ProfileRepository>(
          update: (context, l1, _) {
            final repo = ProfileRepository(l1: l1, l2: context.read<PersistentCacheService>());
            AuthService.instance.setProfileRepository(repo);
            return repo;
          },
        ),
        ProxyProvider<AppCacheService, SettingsRepository>(
          update: (context, l1, _) => SettingsRepository(
            l1: l1, 
            l2: context.read<PersistentCacheService>(),
          ),
        ),
        ProxyProvider<AppCacheService, HomeRepository>(
          update: (context, l1, _) => HomeRepository(
            l1: l1, 
            l2: context.read<PersistentCacheService>(),
          ),
        ),
        ProxyProvider<AppCacheService, InsightsRepository>(
          update: (context, l1, _) => InsightsRepository(
            l1: l1, 
            l2: context.read<PersistentCacheService>(),
          ),
        ),
        ProxyProvider<ApiService, GraphRepository>(
          update: (context, api, _) => GraphRepository(
            api: api,
            l1: context.read<AppCacheService>(), 
            l2: context.read<PersistentCacheService>(),
          ),
        ),
        ProxyProvider<AppCacheService, EntityRepository>(
          update: (context, l1, _) => EntityRepository(
            l1: l1, 
            l2: context.read<PersistentCacheService>(),
          ),
        ),
        ProxyProvider<ApiService, GamificationRepository>(
          update: (context, api, _) => GamificationRepository(
            api: api, 
            l1: context.read<AppCacheService>(), 
            l2: context.read<PersistentCacheService>(),
          ),
        ),
        ProxyProvider2<AppCacheService, ApiService, SessionsRepository>(
          update: (context, l1, api, _) => SessionsRepository(
            l1: l1,
            l2: context.read<PersistentCacheService>(),
            api: api,
          ),
        ),

        // Hydration Service — parallel cache refresh + Realtime subscriptions
        ChangeNotifierProxyProvider<ConnectionService, HydrationService>(
          create: (context) => HydrationService(
            connection: context.read<ConnectionService>(),
            profile: context.read<ProfileRepository>(),
            settings: context.read<SettingsRepository>(),
            home: context.read<HomeRepository>(),
            insights: context.read<InsightsRepository>(),
            graph: context.read<GraphRepository>(),
            entity: context.read<EntityRepository>(),
            gamification: context.read<GamificationRepository>(),
            sessions: context.read<SessionsRepository>(),
          ),
          update: (_, __, prev) => prev!,
        ),

        // 3. LiveKit Service (Depends on ApiService)
        // FIX: Reuse previous instance instead of creating new one on every update
        ChangeNotifierProxyProvider<ApiService, LiveKitService>(
          create: (context) =>
              LiveKitService(Provider.of<ApiService>(context, listen: false)),
          update: (context, api, previous) => previous!..updateApiService(api),
        ),

        // 4. Theme Provider
        ChangeNotifierProvider(create: (_) => ThemeProvider(
          initialThemeMode: initialThemeMode,
          initialSeedColor: initialSeedColor,
        )),

        // 4.5. Settings Provider (Depends on SettingsRepository)
        ChangeNotifierProxyProvider<SettingsRepository, SettingsProvider>(
          create: (context) => SettingsProvider(),
          update: (context, repo, provider) => provider!..setRepository(repo),
        ),
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
        ChangeNotifierProxyProvider<SessionsRepository, ConsultantProvider>(
          create: (_) => ConsultantProvider(),
          update: (context, repo, provider) => provider!..setRepository(repo),
        ),

        // 9. Session Provider (live wingman state)
        ChangeNotifierProvider(create: (_) => SessionProvider()),

        // 10. Home Provider (Depends on HomeRepository)
        ChangeNotifierProxyProvider<HomeRepository, HomeProvider>(
          create: (context) => HomeProvider(),
          update: (context, repo, provider) => provider!..setRepository(repo),
        ),

        // 11. Tags Provider (schema_v2 tagging)
        ChangeNotifierProvider(create: (_) => TagsProvider()),

        // 12. Profile / Identity Provider (Schema v4)
        ChangeNotifierProvider(create: (_) => ProfileProvider()),

        // 13. Health & Finance Provider (Schema v4)
        ChangeNotifierProvider(create: (_) => HealthFinanceProvider()),

        // 14. Tasks & Events Provider
        ChangeNotifierProvider(create: (_) => TaskEventProvider()),

        // 15. Enterprise & Subscriptions Provider
        ChangeNotifierProvider(create: (_) => EnterpriseProvider()),

        // 16. Gamification Provider (Depends on GamificationRepository)
        ProxyProvider<ApiService, PerformaRepository>(
          update: (context, api, _) => PerformaRepository(api),
        ),
        ChangeNotifierProxyProvider<PerformaRepository, PerformaProvider>(
          create: (context) => PerformaProvider(context.read<PerformaRepository>()),
          update: (context, repo, prev) => prev ?? PerformaProvider(repo),
        ),
        ChangeNotifierProxyProvider<GamificationRepository, GamificationProvider>(
          create: (context) => GamificationProvider(context.read<ApiService>()),
          update: (context, repo, provider) => provider!..setRepository(repo),
        ),
      ],
      child: Consumer2<ThemeProvider, SettingsProvider>(
        builder: (context, themeProvider, settingsProvider, child) {
          return MaterialApp(
            navigatorKey: BubblesApp.navigatorKey,
            navigatorObservers: [_AnalyticsNavigatorObserver()],
            debugShowCheckedModeBanner: false,
            title: 'Bubbles',

            // Theme Mode: Follows stored settings (System/Light/Dark)
            themeMode: themeProvider.themeMode,

            // Locale
            locale: settingsProvider.locale,
            supportedLocales: const [
              Locale('en'),
              Locale('ur'),
              Locale('ar'),
            ],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],

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
                final args = settings.arguments as Map<String, dynamic>?;
                return PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) =>
                       SessionAnalyticsScreen(
                        sessionId: args?['sessionId'] ?? '',
                        sessionTitle: args?['sessionTitle'] ?? 'Session',
                        initialTab: args?['initialTab'] ?? 0,
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
              AppRoutes.sessions: (context) {
                final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
                return AuthGuard(child: SessionsScreen(initialSearchQuery: args?['query']));
              },
              AppRoutes.about: (context) =>
                  const AuthGuard(child: AboutScreen()),
              AppRoutes.roleplaySetup: (context) =>
                  const AuthGuard(child: RoleplaySetupScreen()),
              AppRoutes.quests: (context) =>
                  const AuthGuard(child: GameCenterScreen()),
              AppRoutes.gameCenter: (context) =>
                  const AuthGuard(child: GameCenterScreen()),
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
              AppRoutes.smartHome: (context) => AuthGuard(
                child: ChangeNotifierProvider(
                  create: (_) => IoTManagerProvider(),
                  child: const SmartHomeDashboardScreen(),
                ),
              ),
              AppRoutes.tripsPlanner: (context) =>
                  const AuthGuard(child: TripsPlannerScreen()),
              AppRoutes.integrations: (context) =>
                  const AuthGuard(child: IntegrationsHubScreen()),
              AppRoutes.subscription: (context) =>
                  const AuthGuard(child: SubscriptionScreen()),
              AppRoutes.settings: (context) =>
                  const AuthGuard(child: SettingsScreen()),
              AppRoutes.preferences: (context) =>
                  const AuthGuard(child: SettingsPreferencesScreen()),
              AppRoutes.assistant: (context) =>
                  const AuthGuard(child: SettingsAssistantScreen()),
              AppRoutes.voiceAssistant: (context) =>
                  const AuthGuard(child: SettingsVoiceAssistantScreen()),
              AppRoutes.language: (context) =>
                  const AuthGuard(child: LanguageScreen()),
              AppRoutes.permissions: (context) =>
                  const AuthGuard(child: PermissionsScreen()),
              AppRoutes.data: (context) =>
                  const AuthGuard(child: DataManagementScreen()),
              AppRoutes.updatePassword: (context) =>
                  const UpdatePasswordScreen(),
              AppRoutes.performa: (context) =>
                  const AuthGuard(child: PerformaScreen()),
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
