# Home Screen Redesign

**Date:** 2026-05-05  
**Status:** Approved

## Goal

Compact, minimal, interesting home screen. Everything visible earns its place. Primary focus is the session orb/hero. No decorative chrome.

## What Gets Removed

- **Mood check-in widget** — `onMoodSelected` has `// TODO: persist mood via provider` — dead code, never persisted
- **Greeting text section** — "Good Morning, Ahmad." is pure decoration, adds ~80px of height with zero function
- **Section headers** — "Quick Actions" label + edit pencil button replaced by long-press gesture
- **"Recent Insights" label** — carousel is self-evident

## Layout (Top to Bottom)

```
┌──────────────────────────────────┐
│  [Avatar]  [🔥5 ⚡1240]  [Bell🔴] │  ← Header
├──────────────────────────────────┤
│                                  │
│        HERO (orb or card)        │  ← ~42% screen height
│                                  │
├──────────────────────────────────┤
│  [Pill] [Pill] [Pill] [Pill]  [⊞]│  ← Quick Actions + mode switcher
├──────────────────────────────────┤
│  [Card 1.2 peek] [Card] ···      │  ← Insights carousel
└──────────────────────────────────┘
```

---

## Section 1 — Header

Single row, 16px horizontal padding, 10px vertical.

| Slot | Content | Tap |
|------|---------|-----|
| Left | Avatar 44px circle, primary border 2px | → `/settings` |
| Center | Compact streak chip: `🔥{streak}  ⚡{xp}` — Manrope semibold 13px | → `/game-center` |
| Right | Bell icon 40px circle, red badge dot if unread | → notifications panel |

The `StreakStrip` widget is replaced by a new `CompactStreakChip` widget — single `Row` with two `Text` spans, no `SingleChildScrollView`. Level and freezes dropped from header (visible on game-center screen).

---

## Section 2 — Hero

### Setting

`SettingsProvider` gets a new field:
- Key: `session_hero_style` (SharedPreferences + Supabase `user_settings` column)
- Type: `String`, values: `'orb'` | `'card'`, default: `'orb'`
- Getter: `sessionHeroStyle`
- Setter: `setSessionHeroStyle(String val)`

Toggle exposed in Settings screen under a new "Home Screen" subsection (alongside the existing quick actions style setting).

### Orb Mode (default)

Existing `EntityOrb` widget, unchanged. Centered, ~42% of available screen height between header and quick actions. Connection state + breathing animation preserved.

### Card Mode

Full-width frosted glass card, ~200px height. Specs:

- **Background:** `LinearGradient` angled 135°, `slate900 → primary.withAlpha(180)`, dark mode only — light mode uses `Colors.white.withAlpha(230)` with primary tint
- **Texture:** `CustomPainter` scanline pattern — horizontal lines at 2px spacing, opacity 0.03. Gives subtle depth without being consciously visible.
- **Border:** Animated glow pulse — `BoxDecoration` border color animates between `primary.withAlpha(80)` and `primary.withAlpha(200)` using the existing `_breatheCtrl` animation controller. Green tint when connected, muted slate when disconnected.
- **Connection status:** Top-right of card — colored dot (green/red) + `Text` "Connected" / "No connection", 12px
- **Content:** Centered column — `Text("Start Session", fontSize: 26, fontWeight: w800)` + `Text("Tap to begin", fontSize: 13, color: slate400)`
- **Tap:** Full card `GestureDetector` → same logic as orb (connected → `/new-session`, disconnected → not-connected dialog)
- **Border radius:** 24px

---

## Section 3 — Quick Actions

### Modes

`SettingsProvider.quickActionsStyle` extended to three values: `'pills'` | `'icons'` | `'cards'`. Current `'list'` and `'grid'` values migrate: `'grid'` → `'cards'`, `'list'` → `'pills'`.

Each action has a unique accent color defined in a const map:

```dart
const _actionAccents = {
  'consultant':     Color(0xFF8B5CF6), // purple
  'sessions':       Color(0xFF3B82F6), // blue
  'roleplay':       Color(0xFFF59E0B), // amber
  'game-center':    Color(0xFF10B981), // emerald
  'graph-explorer': Color(0xFF06B6D4), // cyan
  'insights':       Color(0xFFEC4899), // pink
};
```

#### Pills mode (horizontal scroll row)
- `ListView.builder` horizontal, `shrinkWrap: true`
- Each pill: `Container` with `BorderRadius.circular(50)`, background = `accent.withAlpha(25)`, border = `accent.withAlpha(80)` at 1px
- Content: `Icon` (accent color, 18px) + `SizedBox(width: 6)` + `Text` (accent color, 13px, semibold)
- Padding: `horizontal: 14, vertical: 10`

#### Icons mode (2-row grid)
- `Wrap` with `spacing: 12, runSpacing: 12`, centered
- Each icon: 56px circle, `RadialGradient` center = `accent.withAlpha(200)`, edge = `accent.withAlpha(80)`
- `Icon` white, 24px, centered
- No label
- Scale animation on tap: `Transform.scale` with `GestureDetector` `onTapDown`/`onTapUp` via local `setState`

#### Cards mode (2-col grid)
- `GridView` 2 columns, `childAspectRatio: 1.6`, `mainAxisSpacing: 10`, `crossAxisSpacing: 10`
- Each card: `LinearGradient` angled, `accent.withAlpha(40) → accent.withAlpha(15)`, border `accent.withAlpha(60)`
- Icon top-left (accent, 20px), title below (white/slate900, 13px, w700)
- Contextual subtitle (slate400, 11px): hardcoded per action for now
  - consultant → "Ask anything"
  - sessions → "View history"
  - roleplay → "Practice scenarios"
  - game-center → "Your progress"
  - graph-explorer → "Knowledge graph"
  - insights → "Recent learnings"

### On-Screen Mode Switcher

Small icon button (`Icons.grid_view_rounded` cycling) at far-right of the actions area. No label. One tap cycles `'pills' → 'icons' → 'cards' → 'pills'`. Calls `settingsProvider.setQuickActionsStyle(nextMode)` — persisted immediately.

### Edit (Long-Press)

Long-press anywhere on the actions area → existing `_showQuickActionsEditSheet`. The edit pencil button and section header are removed.

---

## Section 4 — Insights Carousel

`PageView.builder` (or `ListView.builder` horizontal with `PageSnapping`) showing all insights. Width = screen width − 32px padding, with `viewportFraction: 0.88` to show 1.2 cards (right card peeks 12%).

### Card Visual by Type

| Type | Accent | Icon |
|------|--------|------|
| highlight | `AppColors.error` (red) | `Icons.warning_amber_rounded` |
| event | `Color(0xFFF59E0B)` (amber) | `Icons.event_rounded` |
| notification | `Color(0xFF3B82F6)` (blue) | `Icons.notifications_rounded` |

Each card: glass-morphic, left accent bar 3px wide, badge chip top-right, title bold 15px, body 2-line max overflow ellipsis, time-ago bottom-left, "See all →" bottom-right (only if more than 1 item exists).

### Page Dots

`Row` of dots below carousel, centered. Active dot: 8px × 8px, accent color. Inactive: 6px × 6px, slate400. Animated with `AnimatedContainer`.

### Empty State

Single card (same card style), accent = primary, title = "No insights yet", body = "Start a Wingman session to generate personalized insights." No illustration.

---

## Settings Screen Changes

New "Home Screen" section in Settings (between existing sections):

```
Home Screen
  Session hero style     [Orb ▾]   ← segmented or dropdown picker
  Quick actions layout   [Pills ▾]
```

Both use the same picker pattern already used elsewhere in settings.

---

## Files Affected

| File | Change |
|------|--------|
| `lib/providers/settings_provider.dart` | Add `sessionHeroStyle` field, getter, setter, load/save |
| `lib/screens/home_screen.dart` | Remove mood check-in, greeting section, section headers; add `CompactStreakChip`; wire hero toggle; wire mode switcher long-press |
| `lib/widgets/home/entity_orb.dart` | No changes |
| `lib/widgets/home/quick_actions.dart` | Add pills + icons + cards modes, unique accent colors, contextual subtitles, on-screen mode switcher |
| `lib/widgets/home/insight_card.dart` | Update to type-distinct visual (accent bar, color by type) |
| `lib/widgets/home/home_widgets.dart` | Export new `CompactStreakChip`, `SessionHeroCard` |
| `lib/widgets/session_hero_card.dart` | New widget — card mode hero |
| `lib/widgets/compact_streak_chip.dart` | New widget — condensed header streak display |
| `lib/screens/settings_screen.dart` | Add "Home Screen" section with two pickers |

---

## Migration Notes

- `quickActionsStyle` values remapped on load: `'list'` → `'pills'`, `'grid'` → `'cards'`. Existing `'icons'` value is unchanged — it maps directly to the new icons mode.
- Existing `StreakStrip` widget kept as-is (still used on game-center or wherever else it appears); `CompactStreakChip` is a new standalone widget
