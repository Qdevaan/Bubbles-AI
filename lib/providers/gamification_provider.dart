import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../repositories/gamification_repository.dart';

/// Centralized gamification state for the entire app.
/// Consumed by the Game Center, Home Screen streak strip, and XP ring.
class GamificationProvider extends ChangeNotifier {
  final ApiService _api;
  GamificationRepository? _repository;

  GamificationProvider(this._api);

  void setRepository(GamificationRepository repo) => _repository = repo;

  // ── Profile data ──────────────────────────────────────────────────────────
  int _totalXp = 0;
  int get totalXp => _totalXp;

  int _level = 1;
  int get level => _level;

  double _xpProgressPct = 0.0;
  double get xpProgressPct => _xpProgressPct;

  int _xpCurrentLevel = 0;
  int get xpCurrentLevel => _xpCurrentLevel;

  int _xpNextLevel = 100;
  int get xpNextLevel => _xpNextLevel;

  int _xpToNextLevel = 100;
  int get xpToNextLevel => _xpToNextLevel;

  int _currentStreak = 0;
  int get currentStreak => _currentStreak;

  int _longestStreak = 0;
  int get longestStreak => _longestStreak;

  int _streakFreezes = 0;
  int get streakFreezes => _streakFreezes;

  String? _lastActiveDate;
  String? get lastActiveDate => _lastActiveDate;

  // ── Quests ────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _dailyQuests = [];
  List<Map<String, dynamic>> get dailyQuests => List.unmodifiable(_dailyQuests);

  String? _dailyResetAt;
  String? get dailyResetAt => _dailyResetAt;

  int _completedToday = 0;
  int get completedToday => _completedToday;

  int _totalQuestsToday = 0;
  int get totalQuestsToday => _totalQuestsToday;

  // ── Achievements & XP History ─────────────────────────────────────────────
  List<Map<String, dynamic>> _badges = [];
  List<Map<String, dynamic>> get badges => List.unmodifiable(_badges);

  List<Map<String, dynamic>> _recentXp = [];
  List<Map<String, dynamic>> get recentXp => List.unmodifiable(_recentXp);

  Map<String, int> _stats = {};
  Map<String, int> get stats => Map.unmodifiable(_stats);

  // ── AI Performance (Adaptive Engine) ──────────────────────────────────────
  String? _performanceTier;
  String? get performanceTier => _performanceTier;

  String? _recommendedDifficulty;
  String? get recommendedDifficulty => _recommendedDifficulty;

  String? _aiCoachingTip;
  String? get aiCoachingTip => _aiCoachingTip;

  List<String> _focusAreas = [];
  List<String> get focusAreas => List.unmodifiable(_focusAreas);

  double? _weeklyScore;
  double? get weeklyScore => _weeklyScore;

  double? _scoreDelta;
  double? get scoreDelta => _scoreDelta;

  // ── Loading states ────────────────────────────────────────────────────────
  bool _profileLoading = true;
  bool get profileLoading => _profileLoading;

  bool _questsLoading = true;
  bool get questsLoading => _questsLoading;

  bool _levelUpTriggered = false;
  bool get levelUpTriggered => _levelUpTriggered;

  // ── Skill tier labels ─────────────────────────────────────────────────────

  String get skillTierLabel {
    if (_level <= 3) return 'Seedling';
    if (_level <= 7) return 'Growth';
    if (_level <= 12) return 'Flourishing';
    if (_level <= 20) return 'Mastery';
    return 'Legend';
  }

  String get skillTierEmoji {
    if (_level <= 3) return '🌱';
    if (_level <= 7) return '🌿';
    if (_level <= 12) return '🌳';
    if (_level <= 20) return '⭐';
    return '👑';
  }

  // ── Streak status helpers ─────────────────────────────────────────────────

  bool get hasActiveStreak => _currentStreak > 0;
  bool get isStreakHot => _currentStreak >= 3;

  /// Which days of the current week had activity.
  /// Returns 7 bools (Mon=0 ... Sun=6), with today highlighted.
  List<bool> get weekActivity {
    final now = DateTime.now();
    final weekday = now.weekday; // 1=Mon .. 7=Sun
    // We only definitively know "last_active_date" and "today."
    // For a complete picture, we'd need the server to send a week map.
    // For now: mark today + streak days backward as active.
    final active = List.filled(7, false);
    for (int i = 0; i < _currentStreak && i < 7; i++) {
      final dayIdx = (weekday - 1 - i) % 7;
      if (dayIdx >= 0 && dayIdx < 7) active[dayIdx] = true;
    }
    return active;
  }

  int get todayWeekdayIndex => DateTime.now().weekday - 1;

  // ══════════════════════════════════════════════════════════════════════════
  // Data loading
  // ══════════════════════════════════════════════════════════════════════════

  /// Initialize all gamification data. Call once on app start or Game Center open.
  Future<void> init() async {
    await Future.wait([
      loadProfile(),
      loadQuests(),
    ]);
  }

  Future<void> loadProfile() async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null || userId.isEmpty) return;

    if (_repository == null) return;
    _profileLoading = true;
    notifyListeners();

    try {
      final result = await _repository!.getGamification(userId, forceRefresh: false);
      final data = result.data;
      if (data != null && data.isNotEmpty) {
        final oldLevel = _level;
        _totalXp = (data['xp'] as num?)?.toInt() ?? 0;
        _level = (data['level'] as num?)?.toInt() ?? 1;
        _xpCurrentLevel = (data['xp_current_level'] as num?)?.toInt() ?? 0;
        _xpNextLevel = (data['xp_next_level'] as num?)?.toInt() ?? 100;
        _xpToNextLevel = (data['xp_to_next_level'] as num?)?.toInt() ?? 100;
        _xpProgressPct = (data['xp_progress_pct'] as num?)?.toDouble() ?? 0.0;
        _currentStreak = (data['current_streak'] as num?)?.toInt() ?? 0;
        _longestStreak = (data['longest_streak'] as num?)?.toInt() ?? 0;
        _streakFreezes = (data['streak_freezes'] as num?)?.toInt() ?? 0;
        _lastActiveDate = data['last_active_date'] as String?;
        _badges = List<Map<String, dynamic>>.from(data['badges'] ?? []);
        _recentXp = List<Map<String, dynamic>>.from(data['recent_xp'] ?? []);
        final statsRaw = data['stats'] as Map<String, dynamic>?;
        if (statsRaw != null) {
          _stats = statsRaw.map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0));
        }
        if (oldLevel > 0 && _level > oldLevel) _levelUpTriggered = true;
      }
      _profileLoading = false;
      notifyListeners();
    } catch (e) {
      debugPrint('GamificationProvider.loadProfile repo error: $e');
      _profileLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadQuests() async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null || userId.isEmpty) return;

    if (_repository == null) return;
    _questsLoading = true;
    notifyListeners();
    try {
      final result = await _repository!.getQuests(userId, forceRefresh: false);
      final data = result.data;
      if (data != null && data.isNotEmpty) {
        _dailyQuests = List<Map<String, dynamic>>.from(data['quests'] ?? []);
        _dailyResetAt = data['daily_reset_at'] as String?;
        _completedToday = (data['total_completed_today'] as num?)?.toInt() ?? 0;
        _totalQuestsToday = (data['total_quests_today'] as num?)?.toInt() ?? 0;
      }
      _questsLoading = false;
      notifyListeners();
    } catch (e) {
      debugPrint('GamificationProvider.loadQuests repo error: $e');
      _questsLoading = false;
      notifyListeners();
    }
  }

  /// Load AI performance summary (adaptive engine).
  Future<void> loadPerformanceSummary() async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null || userId.isEmpty) return;

    if (_repository == null) return;
    try {
      final result = await _repository!.getPerformanceSummary(userId, forceRefresh: false);
      final data = result.data;
      if (data != null && data.isNotEmpty) {
        _performanceTier = data['performance_tier'] as String?;
        _recommendedDifficulty = data['recommended_difficulty'] as String?;
        _aiCoachingTip = data['ai_coaching_tip'] as String?;
        _focusAreas = List<String>.from(data['focus_areas'] ?? []);
        _weeklyScore = (data['weekly_score'] as num?)?.toDouble();
        _scoreDelta = (data['score_delta'] as num?)?.toDouble();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('GamificationProvider.loadPerformanceSummary repo error: $e');
    }
  }

  /// Acknowledge the level-up so the celebration doesn't replay.
  void acknowledgeLevelUp() {
    _levelUpTriggered = false;
    notifyListeners();
  }

  /// Get time remaining until daily quest reset.
  Duration? get timeUntilReset {
    if (_dailyResetAt == null) return null;
    try {
      final resetTime = DateTime.parse(_dailyResetAt!);
      final remaining = resetTime.difference(DateTime.now().toUtc());
      return remaining.isNegative ? Duration.zero : remaining;
    } catch (_) {
      return null;
    }
  }
}
