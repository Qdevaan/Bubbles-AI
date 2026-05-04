# Home Screen Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign Bubbles-AI home screen to be compact, minimal, and interesting — with hero orb/card toggle, three quick-action modes, and a type-distinct insights carousel.

**Architecture:** Seven focused tasks, each committed independently. New widgets land first, then `home_screen.dart` wires them in. `SettingsProvider` changes come first since all other tasks depend on the new `sessionHeroStyle` field.

**Tech Stack:** Flutter, Provider, SharedPreferences, Google Fonts, Supabase (for settings sync)

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `lib/providers/settings_provider.dart` | Modify | Add `sessionHeroStyle` field + getter + setter + load/save; migrate old `quickActionsStyle` values |
| `lib/widgets/compact_streak_chip.dart` | Create | Condensed `🔥streak ⚡xp` pill for header |
| `lib/widgets/session_hero_card.dart` | Create | Animated frosted-glass card hero alternative to orb |
| `lib/widgets/home/insights_carousel.dart` | Create | `PageView`-based carousel with type-distinct cards + page dots |
| `lib/widgets/home/quick_actions.dart` | Modify | New pills/icons/cards modes, unique accent colors, mode-switcher icon, long-press edit |
| `lib/widgets/home/home_widgets.dart` | Modify | Export `insights_carousel.dart` |
| `lib/screens/home_screen.dart` | Modify | Remove dead sections; wire new widgets; header, hero toggle, actions, carousel |
| `lib/screens/settings_screen.dart` | Modify | Add "Home Screen" section with two segment pickers |

---

## Task 1: SettingsProvider — sessionHeroStyle + quickActionsStyle migration

**Files:**
- Modify: `lib/providers/settings_provider.dart`

- [ ] **Step 1: Add the constant key**

In `settings_provider.dart`, find the block of `static const String` keys near the top of the class (around line 14). Add after the last existing key:

```dart
static const String _sessionHeroStyleKey = 'session_hero_style';
```

- [ ] **Step 2: Add the field and getter**

Find `String _quickActionsStyle = 'grid';` and add below it:

```dart
String _sessionHeroStyle = 'orb';
```

Find `String get quickActionsStyle => _quickActionsStyle;` and add below it:

```dart
String get sessionHeroStyle => _sessionHeroStyle;
```

- [ ] **Step 3: Add the setter**

Find `Future<void> setQuickActionsStyle(String style) async {` and add a similar method directly below it:

```dart
Future<void> setSessionHeroStyle(String style) async {
  _sessionHeroStyle = style;
  await _updateSetting(_sessionHeroStyleKey, style);
}
```

- [ ] **Step 4: Wire into loadSettings() SharedPreferences fallback**

Inside `loadSettings()`, find the line:
```dart
_quickActionsStyle = prefs.getString(_quickActionsStyleKey) ?? 'grid';
```
Replace it with:
```dart
final rawStyle = prefs.getString(_quickActionsStyleKey) ?? 'pills';
_quickActionsStyle = rawStyle == 'list' ? 'pills' : rawStyle == 'grid' ? 'cards' : rawStyle;
_sessionHeroStyle = prefs.getString(_sessionHeroStyleKey) ?? 'orb';
```

- [ ] **Step 5: Wire into _applySettingsMap()**

Find the line:
```dart
if (settings[_quickActionsStyleKey] != null) _quickActionsStyle = settings[_quickActionsStyleKey];
```
Replace it with:
```dart
if (settings[_quickActionsStyleKey] != null) {
  final raw = settings[_quickActionsStyleKey] as String;
  _quickActionsStyle = raw == 'list' ? 'pills' : raw == 'grid' ? 'cards' : raw;
}
if (settings[_sessionHeroStyleKey] != null) _sessionHeroStyle = settings[_sessionHeroStyleKey] as String;
```

- [ ] **Step 6: Verify with flutter analyze**

```
cd e:\FYP\FYP_V2\Bubbles-AI
flutter analyze lib/providers/settings_provider.dart
```
Expected: no errors.

- [ ] **Step 7: Commit**

```
git add lib/providers/settings_provider.dart
git commit -m "feat: add sessionHeroStyle setting and migrate quickActionsStyle values"
```

---

## Task 2: CompactStreakChip widget

**Files:**
- Create: `lib/widgets/compact_streak_chip.dart`

- [ ] **Step 1: Create the file**

Create `lib/widgets/compact_streak_chip.dart` with full content:

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/design_tokens.dart';

class CompactStreakChip extends StatelessWidget {
  final int streak;
  final int xp;
  final VoidCallback? onTap;

  const CompactStreakChip({
    super.key,
    required this.streak,
    required this.xp,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isDark ? AppColors.glassWhite : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(
            color: isDark ? AppColors.glassBorder : Colors.grey.shade200,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '🔥$streak',
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : AppColors.slate900,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '⚡$xp',
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : AppColors.slate900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify**

```
flutter analyze lib/widgets/compact_streak_chip.dart
```
Expected: no errors.

- [ ] **Step 3: Commit**

```
git add lib/widgets/compact_streak_chip.dart
git commit -m "feat: add CompactStreakChip widget for home header"
```

---

## Task 3: SessionHeroCard widget

**Files:**
- Create: `lib/widgets/session_hero_card.dart`

- [ ] **Step 1: Create the file**

Create `lib/widgets/session_hero_card.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/design_tokens.dart';

class _ScanlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withAlpha(8)
      ..strokeWidth = 1;
    for (double y = 0; y < size.height; y += 2) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_ScanlinePainter old) => false;
}

class SessionHeroCard extends StatelessWidget {
  final bool isConnected;
  final Animation<double> breatheAnimation;
  final VoidCallback onTap;

  const SessionHeroCard({
    super.key,
    required this.isConnected,
    required this.breatheAnimation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    const connectedColor = Color(0xFF10B981);

    final glowColor = isConnected ? connectedColor : AppColors.slate500;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedBuilder(
        animation: breatheAnimation,
        builder: (context, _) {
          final glow = breatheAnimation.value;
          return Container(
            height: 200,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [AppColors.slate900, primary.withAlpha(180)]
                    : [Colors.white.withAlpha(230), primary.withAlpha(60)],
              ),
              border: Border.all(
                color: glowColor.withAlpha((80 + (glow * 120)).round()),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: glowColor.withAlpha((20 + (glow * 40)).round()),
                  blurRadius: 20 + (glow * 10),
                  spreadRadius: -2,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(painter: _ScanlinePainter()),
                  ),
                  Positioned(
                    top: 16,
                    right: 16,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isConnected ? connectedColor : AppColors.error,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          isConnected ? 'Connected' : 'No connection',
                          style: GoogleFonts.manrope(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: isDark ? AppColors.slate400 : AppColors.slate500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Start Session',
                          style: GoogleFonts.manrope(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white : AppColors.slate900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Tap to begin',
                          style: GoogleFonts.manrope(
                            fontSize: 13,
                            color: isDark ? AppColors.slate400 : AppColors.slate500,
                          ),
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
    );
  }
}
```

- [ ] **Step 2: Verify**

```
flutter analyze lib/widgets/session_hero_card.dart
```
Expected: no errors.

- [ ] **Step 3: Commit**

```
git add lib/widgets/session_hero_card.dart
git commit -m "feat: add SessionHeroCard widget for card-mode home hero"
```

---

## Task 4: InsightsCarousel widget

**Files:**
- Create: `lib/widgets/home/insights_carousel.dart`
- Modify: `lib/widgets/home/home_widgets.dart`

- [ ] **Step 1: Create insights_carousel.dart**

Create `lib/widgets/home/insights_carousel.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/design_tokens.dart';
import '../../providers/home_provider.dart';
import '../../widgets/insights/insight_item.dart';
import 'insight_card.dart';

class InsightsCarousel extends StatefulWidget {
  final List<Map<String, dynamic>> events;
  final List<Map<String, dynamic>> highlights;
  final List<Map<String, dynamic>> notifications;
  final bool isDark;

  const InsightsCarousel({
    super.key,
    required this.events,
    required this.highlights,
    required this.notifications,
    required this.isDark,
  });

  @override
  State<InsightsCarousel> createState() => _InsightsCarouselState();
}

class _InsightsCarouselState extends State<InsightsCarousel> {
  late PageController _pageCtrl;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController(viewportFraction: 0.88);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  List<_InsightEntry> get _items {
    final list = <_InsightEntry>[];
    for (final h in widget.highlights) {
      final hlType = (h['highlight_type'] as String? ?? '').toLowerCase();
      list.add(_InsightEntry(
        id: h['id']?.toString() ?? '',
        type: 'highlight',
        accentColor: InsightItem.colorForType(hlType),
        icon: InsightItem.iconForType(hlType),
        title: h['title'] as String? ?? 'Highlight',
        badge: InsightItem.badgeForType(hlType),
        body: h['body'] as String? ?? '',
        createdAt: h['created_at'] as String?,
        sessionId: h['session_id'] as String?,
      ));
    }
    for (final e in widget.events) {
      list.add(_InsightEntry(
        id: e['id']?.toString() ?? '',
        type: 'event',
        accentColor: AppColors.warning,
        icon: Icons.event_rounded,
        title: e['title'] as String? ?? 'Event',
        badge: e['due_text'] as String? ?? 'Event',
        body: e['description'] as String? ?? '',
        createdAt: e['created_at'] as String?,
        sessionId: e['session_id'] as String?,
      ));
    }
    for (final n in widget.notifications) {
      list.add(_InsightEntry(
        id: n['id']?.toString() ?? '',
        type: 'notification',
        accentColor: const Color(0xFF3B82F6),
        icon: Icons.notifications_active_outlined,
        title: n['title'] as String? ?? 'Notification',
        badge: n['notif_type'] as String? ?? 'info',
        body: n['body'] as String? ?? '',
        createdAt: n['created_at'] as String?,
        sessionId: null,
      ));
    }
    return list;
  }

  void _dismiss(String id, String type) {
    context.read<HomeProvider>().dismissInsight(id, type);
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;

    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: HomeInsightCard(
          accentColor: Theme.of(context).colorScheme.primary,
          title: 'No insights yet',
          badge: 'Waiting',
          description:
              'Start a Wingman session to generate personalized insights.',
          isDark: widget.isDark,
        ),
      );
    }

    return Column(
      children: [
        SizedBox(
          height: 140,
          child: PageView.builder(
            controller: _pageCtrl,
            itemCount: items.length,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemBuilder: (context, i) {
              final entry = items[i];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: HomeInsightCard(
                  key: ValueKey(entry.id),
                  accentColor: entry.accentColor,
                  icon: entry.icon,
                  title: entry.title,
                  badge: entry.badge,
                  description: entry.body,
                  isDark: widget.isDark,
                  sessionId: entry.sessionId,
                  onLongPress: () => _dismiss(entry.id, entry.type),
                ),
              );
            },
          ),
        ),
        if (items.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(items.length, (i) {
                final active = i == _currentPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 8 : 6,
                  height: active ? 8 : 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active
                        ? Theme.of(context).colorScheme.primary
                        : AppColors.slate400,
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }
}

class _InsightEntry {
  final String id;
  final String type;
  final Color accentColor;
  final IconData icon;
  final String title;
  final String badge;
  final String body;
  final String? createdAt;
  final String? sessionId;

  const _InsightEntry({
    required this.id,
    required this.type,
    required this.accentColor,
    required this.icon,
    required this.title,
    required this.badge,
    required this.body,
    this.createdAt,
    this.sessionId,
  });
}
```

- [ ] **Step 2: Export from home_widgets.dart**

In `lib/widgets/home/home_widgets.dart`, add at the end:

```dart
export 'insights_carousel.dart';
```

- [ ] **Step 3: Verify**

```
flutter analyze lib/widgets/home/insights_carousel.dart lib/widgets/home/home_widgets.dart
```
Expected: no errors.

- [ ] **Step 4: Commit**

```
git add lib/widgets/home/insights_carousel.dart lib/widgets/home/home_widgets.dart
git commit -m "feat: add InsightsCarousel with type-distinct cards and page dots"
```

---

## Task 5: QuickActionsSection — three modes + mode switcher

**Files:**
- Modify: `lib/widgets/home/quick_actions.dart`

The existing file has `QuickActionCard`, `QuickActionListTile`, `QuickActionIconStyle`, and `QuickActionsSection`. We rewrite `QuickActionsSection` entirely and add new mode widgets. Existing `QuickActionCard` is kept for cards mode (slightly updated). `QuickActionListTile` is kept for backward compat but no longer called.

- [ ] **Step 1: Add accent colors constant and update action definitions**

At the top of `quick_actions.dart`, after the imports, add:

```dart
const Map<String, Color> _kActionAccents = {
  'consultant':     Color(0xFF8B5CF6),
  'sessions':       Color(0xFF3B82F6),
  'roleplay':       Color(0xFFF59E0B),
  'game-center':    Color(0xFF10B981),
  'graph-explorer': Color(0xFF06B6D4),
  'insights':       Color(0xFFEC4899),
};
```

- [ ] **Step 2: Add _QuickPillsMode widget**

After the existing `QuickActionCard` class, add:

```dart
class _QuickPillsMode extends StatelessWidget {
  final List<Map<String, dynamic>> actions;

  const _QuickPillsMode({required this.actions});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: actions.map((a) {
          final accent = _kActionAccents[a['id'] as String] ?? AppColors.primary;
          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: GestureDetector(
              onTap: () => Navigator.pushNamed(context, a['route'] as String),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: accent.withAlpha(25),
                  borderRadius: BorderRadius.circular(50),
                  border: Border.all(color: accent.withAlpha(80)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(a['icon'] as IconData, color: accent, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      a['title'] as String,
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
```

- [ ] **Step 3: Add _QuickIconsMode widget**

```dart
class _QuickIconsMode extends StatelessWidget {
  final List<Map<String, dynamic>> actions;

  const _QuickIconsMode({required this.actions});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Wrap(
        spacing: 20,
        runSpacing: 16,
        alignment: WrapAlignment.center,
        children: actions.map((a) {
          final accent = _kActionAccents[a['id'] as String] ?? AppColors.primary;
          return _IconCircle(
            icon: a['icon'] as IconData,
            accent: accent,
            onTap: () => Navigator.pushNamed(context, a['route'] as String),
          );
        }).toList(),
      ),
    );
  }
}

class _IconCircle extends StatefulWidget {
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  const _IconCircle({required this.icon, required this.accent, required this.onTap});

  @override
  State<_IconCircle> createState() => _IconCircleState();
}

class _IconCircleState extends State<_IconCircle> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) { setState(() => _pressed = false); widget.onTap(); },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.88 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                widget.accent.withAlpha(200),
                widget.accent.withAlpha(90),
              ],
            ),
          ),
          child: Icon(widget.icon, color: Colors.white, size: 24),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Add _QuickCardsMode widget**

```dart
class _QuickCardsMode extends StatelessWidget {
  final List<Map<String, dynamic>> actions;

  const _QuickCardsMode({required this.actions});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.6,
        ),
        itemCount: actions.length,
        itemBuilder: (context, i) {
          final a = actions[i];
          final accent = _kActionAccents[a['id'] as String] ?? AppColors.primary;
          return GestureDetector(
            onTap: () => Navigator.pushNamed(context, a['route'] as String),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.xxl),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [accent.withAlpha(50), accent.withAlpha(15)],
                ),
                border: Border.all(color: accent.withAlpha(60)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(a['icon'] as IconData, color: accent, size: 20),
                  const SizedBox(height: 8),
                  Text(
                    a['title'] as String,
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : AppColors.slate900,
                    ),
                  ),
                  Text(
                    a['subtitle'] as String,
                    style: GoogleFonts.manrope(
                      fontSize: 11,
                      color: isDark ? AppColors.slate400 : AppColors.slate500,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 5: Rewrite QuickActionsSection**

Find the existing `class QuickActionsSection extends StatelessWidget` and replace the entire class (from `class QuickActionsSection` to its closing `}`) with:

```dart
class QuickActionsSection extends StatelessWidget {
  final String style;
  final List<String> enabledIds;
  final VoidCallback onCycleMode;
  final VoidCallback onEditPress;

  const QuickActionsSection({
    super.key,
    required this.style,
    required this.enabledIds,
    required this.onCycleMode,
    required this.onEditPress,
  });

  static const _allActions = [
    {
      'id': 'consultant',
      'icon': Icons.psychology_rounded,
      'title': 'Consultant AI',
      'subtitle': 'Ask anything',
      'route': '/consultant',
    },
    {
      'id': 'sessions',
      'icon': Icons.history_rounded,
      'title': 'History',
      'subtitle': 'View history',
      'route': '/sessions',
    },
    {
      'id': 'roleplay',
      'icon': Icons.theater_comedy_outlined,
      'title': 'Roleplay Mode',
      'subtitle': 'Practice scenarios',
      'route': '/roleplay-setup',
    },
    {
      'id': 'game-center',
      'icon': Icons.emoji_events,
      'title': 'Game Center',
      'subtitle': 'Your progress',
      'route': '/game-center',
    },
    {
      'id': 'graph-explorer',
      'icon': Icons.hub_rounded,
      'title': 'Knowledge Graph',
      'subtitle': 'Knowledge graph',
      'route': '/graph-explorer',
    },
    {
      'id': 'insights',
      'icon': Icons.lightbulb_outline,
      'title': 'Insights',
      'subtitle': 'Recent learnings',
      'route': '/insights',
    },
  ];

  IconData _nextModeIcon() {
    if (style == 'pills') return Icons.grid_view_rounded;
    if (style == 'icons') return Icons.view_module_rounded;
    return Icons.view_list_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final actions = _allActions
        .where((a) => enabledIds.contains(a['id'] as String))
        .toList();

    if (actions.isEmpty) return const SizedBox.shrink();

    Widget content;
    if (style == 'pills') {
      content = _QuickPillsMode(actions: actions);
    } else if (style == 'icons') {
      content = _QuickIconsMode(actions: actions);
    } else {
      content = _QuickCardsMode(actions: actions);
    }

    return GestureDetector(
      onLongPress: onEditPress,
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 16, bottom: 6),
              child: GestureDetector(
                onTap: onCycleMode,
                child: Icon(
                  _nextModeIcon(),
                  size: 18,
                  color: isDark ? AppColors.slate400 : AppColors.slate500,
                ),
              ),
            ),
          ),
          content,
        ],
      ),
    );
  }
}
```

- [ ] **Step 6: Verify**

```
flutter analyze lib/widgets/home/quick_actions.dart
```
Expected: no errors (info warnings about unused `QuickActionListTile` are fine).

- [ ] **Step 7: Commit**

```
git add lib/widgets/home/quick_actions.dart
git commit -m "feat: redesign QuickActionsSection with pills/icons/cards modes and mode switcher"
```

---

## Task 6: home_screen.dart — wire all changes

**Files:**
- Modify: `lib/screens/home_screen.dart`

This task makes the most changes. Read the file carefully before editing.

- [ ] **Step 1: Update imports**

At the top of `home_screen.dart`, make these changes:

Remove this import:
```dart
import '../widgets/mood_check_widget.dart';
```

Replace the existing streak_strip import line:
```dart
import '../widgets/streak_strip.dart';
```
with:
```dart
import '../widgets/compact_streak_chip.dart';
import '../widgets/session_hero_card.dart';
```

The `home_widgets.dart` import already covers `InsightsCarousel` via the barrel (you added the export in Task 4). No additional import needed.

Add the `settings_provider` import if not already present (check first):
```dart
import '../providers/settings_provider.dart';
```

- [ ] **Step 2: Remove the greeting SliverToBoxAdapter**

Find and delete the entire SliverToBoxAdapter block that contains the greeting text. It looks like:

```dart
// --- GREETING with streak ---
SliverToBoxAdapter(
  child: Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
    child: Column(
      ...
      // contains _getGreeting() and ShaderMask with firstName
      ...
    ),
  ),
),
```

Delete this entire block.

- [ ] **Step 3: Remove the mood check-in SliverToBoxAdapter**

Find and delete:
```dart
// --- MOOD CHECK-IN ---
SliverToBoxAdapter(
  child: Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
    child: MoodCheckWidget(
      onMoodSelected: (mood) {
        // TODO: persist mood via provider
        debugPrint('Mood selected: $mood');
      },
    ),
  ),
),
```

- [ ] **Step 4: Replace the header's streak strip with CompactStreakChip**

In the header `Row`, find the `Expanded` widget wrapping the `SingleChildScrollView > Selector<GamificationProvider, ...> > StreakStrip`. Replace the entire `Expanded` child (from `Expanded(` to its closing `)`) with:

```dart
Selector<GamificationProvider, (int, int)>(
  selector: (_, gp) => (gp.currentStreak, gp.totalXp),
  builder: (context, gpData, _) => CompactStreakChip(
    streak: gpData.$1,
    xp: gpData.$2,
    onTap: () => Navigator.pushNamed(context, '/game-center'),
  ),
),
```

- [ ] **Step 5: Replace the hero section**

Find the entire hero section:
```dart
// --- HERO CARD: LIVE WINGMAN ---
SliverToBoxAdapter(
  child: Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Selector<ConnectionService, bool>(
      selector: (_, cs) => cs.isConnected,
      builder: (context, isConnected, __) =>
          GestureDetector(
        onTap: () { ... },
        child: EntityOrb( ... ),
      ),
    ),
  ),
),
```

Replace the entire block with:

```dart
// --- HERO ---
SliverToBoxAdapter(
  child: Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Selector2<ConnectionService, SettingsProvider, (bool, String)>(
      selector: (_, cs, sp) => (cs.isConnected, sp.sessionHeroStyle),
      builder: (context, data, __) {
        final (isConnected, heroStyle) = data;
        void onHeroTap() {
          HapticFeedback.mediumImpact();
          if (isConnected) {
            Navigator.pushNamed(context, '/new-session');
          } else {
            _showNotConnectedDialog(context);
          }
        }
        if (heroStyle == 'card') {
          return SessionHeroCard(
            isConnected: isConnected,
            breatheAnimation: _breatheCtrl,
            onTap: onHeroTap,
          );
        }
        return GestureDetector(
          onTap: onHeroTap,
          child: EntityOrb(
            isConnected: isConnected,
            breatheAnimation: _breatheCtrl,
            onTap: onHeroTap,
          ),
        );
      },
    ),
  ),
),
```

- [ ] **Step 6: Remove the Quick Actions section header, wire new callbacks**

Find the Quick Actions section header:
```dart
// --- QUICK ACTIONS ---
SliverToBoxAdapter(
  child: Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 4, 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('Quick Actions', ...),
        IconButton(
          icon: Icon(Icons.edit_outlined, ...),
          ...
          onPressed: () => _showQuickActionsEditSheet(context),
        ),
      ],
    ),
  ),
),
```

Delete this entire SliverToBoxAdapter block.

Then find the `SliverToBoxAdapter` containing `Consumer<SettingsProvider>` for QuickActionsSection and replace it with:

```dart
SliverToBoxAdapter(
  child: Consumer<SettingsProvider>(
    builder: (context, sp, _) {
      return QuickActionsSection(
        style: sp.quickActionsStyle,
        enabledIds: sp.enabledQuickActions,
        onCycleMode: () {
          final next = sp.quickActionsStyle == 'pills'
              ? 'icons'
              : sp.quickActionsStyle == 'icons'
                  ? 'cards'
                  : 'pills';
          sp.setQuickActionsStyle(next);
        },
        onEditPress: () => _showQuickActionsEditSheet(context),
      );
    },
  ),
),
```

- [ ] **Step 7: Replace the Recent Insights section**

Find the entire `SliverToBoxAdapter` for "RECENT INSIGHTS" — it starts at:
```dart
// --- RECENT INSIGHTS ---
SliverToBoxAdapter(
  child: Selector<HomeProvider, ...>(
```
and contains the header row ("Recent Insights" + "See All" + refresh) and the conditional rendering (loading skeleton, empty card, `RecentInsightsCarousel`).

Replace the entire block with:

```dart
// --- INSIGHTS ---
SliverToBoxAdapter(
  child: Selector<HomeProvider,
      (bool, List<Map<String, dynamic>>, List<Map<String, dynamic>>, List<Map<String, dynamic>>)>(
    selector: (_, home) => (
      home.insightsLoaded,
      home.events,
      home.highlights,
      home.notifications,
    ),
    shouldRebuild: (prev, next) =>
        prev.$1 != next.$1 ||
        prev.$2.length != next.$2.length ||
        prev.$3.length != next.$3.length ||
        prev.$4.length != next.$4.length,
    builder: (context, data, _) {
      final (insightsLoaded, events, highlights, notifications) = data;
      if (!insightsLoaded) {
        return const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SkeletonCardGroup(count: 3),
        );
      }
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: InsightsCarousel(
          events: events,
          highlights: highlights,
          notifications: notifications,
          isDark: isDark,
        ),
      );
    },
  ),
),
```

- [ ] **Step 8: Remove the RecentInsightsCarousel and MeasureSize class definitions**

At the bottom of `home_screen.dart`, find and delete everything from:
```dart
// ============================================================================
//  RECENT INSIGHTS CAROUSEL
// ============================================================================
class RecentInsightsCarousel extends StatefulWidget {
```
all the way to the end of the `_MeasureSizeRenderObject` class (the last `}` of the file).

Also remove the `_getGreeting()` method if it still exists in `_HomeScreenState` (it's no longer called).

- [ ] **Step 9: Verify**

```
flutter analyze lib/screens/home_screen.dart
```
Expected: no errors. The deprecated `withOpacity` warnings that already existed are fine.

- [ ] **Step 10: Commit**

```
git add lib/screens/home_screen.dart
git commit -m "feat: wire home screen redesign — compact header, hero toggle, new quick actions, insights carousel"
```

---

## Task 7: Settings screen — Home Screen section

**Files:**
- Modify: `lib/screens/settings_screen.dart`

- [ ] **Step 1: Add the Home Screen section widget**

In `settings_screen.dart`, find the `build` method. After the profile hero card block:
```dart
// — Profile Hero Card —
Padding(
  padding: const EdgeInsets.symmetric(horizontal: 16),
  child: _ProfileHeroCard(isDark: isDark, cs: cs),
),

const SizedBox(height: 24),

// — Content —
Padding(
  padding: const EdgeInsets.symmetric(horizontal: 16),
  child: GroupedContainer(
```

Insert the Home Screen section between `const SizedBox(height: 24)` and `// — Content —`:

```dart
// — Home Screen —
Padding(
  padding: const EdgeInsets.symmetric(horizontal: 16),
  child: Consumer<SettingsProvider>(
    builder: (context, sp, _) {
      return GroupedContainer(
        isDark: isDark,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Home Screen',
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppColors.slate400 : AppColors.slate500,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 16),
                _HomePickerRow(
                  label: 'Session hero',
                  options: const ['orb', 'card'],
                  labels: const ['Orb', 'Card'],
                  selected: sp.sessionHeroStyle,
                  onChanged: sp.setSessionHeroStyle,
                  isDark: isDark,
                ),
                const SizedBox(height: 12),
                _HomePickerRow(
                  label: 'Quick actions',
                  options: const ['pills', 'icons', 'cards'],
                  labels: const ['Pills', 'Icons', 'Cards'],
                  selected: sp.quickActionsStyle,
                  onChanged: sp.setQuickActionsStyle,
                  isDark: isDark,
                ),
              ],
            ),
          ),
        ],
      );
    },
  ),
),

const SizedBox(height: 16),
```

- [ ] **Step 2: Add _HomePickerRow widget**

At the bottom of `settings_screen.dart` (before the last `}`), add:

```dart
class _HomePickerRow extends StatelessWidget {
  final String label;
  final List<String> options;
  final List<String> labels;
  final String selected;
  final Future<void> Function(String) onChanged;
  final bool isDark;

  const _HomePickerRow({
    required this.label,
    required this.options,
    required this.labels,
    required this.selected,
    required this.onChanged,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : AppColors.slate900,
            ),
          ),
        ),
        Wrap(
          spacing: 6,
          children: List.generate(options.length, (i) {
            final isSelected = selected == options[i];
            return GestureDetector(
              onTap: () => onChanged(options[i]),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected ? primary.withAlpha(25) : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  border: Border.all(
                    color: isSelected ? primary : (isDark ? AppColors.glassBorder : Colors.grey.shade300),
                  ),
                ),
                child: Text(
                  labels[i],
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? primary : (isDark ? AppColors.slate400 : AppColors.slate500),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}
```

- [ ] **Step 3: Add SettingsProvider import if missing**

Check if `settings_provider.dart` is already imported in `settings_screen.dart`:

```
grep -n "settings_provider" lib/screens/settings_screen.dart
```

If not found, add:
```dart
import '../providers/settings_provider.dart';
```

- [ ] **Step 4: Verify**

```
flutter analyze lib/screens/settings_screen.dart
```
Expected: no errors.

- [ ] **Step 5: Commit**

```
git add lib/screens/settings_screen.dart
git commit -m "feat: add Home Screen section to settings with hero and quick actions pickers"
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Task |
|-----------------|------|
| Remove mood check-in | Task 6, Step 3 |
| Remove greeting section | Task 6, Step 2 |
| Compact header with CompactStreakChip | Tasks 2 + 6, Step 4 |
| Orb/card hero toggle via setting | Tasks 1 + 3 + 6, Step 5 |
| Pills/icons/cards quick actions modes | Task 5 |
| Unique accent colors per action | Task 5, Step 1 |
| Mode switcher icon in actions area | Task 5, Step 5 |
| Long-press to edit quick actions | Task 5, Step 5 |
| Type-distinct insight carousel | Task 4 |
| PageView with 0.88 viewportFraction (1.2 peek) | Task 4, Step 1 |
| Page dots | Task 4, Step 1 |
| Empty state inline in carousel | Task 4, Step 1 |
| Settings "Home Screen" section | Task 7 |
| quickActionsStyle migration | Task 1, Steps 4–5 |

All requirements covered. No gaps found.

**Type consistency check:**
- `CompactStreakChip(streak: int, xp: int, onTap: VoidCallback?)` — used correctly in Task 6 Step 4
- `SessionHeroCard(isConnected: bool, breatheAnimation: Animation<double>, onTap: VoidCallback)` — used correctly in Task 6 Step 5
- `QuickActionsSection(style, enabledIds, onCycleMode, onEditPress)` — all params passed in Task 6 Step 6
- `InsightsCarousel(events, highlights, notifications, isDark)` — all params passed in Task 6 Step 7
- `sp.setSessionHeroStyle(String)` / `sp.sessionHeroStyle` — defined Task 1, used Tasks 6 + 7
- `_kActionAccents` — defined Task 5 Step 1, used in Steps 2–4 (same file, const access)
