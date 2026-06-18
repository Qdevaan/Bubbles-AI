# Bubbles-AI — Screen & UI Inventory

> Generated for documentation purposes. Lists every screen, every distinct UI
> state/scenario, and every dialog/popup/bottom-sheet/overlay/snackbar.
> Source: `lib/screens/`, `lib/widgets/`, `lib/routes/app_routes.dart`.

## Counts at a glance

| Category | Count |
|---|---|
| Registered routes | 38 |
| Screen files | 38 |
| User-facing (visible) screens | 33 |
| Routing-only shells (no UI) | 3 (`splash`, `app_bootstrap`, `auth_gate`) |
| Performa wizard step sub-screens | 3 (steps 1–3) |
| Stub screen | 1 (`subscription`) |
| Reusable dialog/sheet/overlay components | 23 |

---

## A. Routing shells (no own UI)

1. **SplashScreen** — `/splash`. Legacy alias; renders AppBootstrap.
2. **AppBootstrap** — entry point. Frame-1 decision: unfinished Performa → wizard; onboarding unseen → onboarding; else → home.
3. **AuthGate** — `/auth-gate`. Post-login; same decision tree as AppBootstrap.

---

## B. Auth & onboarding (8 screens)

### 4. LoginScreen — `/login`
- **States:** initial · email-loading · google-loading · error
- **Popups:** Theme-selection dialog (first login only) · Forgot-password bottom sheet (email input, loading, rate-limit msg) · success/error snackbars

### 5. SignupScreen — `/signup`
- **States:** initial · password-strength bar (Weak/Fair/Good/Strong) · email-loading · google-loading · error
- **Popups:** error snackbars only

### 6. VerifyEmailScreen — `/verify-email`
- **States:** waiting · resending · checking · verified (auto-advance) · not-yet-verified
- **Popups:** snackbars (sent / error / not-verified)

### 7. UpdatePasswordScreen — `/update-password`
- **States:** initial · submitting · validation-error (min 6 chars / mismatch) · success
- **Popups:** success/error snackbars

### 8. ProfileCompletionScreen — `/profile-completion`
- **States:** initial-loading (skeleton) · empty form · image-selected · saving · validation-error · success
- **Popups:** image picker · date picker · gender bottom sheet · country bottom sheet (searchable) · snackbars

### 9. OnboardingScreen — `/onboarding`
- **States:** 6 slides (Welcome · Live Wingman · Practice scenarios · Drills · Progress · Help) · page indicators · Next/Get-started button · replay mode
- **Popups:** none

### 10. PermissionsScreen — `/settings/permissions`
- **States:** loading (skeleton) · loaded · per-permission: granted / denied / permanently-denied · notifications-expanded (4 sub-toggles)
- **Permissions:** Microphone · Camera · Notification · Storage
- **Popups:** opens native OS settings dialog

### 11. VoiceEnrollmentScreen — `/settings/voice-enrollment`
- **States:** idle · recording (7s countdown, pulsing mic) · uploading · success · error · enrolled (sample count) / not-enrolled
- **Popups:** help sheet · snackbars

---

## C. Performa wizard (1 container + 3 steps)

### 12. PerformaWizardScreen — `/performa-wizard` (also edit mode from settings)
- **States:** intro panel · step 0/1/2 · submitting · completed
- **Popups:** Skip-confirmation dialog · error snackbar
- **Step 1 — Identity:** display name · age range · primary role (7 chips, required) · profession · expertise tags (max 5)
- **Step 2 — Language:** native lang · learning lang · proficiency · formality · comm style (max 3)
- **Step 3 — Goals:** goals (max 3) · scenarios (max 4) · cultural context · avoid list

---

## D. Core feature screens (16)

### 13. HomeScreen — `/home`
Dashboard. **States:** loading · empty · error · populated. **Popups:** MoodCheck bottom sheet · NotificationsPanel (drag sheet) · Quick-actions picker sheet.

### 14. ConsultantScreen — `/consultant`
AI chat. **States:** loading · empty · text-chat · voice-streaming. **Popups:** memory disambiguation dialog · voice-mode overlay · suggestion sheet.

### 15. NewSessionScreen — `/new-session`
Session wizard. **States:** mood step · goals step · persona/language step · confidence meter · loading · success. **Popups:** persona/goal picker sheet · session-style picker sheet · SessionContextDialog (topic/goal/mood).

### 16. SessionsScreen — `/sessions`
History list. **States:** loading (skeleton) · empty · filtered · populated. **Popups:** none.

### 17. SessionAnalyticsScreen — `/session-analytics`
Post-session metrics. **States:** loading · empty · error · success · voice-analysis. **Popups:** mistake details sheet.

### 18. RoleplaySetupScreen — `/roleplay-setup`
Scenario briefing. **States:** loading · normal · ready. **Popups:** difficulty tooltip.

### 19. PracticeScreen — `/practice`
Live practice (SSE/voice). **States:** loading · recording · transcribing · awaiting-response · normal · error · success. **Popups:** entity picker sheet · scenario briefing sheet · teleprompter overlay · voice overlay controls.

### 20. DrillsScreen — `/drills`
Pronunciation drills. **States:** loading · empty · list · in-drill (record/pass/fail/retry) · error. **Popups:** drill-result popup · mistake correction sheet.

### 21. ProgressScreen — `/progress`
Trends/charts. **States:** loading · empty · normal · error. **Popups:** chart detail popover.

### 22. ScenarioResultsScreen — `/scenario-results`
Results summary. **States:** success · loading · review. **Popups:** inline mistake list · continue/retry.

### 23. InsightsScreen — `/insights`
Performance insights. **States:** loading · empty · normal · error. **Popups:** save/export bottom sheet.

### 24. TasksScreen — `/tasks`
Daily tasks. **States:** loading · empty · normal · completed. **Popups:** task-reward popup · task-detail sheet.

### 25. EntityScreen — `/entities`
Knowledge-graph entities. **States:** loading · empty · list · detail. **Popups:** action menu sheet · entity-detail drag sheet · ask-about sheet.

### 26. GraphExplorerScreen — `/graph-explorer`
Graph visualization. **States:** loading · empty · rendered · query · result · node-detail. **Popups:** query-result sheet · entity quick-ref sheet · filter sheet.

### 27. GameCenterScreen — `/game-center` (replaces `/quests`)
Gamification hub. **States:** loading · empty · normal · challenge-active · question-set · completed. **Popups:** conversation-mission sheet · question-set modal · achievement-unlock popup.

### 28. ConnectionsScreen — `/connections`
Brain server URL config. **States:** default · connecting · connected · disconnected. **Popups:** success/error snackbars ("✅ Connected" / "❌ Connection Failed").

---

## E. Settings & info (10)

### 29. SettingsScreen — `/settings`
Hub. **States:** default · logging-out. **Popups:** help sheet · logout error snackbar.

### 30. SettingsPreferencesScreen — `/settings/preferences`
Theme/color/language/privacy. **Popups:** theme-mode picker · color picker · language picker · quick-actions style picker.

### 31. SettingsAssistantScreen — `/settings/assistant`
AI tone. **Popups:** live-tone picker · consultant-tone picker.

### 32. SettingsVoiceAssistantScreen — `/settings/voice-assistant`
Wake word "Hey Bubbles", voice mode. **Popups:** voice-mode picker.

### 33. SettingsPerformaScreen — `/settings/performa`
View/edit persona. **States:** loading · no-persona · loaded · refreshing. **Popups:** → Performa wizard (edit mode).

### 34. LanguageScreen — `/settings/language`
Locale (English/Urdu/Arabic). **States:** default · selected · swipe-back. **Popups:** confirm snackbar.

### 35. DataManagementScreen — `/settings/data`
Export/delete account. **States:** default · exporting · export-error · deleting · delete-confirm. **Popups:** delete-confirmation dialog (type "DELETE") · system share sheet · error snackbars.

### 36. AboutScreen — `/about`
Abstract/team/support. **Popups:** feedback dialog (Rate App FAB) · contact sheet.

### 37. HelpIndexScreen — `/help`
Searchable help index. **States:** default · searching · no-results. **Popups:** help sheet · replay-tutorial → onboarding.

### 38. SubscriptionScreen — `/subscription`
**Non-functional stub** ("Coming Soon"). No popups.

---

## F. Global popup / overlay catalog (23 reusable components)

### Primitives
- **AppDialog** — tones: neutral/info/success/warning/danger; variants: `.show` / `.confirm` / `.notice` / loading
- **AppSheet** — glass bottom-sheet wrapper, optional header, drag handle
- **AppSnackBar** — toasts: info/success/warning/error (no stacking)

### Feature-specific
- **FeedbackDialog** — 5-star rating + comment
- **HelpSheet + HelpIconButton** — contextual help
- **ExportBottomSheet** — PDF export + share
- **SessionPlaybackSheet** — timeline scrubber, event markers, legend
- **NotificationsPanel** — swipe-dismiss, mark-read
- **VoiceOverlay** — recording/playing/idle/error HUD
- **TeleprompterPanel** — live hint HUD
- **MoodCheckWidget** — 5-emoji picker
- **TagsBottomSheet** — multi-select tags
- **MistakeListSheet** — mistake list display
- **SuggestionSheet** — AI suggestions
- **SessionContextDialog** — topic/goal/mood form
- **VoiceMode page** — full-screen consultant voice chat

### Settings dialogs (`settings_dialogs.dart`, 8 functions)
contact sheet · theme-mode picker · color picker · voice-mode picker · live-tone picker · consultant-tone picker · quick-actions-style picker · language picker.

---

## Notes

- **3 screens are invisible routers** (`splash`, `app_bootstrap`, `auth_gate`) — navigation logic, not visible UI. Visible screen count = **33**.
- **SubscriptionScreen is a stub** — surfaced in nav but non-functional.
- **Voice/SSE streaming** present in 3 screens: Consultant, Practice, SessionAnalytics.
