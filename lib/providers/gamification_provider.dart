import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  int _xpSpent = 0;
  int get xpSpent => _xpSpent;

  int _xpBalance = 0;
  int get xpBalance => _xpBalance;

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

  // Newly-unlocked queue surfaced to the UI as toasts. Drained via acknowledgeBadge().
  final List<Map<String, dynamic>> _newlyUnlockedBadges = [];
  List<Map<String, dynamic>> get newlyUnlockedBadges =>
      List.unmodifiable(_newlyUnlockedBadges);
  static const String _kLastSeenBadgeAt = 'gam_last_seen_badge_at';
  static const String _kSnapLevel = 'gam_snap_level';
  static const String _kSnapXp = 'gam_snap_xp';
  static const String _kSnapStreak = 'gam_snap_streak';
  static const String _kSnapLongestStreak = 'gam_snap_longest_streak';
  static const String _kSnapXpProgress = 'gam_snap_xp_progress';
  static const String _kSnapXpCurrentLevel = 'gam_snap_xp_current_level';
  static const String _kSnapXpNextLevel = 'gam_snap_xp_next_level';
  static const String _kSnapBadges = 'gam_snap_badges';

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

  // ── Daily quest issuance guard (called on app startup) ───────────────────
  static const String _kLastQuestIssuedDate = 'gam_last_quest_issued_date';

  /// Called on app open. Checks if today's quests have been issued this session.
  /// If the stored date differs from today (or is absent), kicks off a fresh
  /// loadQuests() which hits the backend — the backend is idempotent and will
  /// create quests for today if they don't exist yet.
  Future<void> ensureDailyQuestsIssued() async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null || userId.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final key = '${_kLastQuestIssuedDate}_$userId';
    final storedDate = prefs.getString(key);
    final todayStr = () {
      final now = DateTime.now();
      return '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';
    }();

    if (storedDate != todayStr) {
      // Quests haven't been issued for today yet — fetch from backend (auto-creates them)
      debugPrint('🎮 Daily quests not yet issued for $todayStr — fetching...');
      await loadQuests();
      await prefs.setString(key, todayStr);
    }
  }

  /// Initialize all gamification data. Call once on app start or Game Center open.

  Future<void> init() async {
    await Future.wait([
      loadProfile(),
      loadQuests(),
      loadRewards(),
      loadLeaderboard(),
    ]);
  }

  Future<void> loadProfile() async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null || userId.isEmpty) return;

    if (_repository == null) return;

    // Show last-known state immediately so UI never shows level 0 while loading
    if (_level <= 1 && _totalXp == 0) await _loadProfileFromPrefs();

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
        _xpSpent = (data['xp_spent'] as num?)?.toInt() ?? 0;
        _xpBalance = (data['xp_balance'] as num?)?.toInt() ?? (_totalXp - _xpSpent).clamp(0, _totalXp);
        _currentStreak = (data['current_streak'] as num?)?.toInt() ?? 0;
        _longestStreak = (data['longest_streak'] as num?)?.toInt() ?? 0;
        _streakFreezes = (data['streak_freezes'] as num?)?.toInt() ?? 0;
        _lastActiveDate = data['last_active_date'] as String?;
        final newBadges = List<Map<String, dynamic>>.from(data['badges'] ?? []);
        await _detectNewlyUnlocked(newBadges);
        _badges = newBadges;
        _recentXp = List<Map<String, dynamic>>.from(data['recent_xp'] ?? []);
        final statsRaw = data['stats'] as Map<String, dynamic>?;
        if (statsRaw != null) {
          _stats = statsRaw.map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0));
        }
        if (oldLevel > 0 && _level > oldLevel) _levelUpTriggered = true;
        _saveProfileToPrefs(); // fire-and-forget: persist for offline use
      }
      _profileLoading = false;
      notifyListeners();
    } catch (e) {
      debugPrint('GamificationProvider.loadProfile repo error: $e');
      await _loadProfileFromPrefs(); // fall back to last snapshot on network failure
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
      // Always force-refresh quests: the repo uses a date-scoped cache key,
      // so on first access each day this hits the network (creating quests if needed),
      // and for subsequent calls within the same day it serves from cache.
      final result = await _repository!.getQuests(userId, forceRefresh: true);
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

  /// Detect badges unlocked since the last loadProfile and queue them for the UI.
  /// First-ever load establishes a baseline (no toasts) so we don't replay history.
  Future<void> _detectNewlyUnlocked(List<Map<String, dynamic>> incoming) async {
    if (incoming.isEmpty) return;

    DateTime? newest;
    for (final b in incoming) {
      final ts = b['awarded_at'] as String?;
      if (ts == null || ts.isEmpty) continue;
      final dt = DateTime.tryParse(ts);
      if (dt == null) continue;
      if (newest == null || dt.isAfter(newest)) newest = dt;
    }
    if (newest == null) return;

    final prefs = await SharedPreferences.getInstance();
    final userId = AuthService.instance.currentUser?.id ?? '';
    final key = '${_kLastSeenBadgeAt}_$userId';
    final lastSeenStr = prefs.getString(key);

    if (lastSeenStr == null) {
      // Baseline — don't replay existing badges as new.
      await prefs.setString(key, newest.toIso8601String());
      return;
    }

    final lastSeen = DateTime.tryParse(lastSeenStr);
    if (lastSeen == null) {
      await prefs.setString(key, newest.toIso8601String());
      return;
    }

    if (!newest.isAfter(lastSeen)) return;

    final knownIds = _newlyUnlockedBadges.map((b) => b['id']).toSet();
    for (final b in incoming) {
      final ts = b['awarded_at'] as String?;
      if (ts == null) continue;
      final dt = DateTime.tryParse(ts);
      if (dt == null) continue;
      if (dt.isAfter(lastSeen) && !knownIds.contains(b['id'])) {
        _newlyUnlockedBadges.add(b);
      }
    }
    await prefs.setString(key, newest.toIso8601String());
  }

  Future<void> _saveProfileToPrefs() async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('${_kSnapLevel}_$userId', _level);
    await prefs.setInt('${_kSnapXp}_$userId', _totalXp);
    await prefs.setInt('${_kSnapStreak}_$userId', _currentStreak);
    await prefs.setInt('${_kSnapLongestStreak}_$userId', _longestStreak);
    await prefs.setDouble('${_kSnapXpProgress}_$userId', _xpProgressPct);
    await prefs.setInt('${_kSnapXpCurrentLevel}_$userId', _xpCurrentLevel);
    await prefs.setInt('${_kSnapXpNextLevel}_$userId', _xpNextLevel);
    await prefs.setString('${_kSnapBadges}_$userId', jsonEncode(_badges));
  }

  Future<bool> _loadProfileFromPrefs() async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) return false;
    final prefs = await SharedPreferences.getInstance();
    final cachedLevel = prefs.getInt('${_kSnapLevel}_$userId');
    if (cachedLevel == null) return false;
    _level = cachedLevel;
    _totalXp = prefs.getInt('${_kSnapXp}_$userId') ?? 0;
    _currentStreak = prefs.getInt('${_kSnapStreak}_$userId') ?? 0;
    _longestStreak = prefs.getInt('${_kSnapLongestStreak}_$userId') ?? 0;
    _xpProgressPct = prefs.getDouble('${_kSnapXpProgress}_$userId') ?? 0.0;
    _xpCurrentLevel = prefs.getInt('${_kSnapXpCurrentLevel}_$userId') ?? 0;
    _xpNextLevel = prefs.getInt('${_kSnapXpNextLevel}_$userId') ?? 100;
    final badgesJson = prefs.getString('${_kSnapBadges}_$userId');
    if (badgesJson != null) {
      try {
        _badges = List<Map<String, dynamic>>.from(
          (jsonDecode(badgesJson) as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
      } catch (_) {}
    }
    return true;
  }

  /// Remove the badge with the given id from the unlock queue.
  void acknowledgeBadge(String badgeId) {
    _newlyUnlockedBadges.removeWhere((b) => b['id'] == badgeId);
    notifyListeners();
  }

  /// Acknowledge the level-up so the celebration doesn't replay.
  void acknowledgeLevelUp() {
    _levelUpTriggered = false;
    notifyListeners();
  }

  /// Submit an answer for a question_set mission. Refreshes quests on success.
  /// Returns true if the server accepted the answer.
  Future<bool> submitQuestAnswer({
    required String userQuestId,
    required String questionId,
    required String answer,
  }) async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null || userId.isEmpty) return false;
    final res = await _api.submitQuestAnswer(
      userId: userId,
      userQuestId: userQuestId,
      questionId: questionId,
      answer: answer,
    );
    if (res == null) return false;
    await loadQuests();
    await loadProfile();
    return true;
  }

  /// Attach a completed session to a conversation mission.
  Future<bool> attachQuestSession({
    required String userQuestId,
    required String sessionId,
  }) async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null || userId.isEmpty) return false;
    final res = await _api.attachQuestSession(
      userId: userId,
      userQuestId: userQuestId,
      sessionId: sessionId,
    );
    if (res == null) return false;
    await loadQuests();
    await loadProfile();
    return true;
  }

  // ── Rewards (Phase 3) ─────────────────────────────────────────────────────
  List<Map<String, dynamic>> _rewards = [];
  List<Map<String, dynamic>> get rewards => List.unmodifiable(_rewards);

  bool _rewardsLoading = false;
  bool get rewardsLoading => _rewardsLoading;

  Future<void> loadRewards({bool forceRefresh = false}) async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null || userId.isEmpty) return;
    _rewardsLoading = true;
    notifyListeners();
    try {
      final data = await _api.getRewards(userId);
      if (data != null) {
        _rewards = List<Map<String, dynamic>>.from(data['rewards'] ?? []);
        _xpBalance = (data['balance'] as num?)?.toInt() ?? _xpBalance;
        _xpSpent = (data['xp_spent'] as num?)?.toInt() ?? _xpSpent;
        _totalXp = (data['total_xp'] as num?)?.toInt() ?? _totalXp;
      }
    } catch (e) {
      debugPrint('GamificationProvider.loadRewards error: $e');
    } finally {
      _rewardsLoading = false;
      notifyListeners();
    }
  }

  // ── Leaderboard (Phase 4) ─────────────────────────────────────────────────
  String _leaderboardPeriod = 'all';
  String get leaderboardPeriod => _leaderboardPeriod;

  List<Map<String, dynamic>> _leaderboardRows = [];
  List<Map<String, dynamic>> get leaderboardRows =>
      List.unmodifiable(_leaderboardRows);

  Map<String, dynamic>? _leaderboardSelf;
  Map<String, dynamic>? get leaderboardSelf => _leaderboardSelf;

  bool _leaderboardLoading = false;
  bool get leaderboardLoading => _leaderboardLoading;

  bool _leaderboardOptIn = true;
  bool get leaderboardOptIn => _leaderboardOptIn;

  Future<void> loadLeaderboard({String? period, int limit = 25}) async {
    if (period != null) _leaderboardPeriod = period;
    _leaderboardLoading = true;
    notifyListeners();
    try {
      final data = await _api.getLeaderboard(
        period: _leaderboardPeriod,
        limit: limit,
      );
      if (data != null) {
        _leaderboardRows =
            List<Map<String, dynamic>>.from(data['rows'] ?? []);
        _leaderboardSelf = data['self'] as Map<String, dynamic>?;
        if (_leaderboardSelf != null) {
          _leaderboardOptIn =
              _leaderboardSelf!['leaderboard_opt_in'] as bool? ?? true;
        }
      }
    } catch (e) {
      debugPrint('GamificationProvider.loadLeaderboard error: $e');
    } finally {
      _leaderboardLoading = false;
      notifyListeners();
    }
  }

  Future<bool> setLeaderboardOptIn(bool optIn) async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null || userId.isEmpty) return false;
    final ok =
        await _api.setLeaderboardOptIn(userId: userId, optIn: optIn);
    if (ok) {
      _leaderboardOptIn = optIn;
      notifyListeners();
      await loadLeaderboard();
    }
    return ok;
  }

  /// Redeem a reward by id. Returns null on success, error message on failure.
  Future<String?> redeemReward(String rewardId) async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null || userId.isEmpty) return 'Not signed in';
    final result = await _api.redeemReward(userId: userId, rewardId: rewardId);
    if (result.error != null) return result.error;
    final data = result.data!;
    _xpBalance = (data['new_balance'] as num?)?.toInt() ?? _xpBalance;
    _xpSpent = (data['xp_spent'] as num?)?.toInt() ?? _xpSpent;
    notifyListeners();
    await loadRewards();
    return null;
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
