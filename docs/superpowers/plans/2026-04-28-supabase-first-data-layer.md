# Supabase-First Data Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate Flutter→FastAPI reads for data-at-rest; all persisted data is read directly from Supabase, with Realtime subscriptions for volatile tables and auto-hydration on server reconnect and login.

**Architecture:** Most repositories already query Supabase directly. The only FastAPI-dependent read left is `GamificationRepository.getGamification`. We migrate that to Supabase, create `HydrationService` to trigger parallel refreshes, and wire it to `ConnectionService` reconnects and auth events. Realtime subscriptions on `user_gamification`, `entities`, and `sessions` tables keep volatile data live.

**Tech Stack:** Flutter, `supabase_flutter`, Provider/ChangeNotifier, `dart:async` StreamSubscription

**Spec:** `docs/superpowers/specs/2026-04-27-supabase-first-data-layer-design.md`

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `lib/utils/xp_math.dart` | Create | XP↔level conversion math (ported from Python) |
| `lib/repositories/gamification_repository.dart` | Modify | Replace FastAPI `getGamification` call with 3 Supabase queries |
| `lib/services/hydration_service.dart` | Create | Parallel repo refresh + Realtime subscriptions + reconnect wiring |
| `lib/main.dart` | Modify | Register HydrationService; wire auth events to setUserId/clearUserId |

---

## Task 1: XP Math Utility

**Files:**
- Create: `lib/utils/xp_math.dart`

Port the Python formulas from `server_v2/app/services/gamification_service.py` lines 44–56:
- `_xp_for_level(level)` = `50 * level * (level - 1)`
- `_level_for_xp(xp)` = `floor((1 + sqrt(1 + 4*xp/50)) / 2)` clamped to ≥ 1

- [ ] **Step 1: Create the utility file**

```dart
// lib/utils/xp_math.dart
import 'dart:math';

int xpForLevel(int level) => 50 * level * (level - 1);

int levelForXp(int totalXp) {
  if (totalXp <= 0) return 1;
  final level = ((1 + sqrt(1 + 4 * totalXp / 50)) / 2).floor();
  return max(1, level);
}
```

- [ ] **Step 2: Verify the math against known values**

Run this in a Dart scratch or via `flutter test`:
```
levelForXp(0)    == 1   (0 XP → level 1)
xpForLevel(1)    == 0   (level 1 starts at 0 XP)
xpForLevel(2)    == 100 (level 2 starts at 100 XP)
levelForXp(100)  == 2   (100 XP → level 2)
levelForXp(99)   == 1   (99 XP still level 1)
xpForLevel(3)    == 300
levelForXp(300)  == 3
```

- [ ] **Step 3: Commit**

```bash
git add lib/utils/xp_math.dart
git commit -m "feat: add XP level math utility (ported from Python)"
```

---

## Task 2: Migrate GamificationRepository.getGamification to Supabase

**Files:**
- Modify: `lib/repositories/gamification_repository.dart`

Replace `networkFetch: () => _api.getGamification(userId)` with 3 direct Supabase queries:
1. `user_gamification` for raw XP/streak fields
2. `user_achievements` joined with `achievements` for badges
3. `xp_transactions` for recent XP history

Keep `_api` — it's still used by `getQuests` and `getPerformanceSummary`.

- [ ] **Step 1: Add imports and SupabaseClient field**

At the top of `lib/repositories/gamification_repository.dart`, after the existing imports, add:
```dart
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/xp_math.dart';
```

Inside the class body, after `final ApiService _api;`, add:
```dart
final SupabaseClient _client = Supabase.instance.client;
```

- [ ] **Step 2: Replace getGamification networkFetch**

Replace the entire `getGamification` method with:

```dart
Future<CacheResult<Map<String, dynamic>>> getGamification(String userId, {bool forceRefresh = false}) async {
  return fetch<Map<String, dynamic>>(
    key: CacheKeys.gamification(userId),
    userId: userId,
    policy: forceRefresh ? FetchPolicy.networkFirst : FetchPolicy.staleWhileRevalidate,
    ttlSeconds: CacheTtl.gamification.inSeconds,
    schemaVersion: CacheSchemaVersion.gamification,
    networkFetch: () async {
      // 1. Raw profile row
      final profileRes = await _client
          .from('user_gamification')
          .select('*')
          .eq('user_id', userId)
          .maybeSingle();

      if (profileRes == null) {
        return _defaultGamificationProfile();
      }

      final profile = Map<String, dynamic>.from(profileRes);
      final totalXp = (profile['total_xp'] as num? ?? 0).toInt();
      final xpSpent = (profile['xp_spent'] as num? ?? 0).toInt();
      final level = levelForXp(totalXp);
      final xpCurrentLevel = xpForLevel(level);
      final xpNextLevel = xpForLevel(level + 1);
      final range = xpNextLevel - xpCurrentLevel;

      // 2. Badges
      final badgesRes = await _client
          .from('user_achievements')
          .select('achievement_id, awarded_at, achievements(id, title, description, icon, category, tier, code)')
          .eq('user_id', userId);

      final badges = (badgesRes as List).map((row) {
        final a = Map<String, dynamic>.from(row['achievements'] as Map? ?? {});
        return <String, dynamic>{
          'id': a['id'] ?? row['achievement_id'],
          'title': a['title'] ?? '',
          'description': a['description'] ?? '',
          'icon': a['icon'] ?? '🏆',
          'category': a['category'] ?? 'general',
          'tier': a['tier'] ?? 'bronze',
          'code': a['code'] ?? '',
          'awarded_at': row['awarded_at'],
        };
      }).toList();

      // 3. Recent XP transactions
      final xpRes = await _client
          .from('xp_transactions')
          .select('amount, reason, created_at')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(10);

      return <String, dynamic>{
        'xp': totalXp,
        'level': level,
        'xp_current_level': xpCurrentLevel,
        'xp_next_level': xpNextLevel,
        'xp_to_next_level': xpNextLevel - totalXp,
        'xp_progress_pct': range <= 0 ? 1.0 : (totalXp - xpCurrentLevel) / range,
        'current_streak': profile['current_streak'] ?? 0,
        'longest_streak': profile['longest_streak'] ?? 0,
        'streak_freezes': profile['streak_freezes'] ?? 0,
        'last_active_date': profile['last_active_date'],
        'xp_spent': xpSpent,
        'xp_balance': totalXp - xpSpent,
        'badges': badges,
        'recent_xp': List<Map<String, dynamic>>.from(xpRes),
        'stats': {
          'total_sessions': profile['total_sessions'] ?? 0,
          'total_questions': profile['total_questions'] ?? 0,
        },
      };
    },
    fromJson: (json) => Map<String, dynamic>.from(json),
    toJson: (data) => data,
  );
}

Map<String, dynamic> _defaultGamificationProfile() => {
  'xp': 0,
  'level': 1,
  'xp_current_level': 0,
  'xp_next_level': 100,
  'xp_to_next_level': 100,
  'xp_progress_pct': 0.0,
  'current_streak': 0,
  'longest_streak': 0,
  'streak_freezes': 1,
  'last_active_date': null,
  'xp_spent': 0,
  'xp_balance': 0,
  'badges': <Map<String, dynamic>>[],
  'recent_xp': <Map<String, dynamic>>[],
  'stats': {'total_sessions': 0, 'total_questions': 0},
};
```

- [ ] **Step 3: Hot-reload and open Game Center screen**

Verify:
- XP ring renders correctly
- Streak displays correctly
- Badges list renders (may be empty for test user)
- No exceptions in the console

- [ ] **Step 4: Commit**

```bash
git add lib/repositories/gamification_repository.dart lib/utils/xp_math.dart
git commit -m "feat: migrate GamificationRepository.getGamification to Supabase direct"
```

---

## Task 3: Create HydrationService

**Files:**
- Create: `lib/services/hydration_service.dart`

This service:
- Holds refs to all 8 repositories + `ConnectionService`
- Watches `ConnectionService` for reconnect events (disconnected→connected transition)
- On reconnect or `setUserId`, calls `refreshAll()` in parallel
- Manages 3 Supabase Realtime stream subscriptions (user_gamification, entities, sessions)

- [ ] **Step 1: Create hydration_service.dart**

```dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../repositories/profile_repository.dart';
import '../repositories/settings_repository.dart';
import '../repositories/home_repository.dart';
import '../repositories/insights_repository.dart';
import '../repositories/graph_repository.dart';
import '../repositories/entity_repository.dart';
import '../repositories/gamification_repository.dart';
import '../repositories/sessions_repository.dart';
import 'connection_service.dart';

class HydrationService with ChangeNotifier {
  final ConnectionService _connection;
  final ProfileRepository _profile;
  final SettingsRepository _settings;
  final HomeRepository _home;
  final InsightsRepository _insights;
  final GraphRepository _graph;
  final EntityRepository _entity;
  final GamificationRepository _gamification;
  final SessionsRepository _sessions;

  String? _userId;
  ConnectionStatus _lastStatus = ConnectionStatus.disconnected;
  final List<StreamSubscription> _realtimeSubs = [];

  HydrationService({
    required ConnectionService connection,
    required ProfileRepository profile,
    required SettingsRepository settings,
    required HomeRepository home,
    required InsightsRepository insights,
    required GraphRepository graph,
    required EntityRepository entity,
    required GamificationRepository gamification,
    required SessionsRepository sessions,
  })  : _connection = connection,
        _profile = profile,
        _settings = settings,
        _home = home,
        _insights = insights,
        _graph = graph,
        _entity = entity,
        _gamification = gamification,
        _sessions = sessions {
    _connection.addListener(_onConnectionChanged);
  }

  /// Called on login. Triggers initial hydration and Realtime subscriptions.
  void setUserId(String userId) {
    _userId = userId;
    refreshAll(userId);
    _initRealtime(userId);
  }

  /// Called on logout. Cancels Realtime subscriptions.
  void clearUserId() {
    _userId = null;
    _cancelRealtime();
  }

  /// Force-refresh all repositories in parallel.
  Future<void> refreshAll(String userId) async {
    await Future.wait([
      _profile.getProfile(userId, forceRefresh: true),
      _settings.loadSettings(userId),
      _home.getEvents(userId, forceRefresh: true),
      _home.getHighlights(userId, forceRefresh: true),
      _home.getNotifications(userId, forceRefresh: true),
      _insights.getEvents(userId, forceRefresh: true),
      _insights.getHighlights(userId, forceRefresh: true),
      _insights.getNotifications(userId, forceRefresh: true),
      _graph.getGraphExport(userId, forceRefresh: true),
      _entity.getEntities(userId, forceRefresh: true),
      _gamification.getGamification(userId, forceRefresh: true),
      _gamification.getQuests(userId, forceRefresh: true),
      _sessions.getConsultantSessions(userId, forceRefresh: true),
    ]);
  }

  void _onConnectionChanged() {
    final newStatus = _connection.status;
    final wasDisconnected = _lastStatus != ConnectionStatus.connected;
    final nowConnected = newStatus == ConnectionStatus.connected;
    if (nowConnected && wasDisconnected && _userId != null) {
      refreshAll(_userId!);
    }
    _lastStatus = newStatus;
  }

  void _initRealtime(String userId) {
    _cancelRealtime();
    final client = Supabase.instance.client;

    // user_gamification → refresh gamification cache on XP/streak change
    _realtimeSubs.add(
      client
          .from('user_gamification')
          .stream(primaryKey: ['id'])
          .eq('user_id', userId)
          .listen((_) => _gamification.getGamification(userId, forceRefresh: true)),
    );

    // entities → refresh entity cache when server extracts new entities
    _realtimeSubs.add(
      client
          .from('entities')
          .stream(primaryKey: ['id'])
          .eq('user_id', userId)
          .listen((_) => _entity.getEntities(userId, forceRefresh: true)),
    );

    // sessions → refresh sessions list when a new session is saved
    _realtimeSubs.add(
      client
          .from('sessions')
          .stream(primaryKey: ['id'])
          .eq('user_id', userId)
          .listen((_) => _sessions.getConsultantSessions(userId, forceRefresh: true)),
    );
  }

  void _cancelRealtime() {
    for (final sub in _realtimeSubs) {
      sub.cancel();
    }
    _realtimeSubs.clear();
  }

  @override
  void dispose() {
    _connection.removeListener(_onConnectionChanged);
    _cancelRealtime();
    super.dispose();
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/services/hydration_service.dart
git commit -m "feat: add HydrationService for parallel repo refresh and Realtime subscriptions"
```

---

## Task 4: Register HydrationService in main.dart

**Files:**
- Modify: `lib/main.dart`

Add `HydrationService` as a `ChangeNotifierProvider` after all repository providers. Then wire auth events.

- [ ] **Step 1: Add import at top of main.dart**

After the existing service imports, add:
```dart
import 'services/hydration_service.dart';
```

- [ ] **Step 2: Add HydrationService provider after SessionsRepository**

In `lib/main.dart`, find the `SessionsRepository` ProxyProvider block (the last repo in the list). After it, add:

```dart
// Hydration Service — depends on all repos + ConnectionService
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
```

- [ ] **Step 3: Wire auth events in main() onAuthStateChange listener**

Find this block in `main()`:
```dart
Supabase.instance.client.auth.onAuthStateChange.listen((data) {
  final event = data.event;
  if (event == AuthChangeEvent.signedIn) {
    DeviceService.instance.registerDevice();
  } else if (event == AuthChangeEvent.signedOut) {
    AnalyticsService.instance.flushNow();
  }
```

Replace with:
```dart
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
  }
```

- [ ] **Step 4: Add Provider import if missing**

Ensure `import 'package:provider/provider.dart';` is present at top of main.dart (it likely already is).

- [ ] **Step 5: Hot-restart and log in**

Open the console. You should see no exceptions. After login:
- Game Center XP should load (Supabase direct)
- Sessions list should load
- Entities screen should load

All should work while the FastAPI server is stopped (kill the server process), confirming Supabase-direct reads work independently of the server.

- [ ] **Step 6: Commit**

```bash
git add lib/main.dart
git commit -m "feat: register HydrationService and wire auth events for auto-hydration"
```

---

## Task 5: Verify Realtime Works

- [ ] **Step 1: Test Realtime subscription for gamification**

With the app running and logged in:
1. Open a Supabase dashboard → Table editor → `user_gamification`
2. Manually update `total_xp` by +50 for your test user
3. Observe that the Game Center XP ring updates within ~1-2 seconds without any user action

- [ ] **Step 2: Test Realtime subscription for sessions**

1. Complete a consultant session in the app (or manually insert a row into `sessions` via Supabase dashboard)
2. Navigate to Sessions screen
3. Verify new session appears without manual refresh

- [ ] **Step 3: Test reconnect hydration**

1. Kill the FastAPI server
2. Use the app for a moment (some things will fail that still need server)
3. Restart the FastAPI server
4. Wait for ConnectionService to reconnect (watch the connection indicator)
5. Verify that gamification, sessions, and entities screens silently refresh

- [ ] **Step 4: Commit test confirmation**

```bash
git add -p  # stage any minor fixes from testing
git commit -m "test: verify Supabase Realtime subscriptions and reconnect hydration"
```

---

## Task 6: Update todos.md

- [ ] **Step 1: Mark Performance Optimization items done**

In `todos.md`, mark the following complete:
```markdown
- [x] **Auto Reload**: when app connects to the server, automatically update all screens...
- [x] **Supabase Update**: update everything on supabase, and our app fetches most of the data...
- [x] **Store Everythingh**: Store Everything on supabase...
```

- [ ] **Step 2: Commit**

```bash
git add todos.md
git commit -m "docs: mark Supabase-first data layer todos complete"
```
