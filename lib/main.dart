import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'services/connection_service.dart';
import 'services/api_service.dart';
import 'services/livekit_service.dart';
import 'services/deepgram_service.dart';
import 'services/voice_assistant_service.dart';
import 'services/wake_word_service.dart';
import 'services/analytics_service.dart';
import 'services/device_service.dart';
import 'services/app_cache_service.dart';
import 'providers/theme_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/consultant_provider.dart';
import 'providers/session_provider.dart';
import 'providers/home_provider.dart';
import 'providers/gamification_provider.dart';
import 'providers/tags_provider.dart';
import 'providers/profile_provider.dart';
import 'providers/health_finance_provider.dart';
import 'providers/task_event_provider.dart';
import 'providers/enterprise_provider.dart';
import 'widgets/voice_overlay.dart';
import 'routes/app_router.dart';

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
  const BubblesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // 0. App Cache Service (Global app state cache)
        ChangeNotifierProvider(create: (_) => AppCacheService()),

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

        // 15. Enterprise & Subscriptions Provider
        ChangeNotifierProvider(create: (_) => EnterpriseProvider()),

        // 16. Gamification Provider (depends on ApiService)
        ChangeNotifierProxyProvider<ApiService, GamificationProvider>(
          create: (context) =>
              GamificationProvider(Provider.of<ApiService>(context, listen: false)),
          update: (context, api, previous) => previous!,
        ),
      ],
      child: Consumer2<ThemeProvider, SettingsProvider>(
        builder: (context, themeProvider, settingsProvider, child) {
          return MaterialApp.router(
            routerConfig: AppRouter.router,
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

            // Global builder: adds VoiceOverlay on top of all screens
            builder: (context, child) {
              return _VoiceOverlayWrapper(child: child ?? const SizedBox());
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

