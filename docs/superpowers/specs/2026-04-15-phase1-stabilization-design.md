# Phase 1 — Stabilization Design Spec

**Date:** 2026-04-15
**Project:** Bubbles AI (Flutter Client + FastAPI Backend)
**Scope:** Sections 1, 3, 4 of the April 2026 Architectural Audit
**Approach:** C — AppCacheService + Sub-screens + Scoped Providers

---

## Overview

Phase 1 fixes all critical stability issues identified in the audit: a client-side API key leak, four static memory leaks, one orphaned stream subscription, excessive root-level provider RAM, a dead-end Forgot Password flow, and four stubbed Settings features. No new external infrastructure is required beyond the existing FastAPI backend and Supabase project.

---

## 1. Security — Deepgram Backend Proxy

### Problem
`lib/services/deepgram_service.dart` connects directly to `wss://api.deepgram.com/v1/listen` using a client-side API key loaded from `.env`. Any extracted APK exposes the key.

### Solution
The FastAPI backend gains a new WebSocket endpoint `GET /stt/stream` that acts as a transparent bidirectional proxy to Deepgram.

**Data flow:**
```
Flutter Client                    FastAPI Backend              Deepgram
DeepgramService                   /stt/stream (WS)
  connects to ──────────────────► validates Supabase JWT
  SERVER_URL/stt/stream           opens upstream WS ─────────► wss://api.deepgram.com
  sends audio frames ───────────► proxies frames ────────────► processes audio
  receives transcripts ◄───────── proxies events ◄──────────── streams transcripts
```

**Authentication:** Flutter sends its Supabase JWT as a query parameter `?token=<jwt>` on the WebSocket handshake. The backend validates it before opening the upstream connection.

**New backend file:** `server/routers/stt.py`

**Modified Flutter file:** `lib/services/deepgram_service.dart` — replace direct Deepgram URL with `${SERVER_URL}/stt/stream?token=<jwt>`. Remove `DEEPGRAM_API_KEY` from Flutter `.env`.

**Error handling:**
- Invalid/missing JWT → backend closes with code `4001 Unauthorized`
- Upstream Deepgram disconnect → backend sends `{"error": "upstream_disconnected"}` and closes; Flutter's existing retry logic handles reconnection
- `SERVER_URL` unreachable → existing `DeepgramService` error state fires

---

## 2. Memory — AppCacheService

### Problem
`EntityScreen` declares `static List<Map<String, dynamic>>? _cachedEntities` (line 30). `InsightsScreen` declares three static lists (`_cachedEvents`, `_cachedHighlights`, `_cachedNotifications`, lines 23–25). All four persist indefinitely with no invalidation — they survive user sign-out and account switching, risking stale data display.

### Solution
**New file:** `lib/services/app_cache_service.dart`

```dart
class AppCacheService extends ChangeNotifier {
  List<Map<String, dynamic>>? entities;
  List<Map<String, dynamic>>? events;
  List<Map<String, dynamic>>? highlights;
  List<Map<String, dynamic>>? notifications;

  void invalidateEntities() { entities = null; notifyListeners(); }
  void invalidateInsights() { events = highlights = notifications = null; notifyListeners(); }
  void invalidateAll() { entities = events = highlights = notifications = null; notifyListeners(); }
}
```

`AppCacheService` is registered in the root `MultiProvider`. `EntityScreen` and `InsightsScreen` replace all static field reads/writes with `context.read<AppCacheService>()`.

**Invalidation triggers:**
1. `AuthService.signOut()` calls `appCacheService.invalidateAll()`
2. App cold start (in-memory only — never persisted to disk)
3. Manual pull-to-refresh in `EntityScreen` and `InsightsScreen`

---

## 3. Memory — Orphaned Stream Fix

### Problem
`ConsultantScreen` line 309: `_ttsPlayer.onPlayerComplete.listen((_) { ... })` — the returned `StreamSubscription` is discarded. The listener is never cancelled in `dispose()`.

### Solution
Add field `StreamSubscription? _ttsCompleteSub` to `_ConsultantScreenState`. Assign the subscription on `listen()`. Cancel in `dispose()`:

```dart
@override
void dispose() {
  _ttsCompleteSub?.cancel();
  super.dispose();
}
```

---

## 4. Memory — IoTManagerProvider Scoping

### Problem
`IoTManagerProvider` (manages MQTT/IoT connections) is mounted unconditionally at the app root in `main.dart`, consuming RAM for all users regardless of whether they use Smart Home features.

### Solution
Remove `IoTManagerProvider` from the root `MultiProvider`. Wrap the `/smart-home` route inside `onGenerateRoute` with a locally scoped `ChangeNotifierProvider<IoTManagerProvider>`:

```dart
case AppRoutes.smartHome:
  return MaterialPageRoute(
    builder: (_) => ChangeNotifierProvider(
      create: (_) => IoTManagerProvider(),
      child: const SmartHomeDashboardScreen(),
    ),
  );
```

The provider mounts on route entry and is garbage collected on route pop.

---

## 5. Auth — Forgot Password Flow

### Problem
`LoginScreen` line 339: `onTap: () {}` — the "Forgot Password?" link does nothing.

### Solution
Replace with `onTap: () => _showForgotPasswordSheet(context)`.

`_showForgotPasswordSheet` opens a `showModalBottomSheet` styled with the existing `GlassDialog` / glassmorphism pattern. It contains:
- A single `AppInput` for the email address (pre-filled if the email field on `LoginScreen` is already populated)
- A "Send Reset Link" `AppButton`
- An inline error text widget (hidden unless an error occurs)

`AuthService` gains:
```dart
Future<void> resetPasswordForEmail(String email) async {
  await Supabase.instance.client.auth.resetPasswordForEmail(
    email,
    redirectTo: 'io.supabase.bubbles://reset-password',
  );
}
```

**On success:** Sheet closes, SnackBar: *"Password reset link sent — check your inbox."*

**Error cases:**
- Rate limited (429): inline message — *"Reset email already sent. Please wait a few minutes."*
- Unknown email: Supabase returns success regardless (prevents user enumeration) — show confirmation as normal.
- Network error: inline message — *"Could not send reset email. Check your connection."*

---

## 6. Settings — Full Feature Implementation

All four stubbed settings items become routed sub-screens. `SettingsScreen` taps become `Navigator.pushNamed` calls. New routes added to `AppRoutes` and `main.dart`'s `onGenerateRoute`.

### 6a. LanguageScreen (`/settings/language`)

**New file:** `lib/screens/language_screen.dart`

**Packages added to `pubspec.yaml`:** `flutter_localizations` (SDK bundle — `sdk: flutter`). `intl` is already present at `^0.19.0` — no change needed.

**Supported locales (v1):** English (`en`), Urdu (`ur`), Arabic (`ar`)

`SettingsProvider` gains:
```dart
Locale _locale = const Locale('en');
Locale get locale => _locale;

Future<void> setLocale(Locale locale) async {
  _locale = locale;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('locale', locale.languageCode);
  notifyListeners();
}
```

On app start, `SettingsProvider` loads the saved locale from `SharedPreferences`.

`MaterialApp` in `main.dart` updated:
```dart
locale: settingsProvider.locale,
supportedLocales: const [Locale('en'), Locale('ur'), Locale('ar')],
localizationsDelegates: const [
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
],
```

UI: Tile list matching the existing theme-picker style from `LoginScreen`. RTL handled automatically by Flutter's locale system.

### 6b. PermissionsScreen (`/settings/permissions`)

**New file:** `lib/screens/permissions_screen.dart`

Uses existing `permission_handler` package. Permissions shown:
- Microphone (`Permission.microphone`)
- Camera (`Permission.camera`)
- Notifications (`Permission.notification`)
- Storage (`Permission.storage`)

Each row displays: permission name, icon, current status chip (`Granted` / `Denied` / `Permanently Denied`), and an action button:
- `Granted` → no button (or a "Revoke" button that opens system settings via `openAppSettings()`)
- `Denied` → "Request" button calls `permission.request()`
- `Permanently Denied` → "Open Settings" button calls `openAppSettings()`

`PermissionsUtil` (`lib/utils/permissions_util.dart`) is extended with `checkPermission(Permission p)` and `requestPermission(Permission p)` helpers used by this screen.

### 6c. DataManagementScreen (`/settings/data`)

**New file:** `lib/screens/data_management_screen.dart`

**Package added:** `share_plus`

Two actions:

**Export My Data:**
1. Fetches sessions, entities, and insights from Supabase for the current user
2. Serializes to JSON
3. Writes to device Documents directory via `path_provider` (`getApplicationDocumentsDirectory()`)
4. Opens system share sheet via `share_plus` (`Share.shareXFiles(...)`)
5. On failure (disk full, permission denied): inline error with retry button

**Delete Account:**
1. Shows a confirmation dialog requiring the user to type "DELETE"
2. On confirm: calls `AuthService.deleteAccount()` which calls `Supabase.instance.client.rpc('delete_user')`. **Note:** This RPC function must exist in the Supabase project. If not yet created, it needs a SQL migration: `CREATE OR REPLACE FUNCTION delete_user() RETURNS void AS $$ BEGIN DELETE FROM auth.users WHERE id = auth.uid(); END; $$ LANGUAGE plpgsql SECURITY DEFINER;`
3. On success: calls `AuthService.signOut()` → navigate to `/login`
4. On RPC failure: shows error, user remains logged in, account is NOT deleted

### 6d. SubscriptionScreen (existing, now wired)

`lib/screens/subscription_screen.dart` already exists. The Settings row tap is changed from `_showComingSoon(context, 'Subscription')` to `Navigator.pushNamed(context, AppRoutes.subscription)`.

---

## 7. Complete File Change List

### New files
| File | Purpose |
|------|---------|
| `lib/services/app_cache_service.dart` | Shared in-memory cache replacing static fields |
| `lib/screens/language_screen.dart` | Language selection sub-screen |
| `lib/screens/permissions_screen.dart` | Permissions status and request sub-screen |
| `lib/screens/data_management_screen.dart` | Export and delete account sub-screen |
| `server/routers/stt.py` | FastAPI WebSocket proxy to Deepgram |

### Modified files
| File | Change |
|------|--------|
| `lib/main.dart` | Add `AppCacheService` to provider tree; scope `IoTManagerProvider` to `/smart-home`; add 3 new routes; wire `locale` + `supportedLocales` to `SettingsProvider` |
| `lib/services/auth_service.dart` | Add `resetPasswordForEmail()` and `deleteAccount()` |
| `lib/services/deepgram_service.dart` | Connect to `SERVER_URL/stt/stream` instead of Deepgram directly |
| `lib/screens/login_screen.dart` | Replace empty `onTap` with `_showForgotPasswordSheet()` |
| `lib/screens/settings_screen.dart` | Replace 4 `_showComingSoon` calls with `Navigator.pushNamed` |
| `lib/screens/consultant_screen.dart` | Store `_ttsCompleteSub`, cancel in `dispose()` |
| `lib/screens/entity_screen.dart` | Replace static fields with `AppCacheService` reads/writes |
| `lib/screens/insights_screen.dart` | Replace static fields with `AppCacheService` reads/writes |
| `lib/providers/settings_provider.dart` | Add `locale` field with `SharedPreferences` persistence |
| `lib/utils/permissions_util.dart` | Add `checkPermission()` and `requestPermission()` helpers |
| `lib/routes/app_routes.dart` | Add `language`, `permissions`, `data` route constants |
| `pubspec.yaml` | Add `flutter_localizations` (SDK bundle), `share_plus` (`intl` already present) |
| `env/.env` (Flutter) | Remove `DEEPGRAM_API_KEY` |
| `server/.env` / backend config | Ensure `DEEPGRAM_API_KEY` is present server-side |

---

## 8. Out of Scope for Phase 1

The following items from the audit are explicitly deferred to later phases:
- Repository pattern / bypassed ApiService layers (Phase 2)
- GoRouter migration (Phase 2)
- Selector / Consumer refactoring for render performance (Phase 2)
- Glassmorphism reduction, Rive animations, masonry grids (Phase 3)
- FCM push notifications, VAD, Notion/PDF export (Phase 4)
- Offline Gemma / LiteRT-LM (Phase 4)
