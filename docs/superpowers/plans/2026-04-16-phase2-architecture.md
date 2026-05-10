# Phase 2 — Architecture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate direct Supabase bypasses by adding focused service classes, replace Navigator 1.0 with go_router for type-safe routing, and replace full-subtree Consumer wraps with Selector for render performance.

**Architecture:** Three independent refactors applied in order: (A) Service layer — `InsightsService`, `UserSettingsService`, `SessionsService` extract all raw Supabase DB calls from screens; `AuthService.accessToken` getter eliminates auth bypasses. (B) Consumer/Selector — `consultant_screen`, `home_screen`, and `new_session_screen` replace their full-Scaffold Consumer wraps with `Selector<T, V>` on the minimal data each sub-widget needs. (C) GoRouter — `app_router.dart` + `RouterNotifier` replace the 28-entry `MaterialApp.routes` map and all `Navigator.pushNamed` / `Navigator.push` calls; `AuthGuard` widget is deleted and auth protection moves to GoRouter's `redirect:` callback.

**Tech Stack:** Flutter/Dart (Provider, Selector, go_router ^14.8.1), Supabase Flutter SDK (direct table access inside services only), SharedPreferences.

**Spec:** `docs/superpowers/specs/2026-04-15-phase1-stabilization-design.md` §8 Out-of-Scope list

---

## File Map

### Part A — Service Layer

| Action | File | Responsibility |
|--------|------|---------------|
| Create | `lib/services/insights_service.dart` | Singleton; events / highlights / notifications table CRUD |
| Create | `lib/services/user_settings_service.dart` | Singleton; `user_settings` table select + upsert |
| Create | `lib/services/sessions_service.dart` | Singleton; session log queries |
| Modify | `lib/services/auth_service.dart` | Add `accessToken` getter + `currentUserId` getter |
| Modify | `lib/screens/insights_screen.dart` | Replace Supabase calls with InsightsService |
| Modify | `lib/services/voice_assistant_service.dart` | Replace user_settings calls with UserSettingsService |
| Modify | `lib/screens/sessions_screen.dart` | Replace session log calls with SessionsService |
| Modify | `lib/widgets/auth_guard.dart` | Replace direct `Supabase.instance.client` with `AuthService.instance` |

### Part B — Consumer/Selector

| Action | File | What changes |
|--------|------|-------------|
| Modify | `lib/screens/consultant_screen.dart` | Move `Consumer<ConsultantProvider>` off Scaffold root; use `Selector` on specific fields |
| Modify | `lib/screens/home_screen.dart` | Move `Consumer<HomeProvider>` off Scaffold body root; use `Selector` |
| Modify | `lib/screens/new_session_screen.dart` | Move `Consumer<SessionProvider>` off Scaffold root; use `Selector` |

### Part C — GoRouter Migration

| Action | File | Responsibility |
|--------|------|---------------|
| Create | `lib/routes/router_notifier.dart` | ChangeNotifier that re-notifies on Supabase auth state changes |
| Create | `lib/routes/app_router.dart` | GoRouter singleton with all 28 routes, redirect callback, custom transitions |
| Modify | `pubspec.yaml` | Add `go_router: ^14.8.1` |
| Modify | `lib/main.dart` | Switch to `MaterialApp.router`; inject `AppRouter.router` |
| Modify | All screens with Navigator calls | Replace `Navigator.pushNamed` / `Navigator.push` with `context.go` / `context.push` |
| Delete | `lib/widgets/auth_guard.dart` | Replaced by GoRouter `redirect:` callback |

---

## Part A — Service Layer

### Task 1: Add `accessToken` and `currentUserId` getters to AuthService

**Files:**
- Modify: `lib/services/auth_service.dart`

AuthService already holds `_client = Supabase.instance.client`. Add two convenience getters so screens stop calling `Supabase.instance.client.auth.*` directly.

- [ ] **Step 1: Read auth_service.dart to find where existing getters live**

```bash
grep -n "get current\|get isLoggedIn\|Session\?" lib/services/auth_service.dart
```

- [ ] **Step 2: Add getters after existing getters**

Find the line where `currentSession` or `currentUser` getter is defined. After the last existing getter, add:

```dart
/// JWT access token for the current session. Null when signed out.
String? get accessToken => _client.auth.currentSession?.accessToken;

/// Supabase user ID for the current session. Null when signed out.
String? get currentUserId => _client.auth.currentUser?.id;
```

- [ ] **Step 3: Fix auth_guard.dart to use AuthService**

Open `lib/widgets/auth_guard.dart`. Replace:

```dart
import 'package:supabase_flutter/supabase_flutter.dart';
```
with:
```dart
import '../services/auth_service.dart';
```

Replace:
```dart
final session = Supabase.instance.client.auth.currentSession;
```
with:
```dart
final session = AuthService.instance.currentSession;
```

- [ ] **Step 4: Commit**

```bash
git add lib/services/auth_service.dart lib/widgets/auth_guard.dart
git commit -m "refactor: add accessToken/currentUserId getters to AuthService; fix AuthGuard bypass"
```

---

### Task 2: Create InsightsService

**Files:**
- Create: `lib/services/insights_service.dart`

Read `lib/screens/insights_screen.dart` first to find the exact table names, column names, and query shapes used. Then create the service.

- [ ] **Step 1: Audit insights_screen.dart Supabase calls**

```bash
grep -n "supabase\|\.from(\|\.select\|\.update\|\.delete\|\.insert\|\.upsert" lib/screens/insights_screen.dart
```

Record: table names, filter columns, order columns, update payload shapes.

- [ ] **Step 2: Create InsightsService**

```dart
// lib/services/insights_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';

/// Encapsulates all Supabase DB access for the Insights screen.
/// Covers: events, highlights, notifications tables.
class InsightsService {
  InsightsService._internal();
  static final InsightsService instance = InsightsService._internal();

  final _client = Supabase.instance.client;

  // ── Events ─────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchEvents(String userId) async {
    final data = await _client
        .from('events')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(data as List);
  }

  Future<void> deleteEvent(String eventId) async {
    await _client.from('events').delete().eq('id', eventId);
  }

  // ── Highlights ─────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchHighlights(String userId) async {
    final data = await _client
        .from('highlights')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(data as List);
  }

  Future<void> deleteHighlight(String highlightId) async {
    await _client.from('highlights').delete().eq('id', highlightId);
  }

  // ── Notifications ──────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchNotifications(String userId) async {
    final data = await _client
        .from('notifications')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(data as List);
  }

  Future<void> markNotificationRead(String notificationId) async {
    await _client
        .from('notifications')
        .update({'read': true})
        .eq('id', notificationId);
  }

  Future<void> deleteNotification(String notificationId) async {
    await _client.from('notifications').delete().eq('id', notificationId);
  }
}
```

> **NOTE:** Adjust table/column names to match what `grep` found in Step 1. The signatures above are the intended interface — do not change method names, only fix table/column strings.

- [ ] **Step 3: Commit**

```bash
git add lib/services/insights_service.dart
git commit -m "feat: add InsightsService encapsulating events/highlights/notifications CRUD"
```

---

### Task 3: Refactor insights_screen.dart to use InsightsService

**Files:**
- Modify: `lib/screens/insights_screen.dart`

- [ ] **Step 1: Add import + remove direct supabase import if no longer needed**

At top of `lib/screens/insights_screen.dart`, add:

```dart
import '../services/insights_service.dart';
import '../services/auth_service.dart';
```

Remove the `supabase_flutter` import if insights_screen no longer needs it after refactor. Check with:

```bash
grep -n "supabase_flutter\|Supabase\." lib/screens/insights_screen.dart
```

- [ ] **Step 2: Replace each Supabase call with InsightsService equivalent**

For every occurrence of a direct `_client.from(...)` or `Supabase.instance.client.from(...)` call, replace with the matching `InsightsService.instance.*` method. Use `AuthService.instance.currentUserId` instead of `Supabase.instance.client.auth.currentUser?.id`.

Pattern — before:
```dart
final data = await Supabase.instance.client
    .from('events')
    .select()
    .eq('user_id', userId)
    .order('created_at', ascending: false);
```

After:
```dart
final data = await InsightsService.instance.fetchEvents(userId);
```

- [ ] **Step 3: Verify no Supabase.instance calls remain**

```bash
grep -n "Supabase\.instance" lib/screens/insights_screen.dart
```

Expected: 0 matches.

- [ ] **Step 4: Run flutter analyze**

```bash
flutter analyze lib/screens/insights_screen.dart
```

Expected: 0 errors.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/insights_screen.dart
git commit -m "refactor: route insights_screen DB calls through InsightsService"
```

---

### Task 4: Create UserSettingsService + refactor voice_assistant_service

**Files:**
- Create: `lib/services/user_settings_service.dart`
- Modify: `lib/services/voice_assistant_service.dart`

- [ ] **Step 1: Audit voice_assistant_service.dart Supabase calls**

```bash
grep -n "supabase\|\.from(\|\.select\|\.upsert\|\.update\|maybeSingle" lib/services/voice_assistant_service.dart
```

Record: table name (`user_settings`), column names, upsert payload shape.

- [ ] **Step 2: Create UserSettingsService**

```dart
// lib/services/user_settings_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';

/// Encapsulates all Supabase access for the user_settings table.
class UserSettingsService {
  UserSettingsService._internal();
  static final UserSettingsService instance = UserSettingsService._internal();

  final _client = Supabase.instance.client;

  /// Returns the user_settings row for [userId], or null if not set.
  Future<Map<String, dynamic>?> fetchSettings(String userId) async {
    final data = await _client
        .from('user_settings')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    return data as Map<String, dynamic>?;
  }

  /// Upserts [payload] for [userId]. Caller provides the full row shape.
  Future<void> upsertSettings(String userId, Map<String, dynamic> payload) async {
    await _client
        .from('user_settings')
        .upsert({'user_id': userId, ...payload});
  }
}
```

> Adjust column names from Step 1 audit if they differ.

- [ ] **Step 3: Refactor voice_assistant_service.dart**

Add imports:
```dart
import 'user_settings_service.dart';
import 'auth_service.dart';
```

Replace each `Supabase.instance.client.from('user_settings')...` call with the matching `UserSettingsService.instance.*` method. Replace `Supabase.instance.client.auth.currentUser?.id` with `AuthService.instance.currentUserId`.

- [ ] **Step 4: Verify no Supabase.instance calls remain in voice_assistant_service**

```bash
grep -n "Supabase\.instance" lib/services/voice_assistant_service.dart
```

Expected: 0 matches (supabase_flutter import may also be removable — check).

- [ ] **Step 5: Run flutter analyze**

```bash
flutter analyze lib/services/voice_assistant_service.dart
```

Expected: 0 errors.

- [ ] **Step 6: Commit**

```bash
git add lib/services/user_settings_service.dart lib/services/voice_assistant_service.dart
git commit -m "feat: add UserSettingsService; route voice_assistant_service through it"
```

---

### Task 5: Create SessionsService + refactor sessions_screen

**Files:**
- Create: `lib/services/sessions_service.dart`
- Modify: `lib/screens/sessions_screen.dart`

- [ ] **Step 1: Audit sessions_screen.dart Supabase calls**

```bash
grep -n "supabase\|\.from(\|\.select\|\.delete\|\.update\|\.insert" lib/screens/sessions_screen.dart
```

Record: table names, filter columns, order columns.

- [ ] **Step 2: Create SessionsService**

```dart
// lib/services/sessions_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';

/// Encapsulates Supabase access for session log queries.
class SessionsService {
  SessionsService._internal();
  static final SessionsService instance = SessionsService._internal();

  final _client = Supabase.instance.client;

  /// Fetch all session logs for [userId], newest first.
  Future<List<Map<String, dynamic>>> fetchSessions(String userId) async {
    final data = await _client
        .from('sessions')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// Delete a session log by [sessionId].
  Future<void> deleteSession(String sessionId) async {
    await _client.from('sessions').delete().eq('id', sessionId);
  }
}
```

> Adjust table/column names to match Step 1 audit results.

- [ ] **Step 3: Refactor sessions_screen.dart**

Add imports:
```dart
import '../services/sessions_service.dart';
import '../services/auth_service.dart';
```

Replace each direct `Supabase.instance.client.from(...)` call with `SessionsService.instance.*`. Replace auth user id access with `AuthService.instance.currentUserId`.

- [ ] **Step 4: Verify**

```bash
grep -n "Supabase\.instance" lib/screens/sessions_screen.dart
flutter analyze lib/screens/sessions_screen.dart
```

Expected: 0 Supabase.instance matches, 0 analyze errors.

- [ ] **Step 5: Commit**

```bash
git add lib/services/sessions_service.dart lib/screens/sessions_screen.dart
git commit -m "feat: add SessionsService; route sessions_screen DB calls through it"
```

---

## Part B — Consumer/Selector Optimization

### Task 6: Fix ConsultantScreen Consumer wrapping entire Scaffold

**Files:**
- Modify: `lib/screens/consultant_screen.dart`

`consultant_screen.dart` wraps the entire `Scaffold` (including `MeshGradientBackground`, drawer, and input area) in a single `Consumer<ConsultantProvider>`. Any ConsultantProvider change (typing indicator, loading state, new message) triggers a full-screen rebuild.

- [ ] **Step 1: Find the outer Consumer in consultant_screen.dart**

```bash
grep -n "Consumer<ConsultantProvider>" lib/screens/consultant_screen.dart
```

Note the opening line number (e.g. line 608) and the closing line (end of build method).

- [ ] **Step 2: Read the full build() method structure**

Read from the Consumer opening line to understand what `cp` (the ConsultantProvider) is used for. Identify distinct sub-usages:
- Message list (needs `cp.messages`, `cp.isLoading`)
- Input area send-button state (needs `cp.isLoading`)
- Drawer history (needs `cp.drawerLoaded`, `cp.pastChats`)
- App bar title (may need `cp.sessionTitle`)

- [ ] **Step 3: Remove outer Consumer; access cp with context.read/watch at call sites**

Replace the outer `Consumer<ConsultantProvider>(builder: (context, cp, _) { return Scaffold(...); })` with just `Scaffold(...)`.

For each sub-widget that previously used `cp.*`, replace with one of:

**For the message list** (rebuilds on every new message — needs `Selector`):
```dart
Selector<ConsultantProvider, List<dynamic>>(
  selector: (_, cp) => cp.messages,
  builder: (context, messages, _) {
    return _buildMessageList(context, messages);
  },
)
```

**For the loading indicator** (rebuilds only when isLoading changes):
```dart
Selector<ConsultantProvider, bool>(
  selector: (_, cp) => cp.isLoading,
  builder: (context, isLoading, _) {
    return isLoading ? const LinearProgressIndicator() : const SizedBox.shrink();
  },
)
```

**For send-button enabled state**:
```dart
Selector<ConsultantProvider, bool>(
  selector: (_, cp) => cp.isLoading,
  builder: (context, isLoading, _) {
    return IconButton(
      onPressed: isLoading ? null : _sendMessage,
      icon: const Icon(Icons.send),
    );
  },
)
```

**For one-time reads in callbacks** (tap handlers, onPressed): use `context.read<ConsultantProvider>()`.

- [ ] **Step 4: Run flutter analyze**

```bash
flutter analyze lib/screens/consultant_screen.dart
```

Expected: 0 errors.

- [ ] **Step 5: Smoke-test the screen manually**

Start the app, navigate to Consultant screen. Verify: messages display, send button works, loading indicator appears during AI response, drawer opens with past chats.

- [ ] **Step 6: Commit**

```bash
git add lib/screens/consultant_screen.dart
git commit -m "perf: replace full-Scaffold Consumer with Selector in ConsultantScreen"
```

---

### Task 7: Fix HomeScreen Consumer wrapping entire Scaffold body

**Files:**
- Modify: `lib/screens/home_screen.dart`

- [ ] **Step 1: Find Consumer usages in home_screen.dart**

```bash
grep -n "Consumer<" lib/screens/home_screen.dart
```

Note which Consumer wraps the largest subtree (likely the Scaffold body).

- [ ] **Step 2: Identify what fields are actually used from HomeProvider**

Read the section of build() inside the Consumer. List the specific fields read from `home` (the HomeProvider instance).

- [ ] **Step 3: Replace Consumer with Selector on specific fields**

If the body Consumer only uses `home.isLoading` and `home.profile`, replace with:

```dart
Selector<HomeProvider, (bool, dynamic)>(
  selector: (_, home) => (home.isLoading, home.profile),
  builder: (context, data, _) {
    final (isLoading, profile) = data;
    // original body build using isLoading + profile
  },
)
```

If multiple fields are needed and most of the body depends on them, consider splitting the body into a named private method `_buildBody(BuildContext context, HomeProvider home)` and keeping a narrower Consumer around only the parts that change.

For one-off reads (button onPressed, initState): `context.read<HomeProvider>()`.

- [ ] **Step 4: Verify**

```bash
flutter analyze lib/screens/home_screen.dart
```

Expected: 0 errors. Smoke-test: home screen loads, profile shown, tabs navigate.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/home_screen.dart
git commit -m "perf: replace full-body Consumer with Selector in HomeScreen"
```

---

### Task 8: Fix NewSessionScreen Consumer wrapping entire Scaffold

**Files:**
- Modify: `lib/screens/new_session_screen.dart`

- [ ] **Step 1: Find Consumer in new_session_screen.dart**

```bash
grep -n "Consumer<" lib/screens/new_session_screen.dart
```

The outer Consumer wraps Scaffold + MeshGradientBackground + Stack with animated blobs (~line 287). This is a 900-line build method — only `session.isSessionActive` and `session.status` are likely needed to drive UI state.

- [ ] **Step 2: Read what fields from SessionProvider drive visible UI changes**

Look at references to the Consumer's `session` variable. Categorize:
- State-driven layout changes (e.g. `session.isSessionActive` → show/hide controls)
- Status text display (`session.status`)
- One-time reads in callbacks

- [ ] **Step 3: Replace Consumer with Selector**

```dart
Selector<SessionProvider, (bool, String)>(
  selector: (_, s) => (s.isSessionActive, s.status),
  builder: (context, data, _) {
    final (isActive, status) = data;
    return Scaffold(
      // use isActive + status; use context.read<SessionProvider>() in callbacks
    );
  },
)
```

Everywhere SessionProvider is read inside a callback or initState: use `context.read<SessionProvider>()`.

- [ ] **Step 4: Verify**

```bash
flutter analyze lib/screens/new_session_screen.dart
```

Expected: 0 errors. Smoke-test: session start/stop works, UI responds to state changes.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/new_session_screen.dart
git commit -m "perf: replace full-Scaffold Consumer with Selector in NewSessionScreen"
```

---

## Part C — GoRouter Migration

### Task 9: Add go_router to pubspec.yaml

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add go_router dependency**

In `pubspec.yaml`, under `dependencies:`, add after `provider: ^6.1.5+1`:

```yaml
  go_router: ^14.8.1
```

- [ ] **Step 2: Run flutter pub get**

```bash
flutter pub get
```

Expected: Resolves without errors. Verify go_router appears in pubspec.lock:
```bash
grep "go_router:" pubspec.lock
```

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "deps: add go_router ^14.8.1"
```

---

### Task 10: Create RouterNotifier

**Files:**
- Create: `lib/routes/router_notifier.dart`

GoRouter's `refreshListenable:` needs a `Listenable` that fires when auth state changes. This notifier bridges Supabase's auth stream to GoRouter.

- [ ] **Step 1: Create router_notifier.dart**

```dart
// lib/routes/router_notifier.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Bridges Supabase auth state changes to GoRouter's refreshListenable.
/// GoRouter calls redirect() whenever this notifies.
class RouterNotifier extends ChangeNotifier {
  late final StreamSubscription<AuthState> _sub;

  RouterNotifier() {
    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/routes/router_notifier.dart
git commit -m "feat: add RouterNotifier for GoRouter auth refresh"
```

---

### Task 11: Create app_router.dart with all 28 routes

**Files:**
- Create: `lib/routes/app_router.dart`

This is the central routing config. Read `lib/main.dart` lines 180–335 (the routes map and onGenerateRoute) before writing — you need the exact screen class names and import paths.

- [ ] **Step 1: Read the current routes map in main.dart**

```bash
grep -n "AppRoutes\." lib/main.dart | head -60
```

Also read onGenerateRoute (lines ~210–283) for the 3 custom-transition routes.

- [ ] **Step 2: Read all screen import paths currently in main.dart**

```bash
grep -n "^import.*screens\|^import.*widgets" lib/main.dart
```

- [ ] **Step 3: Create app_router.dart**

```dart
// lib/routes/app_router.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_routes.dart';
import 'router_notifier.dart';

// Screen imports — match exactly what is in main.dart
import '../screens/splash_screen.dart';
import '../screens/login_screen.dart';
import '../screens/signup_screen.dart';
import '../screens/verify_email_screen.dart';
import '../screens/profile_completion_screen.dart';
import '../screens/home_screen.dart';
import '../screens/connections_screen.dart';
import '../screens/new_session_screen.dart';
import '../screens/consultant_screen.dart';
import '../screens/sessions_screen.dart';
import '../screens/about_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/entity_screen.dart';
import '../screens/session_analytics_screen.dart';
import '../screens/roleplay_setup_screen.dart';
import '../screens/quests_screen.dart';
import '../screens/graph_explorer_screen.dart';
import '../screens/health_dashboard_screen.dart';
import '../screens/expense_tracker_screen.dart';
import '../screens/tasks_screen.dart';
import '../screens/smart_home_dashboard_screen.dart';
import '../screens/trips_planner_screen.dart';
import '../screens/integrations_hub_screen.dart';
import '../screens/subscription_screen.dart';
import '../screens/insights_screen.dart';
import '../screens/language_screen.dart';
import '../screens/permissions_screen.dart';
import '../screens/data_management_screen.dart';
import '../providers/iot_manager_provider.dart';

/// Routes that do NOT require authentication.
const _publicRoutes = {
  AppRoutes.login,
  AppRoutes.signup,
  AppRoutes.verifyEmail,
};

class AppRouter {
  AppRouter._();

  static final _notifier = RouterNotifier();

  static final router = GoRouter(
    initialLocation: AppRoutes.home,
    refreshListenable: _notifier,
    redirect: (context, state) {
      final session = Supabase.instance.client.auth.currentSession;
      final isLoggedIn = session != null;
      final isPublic = _publicRoutes.contains(state.matchedLocation);

      if (!isLoggedIn && !isPublic) return AppRoutes.login;
      if (isLoggedIn && isPublic) return AppRoutes.home;
      return null; // no redirect
    },
    routes: [
      // ── Auth (public) ──────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.login,
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.signup,
        builder: (_, __) => const SignupScreen(),
      ),
      GoRoute(
        path: AppRoutes.verifyEmail,
        builder: (_, __) => const VerifyEmailScreen(),
      ),
      GoRoute(
        path: AppRoutes.profileCompletion,
        builder: (_, __) => const ProfileCompletionScreen(),
      ),

      // ── Core screens ───────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.home,
        builder: (_, __) => const HomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.connections,
        builder: (_, __) => const ConnectionsScreen(),
      ),
      GoRoute(
        path: AppRoutes.newSession,
        builder: (_, __) => const NewSessionScreen(),
      ),
      GoRoute(
        path: AppRoutes.consultant,
        builder: (_, __) => const ConsultantScreen(),
      ),
      GoRoute(
        path: AppRoutes.sessions,
        builder: (_, __) => const SessionsScreen(),
      ),
      GoRoute(
        path: AppRoutes.about,
        builder: (_, __) => const AboutScreen(),
      ),

      // ── Settings (slide-from-left transition) ─────────────────────────────
      GoRoute(
        path: AppRoutes.settings,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const SettingsScreen(),
          transitionsBuilder: (context, animation, _, child) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(-1.0, 0.0),
                end: Offset.zero,
              ).chain(CurveTween(curve: Curves.easeInOut)).animate(animation),
              child: child,
            );
          },
        ),
      ),
      GoRoute(
        path: AppRoutes.language,
        builder: (_, __) => const LanguageScreen(),
      ),
      GoRoute(
        path: AppRoutes.permissions,
        builder: (_, __) => const PermissionsScreen(),
      ),
      GoRoute(
        path: AppRoutes.data,
        builder: (_, __) => const DataManagementScreen(),
      ),
      GoRoute(
        path: AppRoutes.subscription,
        builder: (_, __) => const SubscriptionScreen(),
      ),

      // ── Entities (slide-from-right transition) ────────────────────────────
      GoRoute(
        path: AppRoutes.entities,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const EntityScreen(),
          transitionsBuilder: (context, animation, _, child) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1.0, 0.0),
                end: Offset.zero,
              ).chain(CurveTween(curve: Curves.easeInOut)).animate(animation),
              child: child,
            );
          },
        ),
      ),

      // ── Session analytics (slide-from-bottom transition) ──────────────────
      GoRoute(
        path: AppRoutes.sessionAnalytics,
        pageBuilder: (context, state) {
          final args = state.extra as Map<String, String>?;
          return CustomTransitionPage(
            key: state.pageKey,
            child: SessionAnalyticsScreen(
              sessionId: args?['sessionId'] ?? '',
              sessionTitle: args?['sessionTitle'] ?? 'Session',
            ),
            transitionsBuilder: (context, animation, _, child) {
              return SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.0, 1.0),
                  end: Offset.zero,
                ).chain(CurveTween(curve: Curves.easeInOut)).animate(animation),
                child: child,
              );
            },
          );
        },
      ),

      // ── Feature screens ───────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.roleplaySetup,
        builder: (_, __) => const RoleplaySetupScreen(),
      ),
      GoRoute(
        path: AppRoutes.quests,
        builder: (_, __) => const QuestsScreen(),
      ),
      GoRoute(
        path: AppRoutes.graphExplorer,
        builder: (_, __) => const GraphExplorerScreen(),
      ),
      GoRoute(
        path: AppRoutes.insights,
        builder: (_, __) => const InsightsScreen(),
      ),
      GoRoute(
        path: AppRoutes.healthDashboard,
        builder: (_, __) => const HealthDashboardScreen(),
      ),
      GoRoute(
        path: AppRoutes.expensesTracker,
        builder: (_, __) => const ExpenseTrackerScreen(),
      ),
      GoRoute(
        path: AppRoutes.tasks,
        builder: (_, __) => const TasksScreen(),
      ),
      // SmartHome scopes IoTManagerProvider to this route only
      GoRoute(
        path: AppRoutes.smartHome,
        builder: (context, _) => ChangeNotifierProvider(
          create: (_) => IoTManagerProvider(),
          child: const SmartHomeDashboardScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.tripsPlanner,
        builder: (_, __) => const TripsPlannerScreen(),
      ),
      GoRoute(
        path: AppRoutes.integrations,
        builder: (_, __) => const IntegrationsHubScreen(),
      ),
    ],
  );
}
```

- [ ] **Step 4: Run flutter analyze on the new file**

```bash
flutter analyze lib/routes/app_router.dart
```

Fix any import path mismatches (screen file names vs import paths).

- [ ] **Step 5: Commit**

```bash
git add lib/routes/app_router.dart
git commit -m "feat: add AppRouter with GoRouter config and all 28 routes"
```

---

### Task 12: Switch main.dart to MaterialApp.router

**Files:**
- Modify: `lib/main.dart`

**Warning:** This step breaks navigation until Task 13 is complete. Complete Tasks 12 and 13 in one session without stopping.

- [ ] **Step 1: Add AppRouter import to main.dart**

```dart
import 'routes/app_router.dart';
```

- [ ] **Step 2: Remove all screen imports that were only used in the routes map**

Any screen import only referenced inside `MaterialApp.routes` or `onGenerateRoute` can be removed — those screens are now imported by `app_router.dart`. Keep imports for screens used elsewhere in `main.dart` (e.g. SplashScreen if used as `home:`).

- [ ] **Step 3: Replace MaterialApp with MaterialApp.router**

Find the `MaterialApp(` constructor call. Replace with `MaterialApp.router(`:

Remove these parameters entirely (they move to GoRouter):
- `home: const SplashScreen()`
- `routes: { ... }` (entire map)
- `onGenerateRoute: (settings) { ... }` (entire callback)

Add these parameters:
```dart
routerConfig: AppRouter.router,
```

Keep these parameters unchanged:
- `navigatorKey` — **remove** this; GoRouter manages its own navigator key. If `BubblesApp.navigatorKey` is used elsewhere, replace those usages with `AppRouter.router.routerDelegate.navigatorKey` or remove if only used for navigation.
- `debugShowCheckedModeBanner: false`
- `title: 'Bubbles'`
- `themeMode`, `theme`, `darkTheme`
- `locale`, `supportedLocales`, `localizationsDelegates`
- `builder:` — keep the `_VoiceOverlayWrapper` builder

> **Note on navigatorKey:** GoRouter doesn't accept an external `navigatorKey` via `MaterialApp.router`. If `BubblesApp.navigatorKey` is used in `_AnalyticsNavigatorObserver` or notification handling, pass it to GoRouter instead:
> ```dart
> static final router = GoRouter(
>   navigatorKey: BubblesApp.navigatorKey,
>   ...
> )
> ```
> Add `navigatorKey: BubblesApp.navigatorKey` as the first parameter in `AppRouter.router` inside `app_router.dart`.

- [ ] **Step 4: Remove the AuthGuard import from main.dart**

```dart
// Remove:
import 'widgets/auth_guard.dart';
```

- [ ] **Step 5: Run flutter analyze on main.dart**

```bash
flutter analyze lib/main.dart
```

Expected at this stage: likely errors about `Navigator.pushNamed` calls in other files referencing `BubblesApp.navigatorKey` — those will be fixed in Task 13. Fix only `main.dart`-specific errors here.

- [ ] **Step 6: DO NOT COMMIT YET** — continue to Task 13.

---

### Task 13: Replace all Navigator calls with context.go / context.push

**Files:**
- Modify: All files containing `Navigator.pushNamed`, `Navigator.push`, `Navigator.pushReplacementNamed`, `Navigator.pop`

This task must be completed in the same session as Task 12 before committing.

- [ ] **Step 1: Find all Navigator call sites**

```bash
grep -rn "Navigator\." lib/ --include="*.dart" | grep -v "//\|NavigatorState\|NavigatorObserver\|NavigatorKey"
```

Work through every file in the output.

- [ ] **Step 2: Apply replacement rules**

| Old pattern | New pattern |
|-------------|-------------|
| `Navigator.pushNamed(context, route)` | `context.go(route)` or `context.push(route)` — see rule below |
| `Navigator.pushReplacementNamed(context, route)` | `context.go(route)` |
| `Navigator.push(context, MaterialPageRoute(builder: (_) => Screen()))` | `context.push(AppRoutes.screenRoute)` |
| `Navigator.pop(context)` | `context.pop()` |
| `Navigator.of(context).pushReplacementNamed(route)` | `context.go(route)` |

**Rule for go vs push:**
- Auth redirects (login → home, signup → home): `context.go` (replaces stack)
- Normal forward navigation (home → detail): `context.push` (preserves back button)
- Back from sub-screens: `context.pop()`

- [ ] **Step 3: Fix sessionAnalytics navigation (uses arguments)**

All call sites that do:
```dart
Navigator.pushNamed(context, AppRoutes.sessionAnalytics, arguments: {'sessionId': id, 'sessionTitle': title})
```

Replace with:
```dart
context.push(AppRoutes.sessionAnalytics, extra: {'sessionId': id, 'sessionTitle': title})
```

- [ ] **Step 4: Fix BubblesApp.navigatorKey usages if any**

```bash
grep -rn "BubblesApp.navigatorKey\|navigatorKey" lib/ --include="*.dart"
```

If found outside `main.dart`, update to use `AppRouter.router.routerDelegate.navigatorKey` or `AppRouter.router.routerDelegate.context` pattern as appropriate.

- [ ] **Step 5: Run full flutter analyze**

```bash
flutter analyze lib/
```

Expected: 0 errors. Fix any remaining Navigator or route issues.

- [ ] **Step 6: Delete auth_guard.dart**

```bash
git rm lib/widgets/auth_guard.dart
```

- [ ] **Step 7: Commit both Task 12 and 13 together**

```bash
git add lib/main.dart lib/routes/app_router.dart lib/routes/router_notifier.dart
git add $(git diff --name-only)  # all modified screen files
git commit -m "feat: migrate to go_router; replace Navigator 1.0 and delete AuthGuard"
```

---

### Task 14: Smoke-test full navigation flow

**Files:** None — verification only.

- [ ] **Step 1: Run flutter analyze**

```bash
flutter analyze lib/
```

Expected: 0 errors.

- [ ] **Step 2: Start app — verify splash → login → home flow**

```bash
flutter run
```

- Sign out if logged in. Verify:
  - App opens on login screen (not home)
  - Login navigates to home
  - Back button from home does not go back to login

- [ ] **Step 3: Verify all drawer/tab navigation paths**

Open app drawer (if exists). Tap each major route. Verify each screen loads without errors.

- [ ] **Step 4: Verify settings slide-from-left animation**

Navigate to Settings. Verify the slide-from-left animation plays correctly.

- [ ] **Step 5: Verify session analytics slide-from-bottom animation**

Navigate to a session, open analytics. Verify slide-from-bottom.

- [ ] **Step 6: Verify SmartHome IoTManagerProvider scoping**

Navigate to Smart Home. Verify it loads. Navigate away and back. Verify no provider errors in console.

- [ ] **Step 7: Final commit if any smoke-test fixes were needed**

```bash
git add -p  # stage only smoke-test fixes
git commit -m "fix: post-GoRouter smoke-test fixes"
```

---

## Self-Review

### Spec Coverage

| Phase 2 item | Tasks covering it |
|-------------|-----------------|
| Repository pattern / bypassed ApiService layers | Tasks 1–5 |
| GoRouter migration | Tasks 9–14 |
| Selector / Consumer refactoring | Tasks 6–8 |

### Placeholder Scan

- Task 2 and 3: "Adjust table/column names" — non-placeholder; instructs subagent to read the file first and use actual values. Required because exact column names are in screen code, not audit.
- Task 11: screen import list is complete based on main.dart imports listed in audit. Subagent must verify with `grep` step.

### Type Consistency

- `InsightsService.instance.fetchEvents(userId)` — defined Task 2, used Task 3. ✓
- `UserSettingsService.instance.fetchSettings(userId)` — defined Task 4, used Task 4. ✓
- `SessionsService.instance.fetchSessions(userId)` — defined Task 5, used Task 5. ✓
- `AuthService.instance.accessToken` — defined Task 1, used in voice_assistant_service (Task 4). ✓
- `AuthService.instance.currentUserId` — defined Task 1, used Tasks 3, 4, 5. ✓
- `AppRouter.router` — defined Task 11, used Task 12. ✓
- `RouterNotifier` — defined Task 10, imported in Task 11. ✓
- `state.extra as Map<String, String>?` — used in Task 11 (route def) and Task 13 (call site). ✓
