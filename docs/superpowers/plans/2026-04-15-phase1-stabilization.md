# Phase 1 — Stabilization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix all critical stability issues in Bubbles AI: static memory leaks, an orphaned stream, over-scoped providers, a dead-end Forgot Password flow, four stubbed Settings features, and a client-side Deepgram API key leak.

**Architecture:** `AppCacheService` (a root-level `ChangeNotifier`) replaces four static fields across `EntityScreen` and `InsightsScreen`. Settings stubs become four real routed sub-screens. The Deepgram STT WebSocket and TTS HTTP calls are proxied through the FastAPI backend, removing the key from the Flutter client.

**Tech Stack:** Flutter/Dart (Provider, SharedPreferences, permission_handler, share_plus, flutter_localizations), FastAPI/Python (asyncio WebSocket proxy, httpx), Supabase JWT validation.

**Spec:** `docs/superpowers/specs/2026-04-15-phase1-stabilization-design.md`

---

## File Map

### New Flutter files
| File | Responsibility |
|------|---------------|
| `lib/services/app_cache_service.dart` | Shared in-memory cache replacing static fields |
| `lib/screens/language_screen.dart` | Language selection UI |
| `lib/screens/permissions_screen.dart` | Permission status and request UI |
| `lib/screens/data_management_screen.dart` | Export data + delete account UI |
| `test/services/app_cache_service_test.dart` | Unit tests for cache service |

### New backend files
| File | Responsibility |
|------|---------------|
| `server_v2/app/routes/stt.py` | Bidirectional WebSocket proxy to Deepgram STT + TTS HTTP proxy |

### Modified Flutter files
| File | What changes |
|------|-------------|
| `lib/screens/consultant_screen.dart` | Store `_ttsCompleteSub`; route TTS to backend |
| `lib/main.dart` | Add `AppCacheService` to providers; scope `IoTManagerProvider`; add 3 routes; wire locale |
| `lib/services/auth_service.dart` | Add `resetPasswordForEmail()` and `deleteAccount()` |
| `lib/services/deepgram_service.dart` | Connect to backend proxy instead of Deepgram directly |
| `lib/providers/session_provider.dart` | Pass `serverUrl` + `jwt` through to `deepgram.connect()` |
| `lib/screens/new_session_screen.dart` | Supply `serverUrl` + `jwt` to `startSession()` |
| `lib/screens/login_screen.dart` | Replace empty `onTap` with forgot-password sheet |
| `lib/screens/settings_screen.dart` | Replace 4 `_showComingSoon` calls with `Navigator.pushNamed` |
| `lib/screens/entity_screen.dart` | Remove static fields; use `AppCacheService` |
| `lib/screens/insights_screen.dart` | Remove static fields; use `AppCacheService` |
| `lib/providers/settings_provider.dart` | Add `locale` field with SharedPreferences persistence |
| `lib/utils/permissions_util.dart` | Add `checkPermission()` + `requestPermission()` helpers |
| `lib/routes/app_routes.dart` | Add `language`, `permissions`, `data` constants |
| `pubspec.yaml` | Add `flutter_localizations` (SDK), `share_plus` |
| `env/.env` | Remove `DEEPGRAM_API_KEY` |

### Modified backend files
| File | What changes |
|------|-------------|
| `server_v2/app/main.py` | Register `stt.router` under `/v1` |

---

## Task 1: Fix Orphaned Stream in ConsultantScreen

**Files:**
- Modify: `lib/screens/consultant_screen.dart`

- [ ] **Step 1: Locate the `_initVoice` method and existing field declarations**

Search for the `_ttsPlayer` field declaration near the top of `_ConsultantScreenState`. Confirm `_ttsPlayer.onPlayerComplete.listen` has no assigned variable (around line 309).

- [ ] **Step 2: Add the subscription field**

In `_ConsultantScreenState`, find the block of field declarations (alongside `_ttsPlayer` etc.) and add:

```dart
StreamSubscription? _ttsCompleteSub;
```

- [ ] **Step 3: Store the subscription in `_initVoice`**

Replace the bare `listen` call:

```dart
// BEFORE
_ttsPlayer.onPlayerComplete.listen((_) {
  if (_voiceModeActive && mounted) {
    _setVoiceMode(CVoiceMode.listening);
    _startSTT();
  }
});

// AFTER
_ttsCompleteSub = _ttsPlayer.onPlayerComplete.listen((_) {
  if (_voiceModeActive && mounted) {
    _setVoiceMode(CVoiceMode.listening);
    _startSTT();
  }
});
```

- [ ] **Step 4: Cancel in `dispose`**

Find the existing `dispose()` method and add the cancel call before `super.dispose()`:

```dart
@override
void dispose() {
  _ttsCompleteSub?.cancel();
  // ... any existing dispose calls ...
  super.dispose();
}
```

- [ ] **Step 5: Verify the app still compiles**

```bash
cd "e:/FYP/FYP_V2/Bubbles-AI"
flutter analyze lib/screens/consultant_screen.dart
```

Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add lib/screens/consultant_screen.dart
git commit -m "fix: cancel orphaned _ttsPlayer stream subscription in ConsultantScreen dispose"
```

---

## Task 2: Create AppCacheService

**Files:**
- Create: `lib/services/app_cache_service.dart`
- Create: `test/services/app_cache_service_test.dart`

- [ ] **Step 1: Create the service file**

Create `lib/services/app_cache_service.dart`:

```dart
import 'package:flutter/foundation.dart';

/// Shared in-memory cache replacing static fields on EntityScreen and
/// InsightsScreen. Registered at root so any screen can invalidate on
/// sign-out without needing a BuildContext.
class AppCacheService extends ChangeNotifier {
  List<Map<String, dynamic>>? _entities;
  List<Map<String, dynamic>>? _events;
  List<Map<String, dynamic>>? _highlights;
  List<Map<String, dynamic>>? _notifications;
  String? _cacheUserId;

  List<Map<String, dynamic>>? get entities => _entities;
  List<Map<String, dynamic>>? get events => _events;
  List<Map<String, dynamic>>? get highlights => _highlights;
  List<Map<String, dynamic>>? get notifications => _notifications;
  String? get cacheUserId => _cacheUserId;

  void setEntities(List<Map<String, dynamic>> data, String userId) {
    _entities = List.from(data);
    _cacheUserId = userId;
    notifyListeners();
  }

  void setInsights({
    required List<Map<String, dynamic>> events,
    required List<Map<String, dynamic>> highlights,
    required List<Map<String, dynamic>> notifications,
    required String userId,
  }) {
    _events = List.from(events);
    _highlights = List.from(highlights);
    _notifications = List.from(notifications);
    _cacheUserId = userId;
    notifyListeners();
  }

  void updateEvents(List<Map<String, dynamic>> data) {
    _events = List.from(data);
    notifyListeners();
  }

  void updateHighlights(List<Map<String, dynamic>> data) {
    _highlights = List.from(data);
    notifyListeners();
  }

  void updateNotifications(List<Map<String, dynamic>> data) {
    _notifications = List.from(data);
    notifyListeners();
  }

  void invalidateEntities() {
    _entities = null;
    notifyListeners();
  }

  void invalidateInsights() {
    _events = null;
    _highlights = null;
    _notifications = null;
    notifyListeners();
  }

  void invalidateAll() {
    _entities = null;
    _events = null;
    _highlights = null;
    _notifications = null;
    _cacheUserId = null;
    notifyListeners();
  }
}
```

- [ ] **Step 2: Create the test directory and test file**

```bash
mkdir -p "e:/FYP/FYP_V2/Bubbles-AI/test/services"
```

Create `test/services/app_cache_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:bubbles_ai/services/app_cache_service.dart';

void main() {
  group('AppCacheService', () {
    late AppCacheService sut;

    setUp(() {
      sut = AppCacheService();
    });

    test('starts with all nulls', () {
      expect(sut.entities, isNull);
      expect(sut.events, isNull);
      expect(sut.highlights, isNull);
      expect(sut.notifications, isNull);
      expect(sut.cacheUserId, isNull);
    });

    test('setEntities stores data and userId', () {
      final data = [{'id': '1', 'name': 'Alice'}];
      sut.setEntities(data, 'user-123');
      expect(sut.entities, equals(data));
      expect(sut.cacheUserId, equals('user-123'));
    });

    test('setEntities makes a copy — original list mutation does not affect cache', () {
      final data = [{'id': '1'}];
      sut.setEntities(data, 'user-123');
      data.add({'id': '2'});
      expect(sut.entities!.length, equals(1));
    });

    test('setInsights stores all three lists', () {
      sut.setInsights(
        events: [{'id': 'e1'}],
        highlights: [{'id': 'h1'}],
        notifications: [{'id': 'n1'}],
        userId: 'user-abc',
      );
      expect(sut.events!.length, equals(1));
      expect(sut.highlights!.length, equals(1));
      expect(sut.notifications!.length, equals(1));
      expect(sut.cacheUserId, equals('user-abc'));
    });

    test('invalidateEntities nulls only entities', () {
      sut.setEntities([{'id': '1'}], 'u1');
      sut.setInsights(events: [{'id': 'e'}], highlights: [], notifications: [], userId: 'u1');
      sut.invalidateEntities();
      expect(sut.entities, isNull);
      expect(sut.events, isNotNull); // insights untouched
    });

    test('invalidateInsights nulls only insight lists', () {
      sut.setEntities([{'id': '1'}], 'u1');
      sut.setInsights(events: [{'id': 'e'}], highlights: [], notifications: [], userId: 'u1');
      sut.invalidateInsights();
      expect(sut.events, isNull);
      expect(sut.highlights, isNull);
      expect(sut.notifications, isNull);
      expect(sut.entities, isNotNull); // entities untouched
    });

    test('invalidateAll nulls everything including cacheUserId', () {
      sut.setEntities([{'id': '1'}], 'u1');
      sut.setInsights(events: [{'id': 'e'}], highlights: [], notifications: [], userId: 'u1');
      sut.invalidateAll();
      expect(sut.entities, isNull);
      expect(sut.events, isNull);
      expect(sut.highlights, isNull);
      expect(sut.notifications, isNull);
      expect(sut.cacheUserId, isNull);
    });

    test('notifyListeners fires on invalidateAll', () {
      var notified = false;
      sut.addListener(() => notified = true);
      sut.invalidateAll();
      expect(notified, isTrue);
    });
  });
}
```

- [ ] **Step 3: Run the tests — confirm they pass**

```bash
cd "e:/FYP/FYP_V2/Bubbles-AI"
flutter test test/services/app_cache_service_test.dart --reporter=compact
```

Expected output: `All tests passed!`

- [ ] **Step 4: Commit**

```bash
git add lib/services/app_cache_service.dart test/services/app_cache_service_test.dart
git commit -m "feat: add AppCacheService replacing static screen-level cache fields"
```

---

## Task 3: Register AppCacheService + Scope IoTManagerProvider in main.dart

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 1: Add the import**

At the top of `lib/main.dart`, alongside the other service imports, add:

```dart
import 'services/app_cache_service.dart';
```

- [ ] **Step 2: Add AppCacheService to the root MultiProvider**

In `main.dart`, find the root `MultiProvider`. Add `AppCacheService` as the first provider in the list (before `ConnectionService`):

```dart
ChangeNotifierProvider(create: (_) => AppCacheService()),
// 1. Connection / Network
ChangeNotifierProvider(create: (context) => ConnectionService()),
// ... rest unchanged
```

- [ ] **Step 3: Remove IoTManagerProvider from root MultiProvider**

Find and delete this line from the root `MultiProvider`:

```dart
// 15. IoT Provider
ChangeNotifierProvider(create: (_) => IoTManagerProvider()),
```

- [ ] **Step 4: Scope IoTManagerProvider to the smartHome route**

In `main.dart`'s `routes` map, find:

```dart
AppRoutes.smartHome: (context) =>
    const AuthGuard(child: SmartHomeDashboardScreen()),
```

Replace with:

```dart
AppRoutes.smartHome: (context) => AuthGuard(
  child: ChangeNotifierProvider(
    create: (_) => IoTManagerProvider(),
    child: const SmartHomeDashboardScreen(),
  ),
),
```

- [ ] **Step 5: Verify the app compiles**

```bash
flutter analyze lib/main.dart
```

Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add lib/main.dart
git commit -m "refactor: add AppCacheService to root providers; scope IoTManagerProvider to /smart-home route"
```

---

## Task 4: Update EntityScreen to Use AppCacheService

**Files:**
- Modify: `lib/screens/entity_screen.dart`

- [ ] **Step 1: Add the import**

Add to the imports in `entity_screen.dart`:

```dart
import '../services/app_cache_service.dart';
```

- [ ] **Step 2: Remove the static fields**

Find and delete these two lines (around line 30):

```dart
static List<Map<String, dynamic>>? _cachedEntities;
static String? _cacheUserId;
```

- [ ] **Step 3: Update `initState` to read from AppCacheService**

Replace:

```dart
@override
void initState() {
  super.initState();
  final uid = AuthService.instance.currentUser?.id;
  if (_cachedEntities != null && _cacheUserId == uid) {
    _entities = List.from(_cachedEntities!);
    _loading = false;
  } else {
    _loadEntities();
  }
}
```

With:

```dart
@override
void initState() {
  super.initState();
  final uid = AuthService.instance.currentUser?.id;
  final cache = context.read<AppCacheService>();
  if (cache.entities != null && cache.cacheUserId == uid) {
    _entities = List.from(cache.entities!);
    _loading = false;
  } else {
    _loadEntities();
  }
}
```

- [ ] **Step 4: Update `_loadEntities` cache write**

In `_loadEntities()`, find the line that sets the static cache (search for `_cachedEntities =`). Replace it with a call to the service. The exact context: after building the `enriched` list and before `setState`, replace:

```dart
_cachedEntities = enriched;
_cacheUserId = user.id;
```

With:

```dart
context.read<AppCacheService>().setEntities(enriched, user.id);
```

- [ ] **Step 5: Add pull-to-refresh invalidation**

If `_loadEntities` is called on manual refresh, add at the start:

```dart
context.read<AppCacheService>().invalidateEntities();
```

This ensures pull-to-refresh bypasses the cache.

- [ ] **Step 6: Analyze**

```bash
flutter analyze lib/screens/entity_screen.dart
```

Expected: no errors.

- [ ] **Step 7: Commit**

```bash
git add lib/screens/entity_screen.dart
git commit -m "refactor: replace static EntityScreen cache with AppCacheService"
```

---

## Task 5: Update InsightsScreen + Invalidate Cache on Sign-Out

**Files:**
- Modify: `lib/screens/insights_screen.dart`
- Modify: `lib/screens/settings_screen.dart`

- [ ] **Step 1: Add import to insights_screen.dart**

```dart
import 'package:provider/provider.dart';
import '../services/app_cache_service.dart';
```

- [ ] **Step 2: Remove the four static fields**

Find and delete (around lines 23–26):

```dart
static List<Map<String, dynamic>>? _cachedEvents;
static List<Map<String, dynamic>>? _cachedHighlights;
static List<Map<String, dynamic>>? _cachedNotifications;
static String? _cacheUserId;
```

- [ ] **Step 3: Update `initState` cache check**

Replace:

```dart
final uid = AuthService.instance.currentUser?.id;
if (_cachedEvents != null && _cacheUserId == uid) {
  _events        = List.from(_cachedEvents!);
  _highlights    = List.from(_cachedHighlights!);
  _notifications = List.from(_cachedNotifications!);
  _loading = false;
} else {
  _load();
}
```

With:

```dart
final uid = AuthService.instance.currentUser?.id;
final cache = context.read<AppCacheService>();
if (cache.events != null && cache.cacheUserId == uid) {
  _events        = List.from(cache.events!);
  _highlights    = List.from(cache.highlights!);
  _notifications = List.from(cache.notifications!);
  _loading = false;
} else {
  _load();
}
```

- [ ] **Step 4: Update `_load()` cache write**

Find the section in `_load()` that writes to `_cachedEvents`, `_cachedHighlights`, `_cachedNotifications` (the primary one after fetching from Supabase). Replace all three assignments:

```dart
// BEFORE
_cachedEvents        = List.from(_events);
_cachedHighlights    = List.from(_highlights);
_cachedNotifications = List.from(_notifications);
_cacheUserId         = user.id;

// AFTER
context.read<AppCacheService>().setInsights(
  events: _events,
  highlights: _highlights,
  notifications: _notifications,
  userId: user.id,
);
```

- [ ] **Step 5: Update `_deleteItem()` cache sync**

Find every place in `_deleteItem()` that reassigns `_cachedEvents`, `_cachedHighlights`, or `_cachedNotifications` after the setState. Replace those lines with:

```dart
context.read<AppCacheService>().setInsights(
  events: _events,
  highlights: _highlights,
  notifications: _notifications,
  userId: AuthService.instance.currentUser!.id,
);
```

Repeat for any other inline cache mutations (search the file for `_cachedEvents =` to find them all).

- [ ] **Step 6: Add pull-to-refresh invalidation**

At the top of `_load()`, before setting `_loading = true`, add:

```dart
context.read<AppCacheService>().invalidateInsights();
```

- [ ] **Step 7: Invalidate cache on sign-out**

In `lib/screens/settings_screen.dart`, find the `_logout()` method. Add the invalidation **before** `AuthService.instance.signOut()`:

```dart
Future<void> _logout() async {
  setState(() => _isLoggingOut = true);
  try {
    context.read<AppCacheService>().invalidateAll(); // ← add this line
    await AuthService.instance.signOut();
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/login', (Route<dynamic> route) => false);
    }
  } catch (e) {
    // ... existing error handling
  } finally {
    if (mounted) setState(() => _isLoggingOut = false);
  }
}
```

Add the import to `settings_screen.dart`:

```dart
import '../services/app_cache_service.dart';
```

- [ ] **Step 8: Analyze both files**

```bash
flutter analyze lib/screens/insights_screen.dart lib/screens/settings_screen.dart
```

Expected: no errors.

- [ ] **Step 9: Commit**

```bash
git add lib/screens/insights_screen.dart lib/screens/settings_screen.dart
git commit -m "refactor: replace static InsightsScreen caches with AppCacheService; invalidate on sign-out"
```

---

## Task 6: Add resetPasswordForEmail + deleteAccount to AuthService

**Files:**
- Modify: `lib/services/auth_service.dart`

- [ ] **Step 1: Add `resetPasswordForEmail` method**

In `auth_service.dart`, after `signInWithEmail`, add:

```dart
/// Sends a password reset email via Supabase.
/// Always returns success (Supabase does not reveal whether the email exists).
Future<void> resetPasswordForEmail(String email) async {
  try {
    await _client.auth.resetPasswordForEmail(
      email,
      redirectTo: 'io.supabase.bubbles://reset-password',
    );
  } catch (e) {
    throw _handleAuthError(e);
  }
}
```

- [ ] **Step 2: Add `deleteAccount` method**

After `signOut`, add:

```dart
/// Deletes the current user's account by calling the Supabase `delete_user` RPC.
/// The caller is responsible for signing out on success.
/// Throws on RPC failure — the account is NOT deleted if this throws.
///
/// PREREQUISITE: The `delete_user` SQL function must exist in Supabase:
/// CREATE OR REPLACE FUNCTION delete_user() RETURNS void AS $$
///   BEGIN DELETE FROM auth.users WHERE id = auth.uid(); END;
/// $$ LANGUAGE plpgsql SECURITY DEFINER;
Future<void> deleteAccount() async {
  try {
    await _client.rpc('delete_user');
  } catch (e) {
    throw _handleAuthError(e);
  }
}
```

- [ ] **Step 3: Analyze**

```bash
flutter analyze lib/services/auth_service.dart
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/services/auth_service.dart
git commit -m "feat: add resetPasswordForEmail and deleteAccount to AuthService"
```

---

## Task 7: Implement Forgot Password Bottom Sheet in LoginScreen

**Files:**
- Modify: `lib/screens/login_screen.dart`

- [ ] **Step 1: Add the `_showForgotPasswordSheet` method**

In `_LoginScreenState`, add this method (alongside `_loginWithEmail`):

```dart
void _showForgotPasswordSheet(BuildContext context) {
  final emailCtrl = TextEditingController(text: _emailCtrl.text.trim());
  final isDark = Theme.of(context).brightness == Brightness.dark;
  String? _inlineError;
  bool _sending = false;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: GlassDialog(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Reset Password',
                style: GoogleFonts.manrope(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : AppColors.slate900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter your email and we\'ll send a reset link.',
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  color: AppColors.slate400,
                ),
              ),
              const SizedBox(height: 20),
              AppInput(
                controller: emailCtrl,
                label: 'Email',
                prefixIcon: Icons.email_outlined,
                type: TextInputType.emailAddress,
                hintText: 'your@email.com',
              ),
              if (_inlineError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _inlineError!,
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    color: AppColors.error,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              AppButton(
                label: 'Send Reset Link',
                icon: Icons.send_rounded,
                filled: true,
                loading: _sending,
                onTap: () async {
                  final email = emailCtrl.text.trim();
                  if (email.isEmpty || !email.contains('@')) {
                    setSheetState(() => _inlineError = 'Enter a valid email address.');
                    return;
                  }
                  setSheetState(() { _sending = true; _inlineError = null; });
                  try {
                    await _authService.resetPasswordForEmail(email);
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Password reset link sent — check your inbox.'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  } catch (e) {
                    final msg = e.toString().toLowerCase();
                    setSheetState(() {
                      _sending = false;
                      if (msg.contains('rate') || msg.contains('too many')) {
                        _inlineError = 'Reset email already sent. Please wait a few minutes.';
                      } else {
                        _inlineError = 'Could not send reset email. Check your connection.';
                      }
                    });
                  }
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
```

- [ ] **Step 2: Wire the tap**

Find line 339 in `login_screen.dart`:

```dart
onTap: () {},
```

Replace with:

```dart
onTap: () => _showForgotPasswordSheet(context),
```

- [ ] **Step 3: Analyze**

```bash
flutter analyze lib/screens/login_screen.dart
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/screens/login_screen.dart
git commit -m "feat: implement Forgot Password bottom sheet with inline error handling"
```

---

## Task 8: Add Locale Support to SettingsProvider + Update pubspec.yaml

**Files:**
- Modify: `lib/providers/settings_provider.dart`
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add the locale field to SettingsProvider**

In `settings_provider.dart`, add to the field declarations:

```dart
static const String _localeKey = 'app_locale';
Locale _locale = const Locale('en');
Locale get locale => _locale;
```

- [ ] **Step 2: Load locale in `_loadSettings`**

Inside `_loadSettings()`, after loading other prefs, add:

```dart
final localeCode = prefs.getString(_localeKey) ?? 'en';
_locale = Locale(localeCode);
```

(This goes before `notifyListeners()`.)

- [ ] **Step 3: Add the `setLocale` method**

Alongside the other setters, add:

```dart
Future<void> setLocale(Locale locale) async {
  _locale = locale;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_localeKey, locale.languageCode);
  notifyListeners();
  _logSettingsChange('app_locale', locale.languageCode);
}
```

- [ ] **Step 4: Update pubspec.yaml**

Open `pubspec.yaml`. In the `flutter:` section (alongside `uses-material-design`), add:

```yaml
flutter:
  uses-material-design: true
  generate: true   # needed for flutter_localizations

dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter
```

Also add `share_plus` to `dependencies`:

```yaml
  share_plus: ^10.1.4
```

- [ ] **Step 5: Run pub get**

```bash
cd "e:/FYP/FYP_V2/Bubbles-AI"
flutter pub get
```

Expected: resolves without errors.

- [ ] **Step 6: Analyze**

```bash
flutter analyze lib/providers/settings_provider.dart
```

Expected: no errors.

- [ ] **Step 7: Commit**

```bash
git add lib/providers/settings_provider.dart pubspec.yaml pubspec.lock
git commit -m "feat: add locale field to SettingsProvider; add flutter_localizations and share_plus deps"
```

---

## Task 9: Add New Route Constants

**Files:**
- Modify: `lib/routes/app_routes.dart`

- [ ] **Step 1: Add the three new route constants**

Open `lib/routes/app_routes.dart`. Add after the `insights` constant:

```dart
static const language    = '/settings/language';
static const permissions = '/settings/permissions';
static const data        = '/settings/data';
```

- [ ] **Step 2: Commit**

```bash
git add lib/routes/app_routes.dart
git commit -m "feat: add language, permissions, data route constants to AppRoutes"
```

---

## Task 10: Create LanguageScreen

**Files:**
- Create: `lib/screens/language_screen.dart`

- [ ] **Step 1: Create the screen**

Create `lib/screens/language_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../theme/design_tokens.dart';
import '../widgets/glass_morphism.dart';

class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key});

  static const _locales = [
    (Locale('en'), 'English',  '🇬🇧'),
    (Locale('ur'), 'اردو',     '🇵🇰'),
    (Locale('ar'), 'العربية',  '🇸🇦'),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = context.watch<SettingsProvider>();

    return GestureDetector(
      onHorizontalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) > 300) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor:
            isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: isDark ? Colors.white : AppColors.slate900,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'Language',
                      style: GoogleFonts.manrope(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : AppColors.slate900,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Select your preferred language.',
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    color: AppColors.slate400,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Locale tiles
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _locales.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final (locale, label, flag) = _locales[i];
                    final isSelected =
                        settings.locale.languageCode == locale.languageCode;
                    return GestureDetector(
                      onTap: () => settings.setLocale(locale),
                      child: GlassCard(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          child: Row(
                            children: [
                              Text(flag, style: const TextStyle(fontSize: 24)),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  label,
                                  style: GoogleFonts.manrope(
                                    fontSize: 16,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: isSelected
                                        ? Theme.of(context)
                                            .colorScheme
                                            .primary
                                        : (isDark
                                            ? Colors.white
                                            : AppColors.slate900),
                                  ),
                                ),
                              ),
                              if (isSelected)
                                Icon(
                                  Icons.check_circle_rounded,
                                  color:
                                      Theme.of(context).colorScheme.primary,
                                  size: 20,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Analyze**

```bash
flutter analyze lib/screens/language_screen.dart
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/screens/language_screen.dart
git commit -m "feat: add LanguageScreen with en/ur/ar locale selection"
```

---

## Task 11: Extend PermissionsUtil + Create PermissionsScreen

**Files:**
- Modify: `lib/utils/permissions_util.dart`
- Create: `lib/screens/permissions_screen.dart`

- [ ] **Step 1: Extend PermissionsUtil**

Open `lib/utils/permissions_util.dart`. Add these two helpers at the end of the class (before the closing `}`):

```dart
/// Returns the current status for a single permission.
static Future<PermissionStatus> checkPermission(Permission permission) =>
    permission.status;

/// Requests a single permission. Returns the resulting status.
static Future<PermissionStatus> requestPermission(Permission permission) =>
    permission.request();
```

Make sure `permission_handler` is imported at the top (it likely already is — confirm `import 'package:permission_handler/permission_handler.dart';` exists).

- [ ] **Step 2: Create PermissionsScreen**

Create `lib/screens/permissions_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

import '../theme/design_tokens.dart';
import '../utils/permissions_util.dart';
import '../widgets/glass_morphism.dart';

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  static const _permissionDefs = [
    (Permission.microphone,    'Microphone',    Icons.mic_rounded,          'Required for live sessions and voice commands.'),
    (Permission.camera,        'Camera',         Icons.camera_alt_rounded,   'Used for profile photos.'),
    (Permission.notification,  'Notifications', Icons.notifications_rounded, 'Allows Bubbles to send reminders and digests.'),
    (Permission.storage,       'Storage',        Icons.folder_rounded,       'Needed to save and export session recordings.'),
  ];

  Map<Permission, PermissionStatus> _statuses = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStatuses();
  }

  Future<void> _loadStatuses() async {
    final results = <Permission, PermissionStatus>{};
    for (final (perm, _, __, ___) in _permissionDefs) {
      results[perm] = await PermissionsUtil.checkPermission(perm);
    }
    if (mounted) setState(() { _statuses = results; _loading = false; });
  }

  Future<void> _handleTap(Permission perm, PermissionStatus status) async {
    if (status.isPermanentlyDenied) {
      await openAppSettings();
    } else if (!status.isGranted) {
      final result = await PermissionsUtil.requestPermission(perm);
      if (mounted) setState(() => _statuses[perm] = result);
    }
  }

  String _statusLabel(PermissionStatus s) {
    if (s.isGranted) return 'Granted';
    if (s.isPermanentlyDenied) return 'Permanently Denied';
    return 'Denied';
  }

  Color _statusColor(PermissionStatus s, BuildContext ctx) {
    if (s.isGranted) return Colors.green;
    if (s.isPermanentlyDenied) return AppColors.error;
    return AppColors.slate400;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onHorizontalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) > 300) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor:
            isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Icon(Icons.arrow_back_ios_new_rounded,
                          color: isDark ? Colors.white : AppColors.slate900,
                          size: 20),
                    ),
                    const SizedBox(width: 16),
                    Text('Permissions',
                        style: GoogleFonts.manrope(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : AppColors.slate900)),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (_loading)
                const Expanded(child: Center(child: CircularProgressIndicator()))
              else
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: _permissionDefs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final (perm, label, icon, desc) = _permissionDefs[i];
                      final status = _statuses[perm] ?? PermissionStatus.denied;
                      final isGranted = status.isGranted;
                      return GlassCard(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withAlpha(26),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(icon,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                    size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(label,
                                        style: GoogleFonts.manrope(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 15,
                                            color: isDark
                                                ? Colors.white
                                                : AppColors.slate900)),
                                    const SizedBox(height: 2),
                                    Text(desc,
                                        style: GoogleFonts.manrope(
                                            fontSize: 12,
                                            color: AppColors.slate400)),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: _statusColor(status, context)
                                                .withAlpha(26),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            _statusLabel(status),
                                            style: GoogleFonts.manrope(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: _statusColor(
                                                  status, context),
                                            ),
                                          ),
                                        ),
                                        if (!isGranted)
                                          GestureDetector(
                                            onTap: () =>
                                                _handleTap(perm, status),
                                            child: Text(
                                              status.isPermanentlyDenied
                                                  ? 'Open Settings'
                                                  : 'Request',
                                              style: GoogleFonts.manrope(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Analyze**

```bash
flutter analyze lib/utils/permissions_util.dart lib/screens/permissions_screen.dart
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/utils/permissions_util.dart lib/screens/permissions_screen.dart
git commit -m "feat: add PermissionsScreen with live status display and request/open-settings actions"
```

---

## Task 12: Create DataManagementScreen

**Files:**
- Create: `lib/screens/data_management_screen.dart`

- [ ] **Step 1: Create the screen**

Create `lib/screens/data_management_screen.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import '../services/app_cache_service.dart';
import '../theme/design_tokens.dart';
import '../widgets/app_button.dart';
import '../widgets/glass_morphism.dart';
import 'package:provider/provider.dart';

class DataManagementScreen extends StatefulWidget {
  const DataManagementScreen({super.key});

  @override
  State<DataManagementScreen> createState() => _DataManagementScreenState();
}

class _DataManagementScreenState extends State<DataManagementScreen> {
  bool _exporting = false;
  String? _exportError;
  bool _deleting = false;
  String? _deleteError;
  final _confirmCtrl = TextEditingController();

  @override
  void dispose() {
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _exportData() async {
    setState(() { _exporting = true; _exportError = null; });
    try {
      final user = AuthService.instance.currentUser!;
      final sb = Supabase.instance.client;

      final sessions = await sb
          .from('sessions')
          .select('id, title, mode, created_at, summary')
          .eq('user_id', user.id)
          .order('created_at', ascending: false);
      final entities = await sb
          .from('entities')
          .select('id, display_name, entity_type, description, mention_count')
          .eq('user_id', user.id);
      final highlights = await sb
          .from('highlights')
          .select('id, title, body, highlight_type, created_at')
          .eq('user_id', user.id);

      final export = jsonEncode({
        'exported_at': DateTime.now().toIso8601String(),
        'user_id': user.id,
        'sessions': sessions,
        'entities': entities,
        'highlights': highlights,
      });

      final dir = await getApplicationDocumentsDirectory();
      final file = File(
          '${dir.path}/bubbles_export_${DateTime.now().millisecondsSinceEpoch}.json');
      await file.writeAsString(export);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Bubbles AI — My Data Export',
      );
    } catch (e) {
      if (mounted) setState(() => _exportError = 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _showDeleteConfirmation() async {
    _confirmCtrl.clear();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: isDark ? AppColors.backgroundDark : Colors.white,
          title: Text('Delete Account',
              style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : AppColors.slate900)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This is permanent and cannot be undone. All your data will be deleted.',
                style: GoogleFonts.manrope(fontSize: 13, color: AppColors.slate400),
              ),
              const SizedBox(height: 16),
              Text('Type DELETE to confirm:',
                  style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : AppColors.slate900)),
              const SizedBox(height: 8),
              TextField(
                controller: _confirmCtrl,
                style: GoogleFonts.manrope(color: isDark ? Colors.white : AppColors.slate900),
                decoration: InputDecoration(
                  hintText: 'DELETE',
                  hintStyle: GoogleFonts.manrope(color: AppColors.slate400),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              if (_deleteError != null) ...[
                const SizedBox(height: 8),
                Text(_deleteError!,
                    style: GoogleFonts.manrope(
                        fontSize: 12, color: AppColors.error)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel',
                  style: GoogleFonts.manrope(color: AppColors.slate400)),
            ),
            TextButton(
              onPressed: _deleting
                  ? null
                  : () async {
                      if (_confirmCtrl.text.trim() != 'DELETE') {
                        setDialogState(() =>
                            _deleteError = 'Type DELETE exactly to confirm.');
                        return;
                      }
                      setDialogState(() { _deleting = true; _deleteError = null; });
                      try {
                        await AuthService.instance.deleteAccount();
                        context.read<AppCacheService>().invalidateAll();
                        await AuthService.instance.signOut();
                        if (ctx.mounted) {
                          Navigator.of(ctx).pushNamedAndRemoveUntil(
                              '/login', (_) => false);
                        }
                      } catch (e) {
                        setDialogState(() {
                          _deleting = false;
                          _deleteError =
                              'Deletion failed. Your account was not deleted.';
                        });
                      }
                    },
              child: Text('Delete',
                  style: GoogleFonts.manrope(
                      color: AppColors.error, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onHorizontalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) > 300) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor:
            isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Icon(Icons.arrow_back_ios_new_rounded,
                          color: isDark ? Colors.white : AppColors.slate900,
                          size: 20),
                    ),
                    const SizedBox(width: 16),
                    Text('Data Management',
                        style: GoogleFonts.manrope(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : AppColors.slate900)),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    // Export card
                    GlassCard(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withAlpha(26),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(Icons.download_rounded,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                      size: 20),
                                ),
                                const SizedBox(width: 12),
                                Text('Export My Data',
                                    style: GoogleFonts.manrope(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: isDark
                                            ? Colors.white
                                            : AppColors.slate900)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Downloads your sessions, entities, and highlights as a JSON file and opens the share sheet.',
                              style: GoogleFonts.manrope(
                                  fontSize: 13, color: AppColors.slate400),
                            ),
                            if (_exportError != null) ...[
                              const SizedBox(height: 8),
                              Text(_exportError!,
                                  style: GoogleFonts.manrope(
                                      fontSize: 12, color: AppColors.error)),
                            ],
                            const SizedBox(height: 16),
                            AppButton(
                              label: 'Export Data',
                              icon: Icons.ios_share_rounded,
                              loading: _exporting,
                              onTap: _exportData,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Delete card
                    GlassCard(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: AppColors.error.withAlpha(26),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(Icons.delete_forever_rounded,
                                      color: AppColors.error, size: 20),
                                ),
                                const SizedBox(width: 12),
                                Text('Delete Account',
                                    style: GoogleFonts.manrope(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.error)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Permanently deletes your account and all associated data. This cannot be undone.',
                              style: GoogleFonts.manrope(
                                  fontSize: 13, color: AppColors.slate400),
                            ),
                            const SizedBox(height: 16),
                            AppButton(
                              label: 'Delete My Account',
                              icon: Icons.warning_amber_rounded,
                              onTap: _showDeleteConfirmation,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Analyze**

```bash
flutter analyze lib/screens/data_management_screen.dart
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/screens/data_management_screen.dart
git commit -m "feat: add DataManagementScreen with JSON export and typed-confirmation account deletion"
```

---

## Task 13: Wire Settings Navigation + Register Routes + Locale in MaterialApp

**Files:**
- Modify: `lib/screens/settings_screen.dart`
- Modify: `lib/main.dart`

- [ ] **Step 1: Wire the four Settings taps**

In `lib/screens/settings_screen.dart`, find the four `_showComingSoon` call sites:

```
Line ~200:  _showComingSoon(context, 'Subscription')
Line ~279:  onTap: () => _showComingSoon(context, 'Language')
Line ~405:  _showComingSoon(context, 'Data Management')
Line ~417:  _showComingSoon(context, 'Permissions')
```

Replace each with `Navigator.pushNamed`:

```dart
// Subscription (~line 200)
Navigator.pushNamed(context, AppRoutes.subscription)

// Language (~line 279)
onTap: () => Navigator.pushNamed(context, AppRoutes.language)

// Data Management (~line 405)
Navigator.pushNamed(context, AppRoutes.data)

// Permissions (~line 417)
Navigator.pushNamed(context, AppRoutes.permissions)
```

For the toggle `onChanged` stub at ~line 436, leave it calling `_showComingSoon` unless you can identify which feature it belongs to — check what the toggle label says.

Add the `AppRoutes` import if not present:

```dart
import '../routes/app_routes.dart';
```

- [ ] **Step 2: Register new routes in main.dart**

Open `lib/main.dart`. Add the three new screen imports at the top:

```dart
import 'screens/language_screen.dart';
import 'screens/permissions_screen.dart';
import 'screens/data_management_screen.dart';
```

In the `routes` map, add the three new entries:

```dart
AppRoutes.language: (context) =>
    const AuthGuard(child: LanguageScreen()),
AppRoutes.permissions: (context) =>
    const AuthGuard(child: PermissionsScreen()),
AppRoutes.data: (context) =>
    const AuthGuard(child: DataManagementScreen()),
```

- [ ] **Step 3: Wire locale in MaterialApp**

In `main.dart`, the `MaterialApp` is wrapped in `Consumer<ThemeProvider>`. Change it to also consume `SettingsProvider`:

```dart
// BEFORE
child: Consumer<ThemeProvider>(
  builder: (context, themeProvider, child) {
    return MaterialApp(
      themeMode: themeProvider.themeMode,
      ...

// AFTER
child: Consumer2<ThemeProvider, SettingsProvider>(
  builder: (context, themeProvider, settingsProvider, child) {
    return MaterialApp(
      themeMode: themeProvider.themeMode,
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
      ...
```

Add the localizations import at the top of `main.dart`:

```dart
import 'package:flutter_localizations/flutter_localizations.dart';
```

- [ ] **Step 4: Analyze**

```bash
flutter analyze lib/screens/settings_screen.dart lib/main.dart
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/settings_screen.dart lib/main.dart
git commit -m "feat: wire Settings sub-screens; add locale support to MaterialApp; register 3 new routes"
```

---

## Task 14: Create Backend STT + TTS Proxy

**Files:**
- Create: `server_v2/app/routes/stt.py`
- Modify: `server_v2/app/main.py`

- [ ] **Step 1: Create the stt router**

Create `server_v2/app/routes/stt.py`:

```python
"""
STT/TTS proxy routes.

GET  /stt/stream  — WebSocket proxy: Flutter ↔ this server ↔ Deepgram STT
POST /tts         — HTTP proxy: Flutter → this server → Deepgram TTS → audio bytes
"""

import asyncio

import httpx
from fastapi import APIRouter, HTTPException, WebSocket, WebSocketDisconnect
from supabase import create_client
from websockets.client import connect as ws_connect
from websockets.exceptions import ConnectionClosed

from app.config import settings

router = APIRouter()

_DEEPGRAM_STT_URL = (
    "wss://api.deepgram.com/v1/listen"
    "?smart_format=true&diarize=true&model=nova-2"
    "&encoding=linear16&sample_rate=16000&channels=1"
)
_DEEPGRAM_TTS_URL = "https://api.deepgram.com/v1/speak?model=aura-orpheus-en"


def _verify_jwt(token: str) -> str:
    """Validate Supabase JWT. Returns user_id on success, raises HTTPException on failure."""
    if not token:
        raise HTTPException(status_code=401, detail="Missing token")
    try:
        svc = create_client(settings.SUPABASE_URL, settings.SUPABASE_SERVICE_KEY)
        user = svc.auth.get_user(token)
        return user.user.id
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid token")


# ── STT WebSocket Proxy ───────────────────────────────────────────────────────

@router.websocket("/stt/stream")
async def stt_stream(websocket: WebSocket, token: str = ""):
    """
    Bidirectional WebSocket proxy between Flutter client and Deepgram STT.
    Requires ?token=<supabase_jwt> query parameter.
    Closes with code 4001 if JWT is invalid.
    """
    # Validate JWT before accepting the connection
    try:
        _verify_jwt(token)
    except HTTPException:
        await websocket.close(code=4001, reason="Unauthorized")
        return

    await websocket.accept()

    if not settings.DEEPGRAM_API_KEY:
        await websocket.close(code=4002, reason="STT not configured on server")
        return

    try:
        async with ws_connect(
            _DEEPGRAM_STT_URL,
            extra_headers={"Authorization": f"Token {settings.DEEPGRAM_API_KEY}"},
        ) as deepgram_ws:

            async def client_to_deepgram():
                """Forward audio bytes from Flutter → Deepgram."""
                try:
                    async for message in websocket.iter_bytes():
                        await deepgram_ws.send(message)
                except (WebSocketDisconnect, Exception):
                    pass
                finally:
                    await deepgram_ws.close()

            async def deepgram_to_client():
                """Forward transcript JSON from Deepgram → Flutter."""
                try:
                    async for message in deepgram_ws:
                        await websocket.send_text(message)
                except (ConnectionClosed, WebSocketDisconnect, Exception):
                    pass

            await asyncio.gather(
                client_to_deepgram(),
                deepgram_to_client(),
                return_exceptions=True,
            )

    except Exception as exc:
        try:
            await websocket.send_json({"error": "upstream_disconnected", "detail": str(exc)})
        except Exception:
            pass
    finally:
        try:
            await websocket.close()
        except Exception:
            pass


# ── TTS HTTP Proxy ────────────────────────────────────────────────────────────

@router.post("/tts")
async def tts_proxy(request_body: dict, authorization: str = ""):
    """
    Proxy Deepgram TTS: receive {"text": "..."} from Flutter,
    forward to Deepgram /v1/speak, return audio bytes.
    Requires Authorization: Bearer <supabase_jwt> header.
    """
    token = authorization.removeprefix("Bearer ").strip()
    _verify_jwt(token)

    text = request_body.get("text", "").strip()
    if not text:
        raise HTTPException(status_code=400, detail="text field is required")

    if not settings.DEEPGRAM_API_KEY:
        raise HTTPException(status_code=503, detail="TTS not configured on server")

    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.post(
            _DEEPGRAM_TTS_URL,
            headers={
                "Authorization": f"Token {settings.DEEPGRAM_API_KEY}",
                "Content-Type": "application/json",
            },
            json={"text": text},
        )

    if resp.status_code != 200:
        raise HTTPException(
            status_code=502,
            detail=f"Deepgram TTS error: {resp.status_code}",
        )

    from fastapi.responses import Response
    return Response(
        content=resp.content,
        media_type=resp.headers.get("content-type", "audio/mpeg"),
    )
```

- [ ] **Step 2: Install websockets package**

Add `websockets` to `server_v2/requirements.txt` (it's not currently listed):

```
websockets
```

Then install:

```bash
cd "e:/FYP/FYP_V2/Bubbles-AI/server_v2"
pip install websockets
```

- [ ] **Step 3: Register the router in main.py**

Open `server_v2/app/main.py`. Find:

```python
from app.routes import health, sessions, consultant, voice, analytics, entities, gamification
```

Replace with:

```python
from app.routes import health, sessions, consultant, voice, analytics, entities, gamification, stt
```

Find the `v1` router section:

```python
v1 = APIRouter(prefix="/v1")
v1.include_router(sessions.router)
v1.include_router(consultant.router)
v1.include_router(voice.router)
v1.include_router(analytics.router)
v1.include_router(entities.router)
v1.include_router(gamification.router)
```

Add:

```python
v1.include_router(stt.router)
```

- [ ] **Step 4: Verify the backend starts**

```bash
cd "e:/FYP/FYP_V2/Bubbles-AI/server_v2"
python -c "from app.main import app; print('✅ app loaded')"
```

Expected: `✅ app loaded`

- [ ] **Step 5: Commit**

```bash
git add server_v2/app/routes/stt.py server_v2/app/main.py server_v2/requirements.txt
git commit -m "feat: add Deepgram STT WebSocket proxy and TTS HTTP proxy to backend"
```

---

## Task 15: Update Flutter DeepgramService + ConsultantScreen TTS + Remove Key

**Files:**
- Modify: `lib/services/deepgram_service.dart`
- Modify: `lib/providers/session_provider.dart`
- Modify: `lib/screens/new_session_screen.dart`
- Modify: `lib/screens/consultant_screen.dart`
- Modify: `env/.env`

- [ ] **Step 1: Update `DeepgramService.connect()` signature**

In `lib/services/deepgram_service.dart`, remove the static `_apiKey` getter and `_wsUrl` constant:

```dart
// DELETE these lines:
static String get _apiKey => dotenv.env['DEEPGRAM_API_KEY'] ?? '';
static const String _wsUrl =
    "wss://api.deepgram.com/v1/listen?smart_format=true&diarize=true&model=nova-2"
    "&encoding=linear16&sample_rate=16000&channels=1";
```

Update `connect()` to accept `serverUrl` and `jwt` parameters:

```dart
Future<void> connect({
  required String serverUrl,
  required String jwt,
}) async {
  if (_isConnected) return;
  _intentionalDisconnect = false;
  _reconnectAttempts = 0;

  if (serverUrl.isEmpty || jwt.isEmpty) {
    debugPrint("❌ DeepgramService: serverUrl or jwt is empty");
    return;
  }

  // Convert http(s) base URL to ws(s)
  final wsBase = serverUrl
      .replaceFirst('https://', 'wss://')
      .replaceFirst('http://', 'ws://');
  final wsUrl = '$wsBase/v1/stt/stream'
      '?token=$jwt'
      '&smart_format=true&diarize=true&model=nova-2'
      '&encoding=linear16&sample_rate=16000&channels=1';

  try {
    if (!await _recorder.hasPermission()) {
      debugPrint("❌ DeepgramService: No microphone permission");
      return;
    }

    _channel = IOWebSocketChannel.connect(Uri.parse(wsUrl));
    // No Authorization header needed — JWT is in the query string
    await _channel!.ready;
    debugPrint("✅ DeepgramService: WebSocket Connected via backend proxy");
    _isConnected = true;
    notifyListeners();

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );

    _audioBuffer.clear();
    _isMuted = false;
    _audioStreamSubscription = stream.listen((data) {
      if (!_isMuted) {
        _channel?.sink.add(data);
        _audioBuffer.add(data);
      }
    });

    _channel!.stream.listen(
      (message) => _handleMessage(message),
      onError: (error) {
        debugPrint("❌ DeepgramService: WebSocket Error: $error");
        _attemptReconnect(serverUrl: serverUrl, jwt: jwt);
      },
      onDone: () {
        debugPrint("⚠️ DeepgramService: WebSocket Closed");
        _attemptReconnect(serverUrl: serverUrl, jwt: jwt);
      },
    );
  } catch (e) {
    debugPrint("❌ DeepgramService: Connection Failed: $e");
    disconnect();
  }
}
```

- [ ] **Step 2: Update `_attemptReconnect` to pass through serverUrl + jwt**

Find `_attemptReconnect()` and update its signature and internal call:

```dart
void _attemptReconnect({required String serverUrl, required String jwt}) {
  if (_intentionalDisconnect) return;
  if (_reconnectAttempts >= _maxReconnectAttempts) {
    debugPrint("❌ DeepgramService: Max reconnect attempts reached");
    disconnect();
    return;
  }
  _isConnected = false;
  _channel = null;
  notifyListeners();
  _reconnectAttempts++;
  final delay = Duration(seconds: _reconnectAttempts * 2);
  debugPrint("🔄 DeepgramService: Reconnecting in ${delay.inSeconds}s (attempt $_reconnectAttempts)");
  Future.delayed(delay, () {
    if (!_intentionalDisconnect) connect(serverUrl: serverUrl, jwt: jwt);
  });
}
```

Remove the `flutter_dotenv` import from `deepgram_service.dart` if it's no longer used there.

- [ ] **Step 3: Update SessionProvider.startSession to pass serverUrl + jwt**

In `lib/providers/session_provider.dart`, update the `startSession` signature:

```dart
Future<void> startSession(
  ApiService api,
  DeepgramService deepgram, {
  String tone = 'casual',
  String? targetEntityId,
  bool isEphemeral = false,
  bool isMultiplayer = false,
  required String serverUrl,
  required String jwt,
}) async {
```

Update the `deepgram.connect()` call:

```dart
await deepgram.connect(serverUrl: serverUrl, jwt: jwt);
```

- [ ] **Step 4: Update NewSessionScreen to supply serverUrl + jwt**

In `lib/screens/new_session_screen.dart`, add imports:

```dart
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/connection_service.dart';
```

Find where `_session.startSession(...)` is called (around line 255). Update the call:

```dart
final serverUrl = context.read<ConnectionService>().serverUrl;
final jwt = Supabase.instance.client.auth.currentSession?.accessToken ?? '';

await _session.startSession(
  api,
  deepgram,
  tone: selectedTone,
  targetEntityId: targetEntityId,
  isEphemeral: isEphemeral,
  isMultiplayer: isMultiplayer,
  serverUrl: serverUrl,
  jwt: jwt,
);
```

- [ ] **Step 5: Update ConsultantScreen TTS to call backend proxy**

In `lib/screens/consultant_screen.dart`, find the TTS section (around line 430) that calls `https://api.deepgram.com/v1/speak`. Replace the entire TTS call block:

```dart
// BEFORE — remove this block:
final apiKey = dotenv.env['DEEPGRAM_API_KEY'] ?? '';
if (apiKey.isEmpty) { ... return; }
...
final response = await http.post(
  Uri.parse('https://api.deepgram.com/v1/speak?model=aura-orpheus-en'),
  headers: {'Authorization': 'Token $apiKey', 'Content-Type': 'application/json'},
  body: jsonEncode({'text': plain}),
);

// AFTER — use backend proxy:
final serverUrl = context.read<ConnectionService>().serverUrl;
final jwt = Supabase.instance.client.auth.currentSession?.accessToken ?? '';
if (serverUrl.isEmpty || jwt.isEmpty) {
  if (_voiceModeActive && mounted) {
    _setVoiceMode(CVoiceMode.listening);
    _startSTT();
  }
  return;
}
_setVoiceMode(CVoiceMode.speaking);
try {
  final response = await http.post(
    Uri.parse('$serverUrl/v1/tts'),
    headers: {
      'Authorization': 'Bearer $jwt',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({'text': plain}),
  );
```

(The rest of the TTS response handling — reading bytes, playing audio — stays identical.)

Add imports to `consultant_screen.dart` if not present:

```dart
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/connection_service.dart';
```

Remove the `flutter_dotenv` import from `consultant_screen.dart` if no longer used.

- [ ] **Step 6: Remove DEEPGRAM_API_KEY from Flutter .env**

Open `env/.env`. Find and delete the line:

```
DEEPGRAM_API_KEY=...
```

- [ ] **Step 7: Analyze all modified files**

```bash
flutter analyze lib/services/deepgram_service.dart lib/providers/session_provider.dart lib/screens/new_session_screen.dart lib/screens/consultant_screen.dart
```

Expected: no errors.

- [ ] **Step 8: Final full analyze**

```bash
flutter analyze lib/
```

Expected: no errors (or only pre-existing warnings unrelated to this change).

- [ ] **Step 9: Commit**

```bash
git add lib/services/deepgram_service.dart lib/providers/session_provider.dart lib/screens/new_session_screen.dart lib/screens/consultant_screen.dart env/.env
git commit -m "security: proxy Deepgram STT and TTS through backend; remove client-side API key"
```

---

## Self-Review Checklist (for implementer)

Before marking this plan done, verify:

- [ ] `flutter analyze lib/` returns no new errors
- [ ] `flutter test test/services/app_cache_service_test.dart` — all 7 tests pass
- [ ] Backend imports `websockets` — `pip show websockets` confirms installation
- [ ] `DEEPGRAM_API_KEY` no longer appears anywhere in `lib/` (`grep -r DEEPGRAM lib/` returns empty)
- [ ] Opening `/settings` in the running app — all four rows navigate to real screens (not snackbars)
- [ ] Tapping "Forgot Password?" opens the glass bottom sheet
- [ ] Opening and closing `/smart-home` then checking memory — `IoTManagerProvider` is not active on other screens
- [ ] STT streaming works end-to-end via the backend proxy in a live session
