import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../services/analytics_service.dart';
import '../theme/design_tokens.dart';

class ThemeProvider extends ChangeNotifier {
  Color _seedColor = AppColors.primary;
  ThemeMode _themeMode = ThemeMode.system;

  static const String _colorKey = 'theme_seed_color';
  static const String _themeModeKey = 'theme_mode_pref';

  Color get seedColor => _seedColor;
  ThemeMode get themeMode => _themeMode;

  ThemeProvider() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final int? colorValue = prefs.getInt(_colorKey);
    if (colorValue != null) {
      _seedColor = Color(colorValue);
    }
    final int? modeValue = prefs.getInt(_themeModeKey);
    if (modeValue != null) {
      _themeMode = ThemeMode.values[modeValue];
    }
    notifyListeners();
    _loadFromSupabase();
  }

  Future<void> _loadFromSupabase() async {
    try {
      final user = AuthService.instance.currentUser;
      if (user == null) return;
      final row = await Supabase.instance.client
          .from('user_settings')
          .select('theme, accent_color')
          .eq('user_id', user.id)
          .maybeSingle();
      if (row == null) return;
      final prefs = await SharedPreferences.getInstance();
      if (row['theme'] != null) {
        final String t = row['theme'];
        ThemeMode mode = ThemeMode.system;
        if (t == 'dark') mode = ThemeMode.dark;
        else if (t == 'light') mode = ThemeMode.light;
        
        if (mode != _themeMode) {
          _themeMode = mode;
          await prefs.setInt(_themeModeKey, mode.index);
        }
      }
      if (row['accent_color'] != null) {
        final int? colorVal = int.tryParse(row['accent_color']);
        if (colorVal != null) {
          _seedColor = Color(colorVal);
          await prefs.setInt(_colorKey, colorVal);
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('ThemeProvider._loadFromSupabase: $e');
    }
  }

  Future<void> _upsertSetting(Map<String, dynamic> updates) async {
    try {
      final user = AuthService.instance.currentUser;
      if (user == null) return;
      await Supabase.instance.client.from('user_settings').upsert({
        'user_id': user.id,
        ...updates,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint('ThemeProvider._upsertSetting: $e');
    }
  }

  Future<void> setThemeColor(Color color) async {
    _seedColor = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_colorKey, color.value);
    _upsertSetting({'accent_color': color.value.toString()});
    AnalyticsService.instance.logAction(
      action: 'settings_changed',
      entityType: 'user_settings',
      details: {'key': 'accent_color', 'value': color.value.toString()},
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeModeKey, mode.index);
    String tStr = 'system';
    if (mode == ThemeMode.dark) tStr = 'dark';
    else if (mode == ThemeMode.light) tStr = 'light';
    _upsertSetting({'theme': tStr});
    AnalyticsService.instance.logAction(
      action: 'settings_changed',
      entityType: 'user_settings',
      details: {'key': 'theme', 'value': tStr},
    );
  }

  TextTheme get _manropeTextTheme => GoogleFonts.manropeTextTheme();

  ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      textTheme: _manropeTextTheme.apply(
        bodyColor: AppColors.slate900,
        displayColor: AppColors.slate900,
      ),
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: _seedColor,
            brightness: Brightness.light,
          ).copyWith(
            primary: _seedColor,
            onPrimary: Colors.white,
            secondary: _seedColor,
            onSecondary: Colors.white,
            surface: AppColors.surfaceLight,
            onSurface: AppColors.slate900,
          ),
      scaffoldBackgroundColor: AppColors.backgroundLight,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.slate900,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.manrope(
          fontWeight: FontWeight.w800,
          fontSize: 20,
          color: AppColors.slate900,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white.withAlpha(220),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xxl),
          side: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withAlpha(200),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: BorderSide(color: _seedColor, width: 2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _seedColor,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          textStyle: GoogleFonts.manrope(
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
        },
      ),
    );
  }

  ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      textTheme: _manropeTextTheme.apply(
        bodyColor: AppColors.slate200,
        displayColor: AppColors.slate200,
      ),
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: _seedColor,
            brightness: Brightness.dark,
          ).copyWith(
            primary: _seedColor,
            onPrimary: Colors.white,
            secondary: _seedColor,
            onSecondary: Colors.white,
            surface: AppColors.surfaceDark,
            onSurface: AppColors.slate200,
          ),
      scaffoldBackgroundColor: AppColors.backgroundDark,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.manrope(
          fontWeight: FontWeight.w800,
          fontSize: 20,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.glassWhite,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xxl),
          side: BorderSide(color: AppColors.glassBorder),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.glassInput,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: BorderSide(color: AppColors.glassBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: BorderSide(color: AppColors.glassBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: BorderSide(color: _seedColor, width: 2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _seedColor,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          textStyle: GoogleFonts.manrope(
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
        },
      ),
    );
  }
}
