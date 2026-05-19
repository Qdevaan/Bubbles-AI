import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../theme/design_tokens.dart';

class ThemeProvider extends ChangeNotifier {
  Color _seedColor = AppColors.primary;
  ThemeMode _themeMode = ThemeMode.system;

  static const String _colorKey = 'theme_seed_color';
  static const String _themeModeKey = 'theme_mode_pref';

  Color get seedColor => _seedColor;
  ThemeMode get themeMode => _themeMode;

  ThemeProvider({ThemeMode? initialThemeMode, Color? initialSeedColor}) {
    if (initialThemeMode != null) _themeMode = initialThemeMode;
    if (initialSeedColor != null) _seedColor = initialSeedColor;
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
        if (t == 'dark') {
          mode = ThemeMode.dark;
        } else if (t == 'light') {
          mode = ThemeMode.light;
        }

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
    await prefs.setInt(_colorKey, color.toARGB32());
    _upsertSetting({'accent_color': color.toARGB32().toString()});
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeModeKey, mode.index);
    String tStr = 'system';
    if (mode == ThemeMode.dark) {
      tStr = 'dark';
    } else if (mode == ThemeMode.light) {
      tStr = 'light';
    }
    _upsertSetting({'theme': tStr});
  }

  TextTheme get _manropeTextTheme => GoogleFonts.manropeTextTheme();

  ThemeData get lightTheme => _buildTheme(Brightness.light);
  ThemeData get darkTheme => _buildTheme(Brightness.dark);

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final onSurface = isDark ? AppColors.slate200 : AppColors.slate900;
    final onSurfaceMuted = isDark ? AppColors.slate400 : AppColors.slate500;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final surfaceElevated =
        isDark ? AppColors.surfaceDarkHighlight : Colors.white;
    final scaffoldBg =
        isDark ? AppColors.backgroundDark : AppColors.backgroundLight;
    final border = isDark ? AppColors.glassBorder : AppColors.slate200;
    final fillSubtle = isDark ? AppColors.glassInput : Colors.white;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: brightness,
    ).copyWith(
      primary: _seedColor,
      onPrimary: Colors.white,
      secondary: _seedColor,
      onSecondary: Colors.white,
      surface: surface,
      onSurface: onSurface,
      error: AppColors.error,
      onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBg,
      textTheme: _manropeTextTheme.apply(
        bodyColor: onSurface,
        displayColor: onSurface,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: onSurface,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: onSurface),
        titleTextStyle: GoogleFonts.manrope(
          fontWeight: FontWeight.w800,
          fontSize: 20,
          color: onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: isDark ? AppColors.glassWhite : Colors.white.withAlpha(220),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xxl),
          side: BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fillSubtle,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        hintStyle: GoogleFonts.manrope(
          fontSize: 14,
          color: onSurfaceMuted,
        ),
        labelStyle: GoogleFonts.manrope(
          fontSize: 14,
          color: onSurfaceMuted,
          fontWeight: FontWeight.w600,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: BorderSide(color: _seedColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: const BorderSide(color: AppColors.error, width: 2),
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
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _seedColor,
          foregroundColor: Colors.white,
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
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _seedColor,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          side: BorderSide(color: _seedColor.withAlpha(140)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          textStyle: GoogleFonts.manrope(
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: _seedColor,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          textStyle: GoogleFonts.manrope(
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: onSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: _seedColor,
        foregroundColor: Colors.white,
        elevation: 2,
        highlightElevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            isDark ? AppColors.surfaceDarkHighlight : AppColors.slate800,
        contentTextStyle: GoogleFonts.manrope(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 13.5,
        ),
        actionTextColor: _seedColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        insetPadding: const EdgeInsets.all(12),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          side: BorderSide(color: border),
        ),
        titleTextStyle: GoogleFonts.manrope(
          fontWeight: FontWeight.w800,
          fontSize: 18,
          color: onSurface,
        ),
        contentTextStyle: GoogleFonts.manrope(
          fontWeight: FontWeight.w400,
          fontSize: 14,
          height: 1.5,
          color: onSurface,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surfaceElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalBackgroundColor: surfaceElevated,
        modalElevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
        ),
        showDragHandle: true,
        dragHandleColor: onSurfaceMuted,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(
            right: Radius.circular(AppRadius.xl),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor:
            isDark ? AppColors.glassWhite : AppColors.slate100,
        selectedColor: _seedColor.withAlpha(46),
        secondarySelectedColor: _seedColor.withAlpha(46),
        labelStyle: GoogleFonts.manrope(
          fontWeight: FontWeight.w600,
          fontSize: 13,
          color: onSurface,
        ),
        secondaryLabelStyle: GoogleFonts.manrope(
          fontWeight: FontWeight.w700,
          fontSize: 13,
          color: _seedColor,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.full),
          side: BorderSide(color: border),
        ),
        side: BorderSide(color: border),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        showCheckmark: false,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return isDark ? AppColors.slate400 : Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return _seedColor;
          return isDark ? AppColors.slate700 : AppColors.slate300;
        }),
        trackOutlineColor:
            const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return _seedColor;
          return Colors.transparent;
        }),
        checkColor: const WidgetStatePropertyAll(Colors.white),
        side: BorderSide(color: onSurfaceMuted, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm / 2),
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return _seedColor;
          return onSurfaceMuted;
        }),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: _seedColor,
        inactiveTrackColor: _seedColor.withAlpha(60),
        thumbColor: _seedColor,
        overlayColor: _seedColor.withAlpha(40),
        valueIndicatorColor: _seedColor,
        valueIndicatorTextStyle: GoogleFonts.manrope(
          fontWeight: FontWeight.w700,
          color: Colors.white,
          fontSize: 12,
        ),
        trackHeight: 4,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: _seedColor,
        linearTrackColor: _seedColor.withAlpha(60),
        circularTrackColor: _seedColor.withAlpha(60),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: _seedColor,
        unselectedLabelColor: onSurfaceMuted,
        labelStyle: GoogleFonts.manrope(
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
        unselectedLabelStyle: GoogleFonts.manrope(
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
        indicatorSize: TabBarIndicatorSize.label,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: _seedColor, width: 2.5),
          insets: const EdgeInsets.symmetric(horizontal: 16),
        ),
        dividerColor: Colors.transparent,
        overlayColor: WidgetStatePropertyAll(_seedColor.withAlpha(20)),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor:
              isDark ? AppColors.glassWhite : AppColors.slate100,
          foregroundColor: onSurface,
          selectedBackgroundColor: _seedColor,
          selectedForegroundColor: Colors.white,
          textStyle: GoogleFonts.manrope(
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.full),
            side: BorderSide(color: border),
          ),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: onSurfaceMuted,
        textColor: onSurface,
        titleTextStyle: GoogleFonts.manrope(
          fontWeight: FontWeight.w600,
          fontSize: 15,
          color: onSurface,
        ),
        subtitleTextStyle: GoogleFonts.manrope(
          fontWeight: FontWeight.w400,
          fontSize: 13,
          color: onSurfaceMuted,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      dividerTheme: DividerThemeData(
        color: border,
        thickness: 1,
        space: 1,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.surfaceDarkHighlight
              : AppColors.slate800,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        textStyle: GoogleFonts.manrope(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        waitDuration: const Duration(milliseconds: 350),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surfaceElevated,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: border),
        ),
        textStyle: GoogleFonts.manrope(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: onSurface,
        ),
      ),
      iconTheme: IconThemeData(color: onSurface),
      primaryIconTheme: const IconThemeData(color: Colors.white),
      splashColor: _seedColor.withAlpha(20),
      highlightColor: _seedColor.withAlpha(15),
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
