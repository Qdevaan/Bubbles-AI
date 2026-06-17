// Purpose: Static help content map — stores all in-app help text keyed by feature name for the help index screen.
import 'package:flutter/material.dart';

/// Stable identifier for a screen's help content. Add a new entry whenever a
/// screen wires up a `HelpIconButton`.
enum HelpScreen {
  home,
  newSession,
  drills,
  progress,
  practice,
  scenarioResults,
  sessions,
  settings,
  performa,
  voiceEnrollment,
  gameCenter,
  insights,
}

class HelpSection {
  final IconData icon;
  final String title;
  final String body;
  const HelpSection({required this.icon, required this.title, required this.body});
}

class HelpEntry {
  final String title;
  final String subtitle;
  final IconData icon;
  final String overview;
  final List<HelpSection> sections;
  final List<String> tips;

  const HelpEntry({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.overview,
    required this.sections,
    required this.tips,
  });
}

class HelpContent {
  HelpContent._();

  static const Map<HelpScreen, HelpEntry> entries = {
    HelpScreen.home: HelpEntry(
      title: 'Home',
      subtitle: 'Your daily dashboard',
      icon: Icons.home_rounded,
      overview:
          'Home shows what matters today: your streak, level, due drills, '
          'mood check-in, and quick actions to start a Live Wingman session.',
      sections: [
        HelpSection(
          icon: Icons.bolt_rounded,
          title: 'Quick actions',
          body:
              'Tap the tiles to jump into Live Wingman, Practice scenarios, '
              'Drills, or your Progress dashboard. The session button is the '
              'fastest path into a real conversation.',
        ),
        HelpSection(
          icon: Icons.local_fire_department_rounded,
          title: 'Streak & XP',
          body:
              'Daily activity grows your streak. XP comes from finished '
              'sessions, drill reviews, and completed scenarios. Tap the '
              'streak chip to see your gamification details.',
        ),
        HelpSection(
          icon: Icons.menu_rounded,
          title: 'Navigation drawer',
          body:
              'Swipe from the left or tap the menu icon to reach every '
              'feature: Live Wingman, Practice, Drills, Progress, Sessions, '
              'Game Center, Settings, and Help.',
        ),
      ],
      tips: [
        'Open Live Wingman before a real conversation for live suggestions.',
        'Check Drills daily — even five cards keeps your streak alive.',
        'New here? Replay the tutorial from Settings → Replay tutorial.',
      ],
    ),
    HelpScreen.newSession: HelpEntry(
      title: 'Live Wingman',
      subtitle: 'Real-time conversation coach',
      icon: Icons.mic_rounded,
      overview:
          'Live Wingman listens to your conversation in real time, transcribes '
          'each turn, surfaces reply suggestions, flags mistakes, and tracks '
          'your speaking confidence. End the session to save analytics.',
      sections: [
        HelpSection(
          icon: Icons.record_voice_over_rounded,
          title: 'Transcript',
          body:
              'The live transcript shows your speech and the other speaker. '
              'Interim text appears greyed out; final text snaps in once '
              'speech recognition settles.',
        ),
        HelpSection(
          icon: Icons.tips_and_updates_rounded,
          title: 'Suggestions strip',
          body:
              'Reply ideas appear under the transcript. Tap one to copy it. '
              'Suggestions adapt to your persona and the conversation goal.',
        ),
        HelpSection(
          icon: Icons.show_chart_rounded,
          title: 'Confidence meter',
          body:
              'The coloured pill tracks how confidently you speak — green is '
              'strong, amber is shaky, red is full of fillers. It updates on '
              'a rolling 8-second window.',
        ),
        HelpSection(
          icon: Icons.report_rounded,
          title: 'Mistakes badge',
          body:
              'Tap the badge to review mistakes detected during the session '
              'so you can practice them later as drills.',
        ),
      ],
      tips: [
        'Set the session context first — better context = better suggestions.',
        'Speak naturally. Pauses help the model segment turns cleanly.',
        'End the session properly to sync confidence & mistakes to the server.',
      ],
    ),
    HelpScreen.drills: HelpEntry(
      title: 'Drills',
      subtitle: 'Spaced-repetition practice cards',
      icon: Icons.style_rounded,
      overview:
          'Drills turn your past mistakes into flashcards. Cards are scheduled '
          'using spaced repetition: harder cards return sooner, easy cards '
          'stretch out. Reviewing daily compounds quickly.',
      sections: [
        HelpSection(
          icon: Icons.touch_app_rounded,
          title: 'Tap to flip',
          body:
              'Tap the card to reveal the answer. Read it, then grade your '
              'recall honestly — the algorithm depends on it.',
        ),
        HelpSection(
          icon: Icons.thumb_up_alt_rounded,
          title: 'Grade buttons',
          body:
              'Again = forgot, Hard = struggled, Good = recalled with effort, '
              'Easy = instant. The button you pick decides when the card '
              'comes back.',
        ),
        HelpSection(
          icon: Icons.archive_rounded,
          title: 'Retire',
          body:
              'Tap retire to permanently stop showing a card. Use this for '
              'mistakes you have truly internalised.',
        ),
        HelpSection(
          icon: Icons.schedule_rounded,
          title: 'Practice early',
          body:
              'If nothing is due, you can still practice early — those reviews '
              'do not affect scheduling but build muscle memory.',
        ),
      ],
      tips: [
        'Grade honestly — overrating cards breaks the schedule.',
        'Short daily sessions beat long weekly ones.',
        'Watch for the +XP toast after each review.',
      ],
    ),
    HelpScreen.progress: HelpEntry(
      title: 'Progress',
      subtitle: 'Your longitudinal dashboard',
      icon: Icons.insights_rounded,
      overview:
          'Progress aggregates 30, 90, or 365 days of activity into trends: '
          'sessions, mistakes, sentiment, mastery, and drill retention.',
      sections: [
        HelpSection(
          icon: Icons.toggle_on_rounded,
          title: 'Range selector',
          body:
              'Switch between 30D / 90D / 1Y to zoom out. Sparklines and '
              'summary cards refresh together.',
        ),
        HelpSection(
          icon: Icons.dashboard_rounded,
          title: 'Snapshot strip',
          body:
              'The top strip shows current streak, level, due drills, and '
              'mastery. Tap any tile to jump straight into that area.',
        ),
        HelpSection(
          icon: Icons.trending_up_rounded,
          title: 'Delta pills',
          body:
              'Each summary card shows the delta vs the previous period. '
              'Green = improvement, red = regression. Note: for mistakes, '
              'fewer is better, so the colours invert.',
        ),
        HelpSection(
          icon: Icons.bar_chart_rounded,
          title: 'Sparklines',
          body:
              'Tiny charts show the trend across the range. Gaps in the '
              'sentiment line mean no sessions on those days.',
        ),
      ],
      tips: [
        'Compare 30D vs 90D to see whether a recent dip is a blip or a trend.',
        'Tap snapshot tiles to navigate — they are shortcuts.',
        'Use the deltas to decide what to focus on next.',
      ],
    ),
    HelpScreen.practice: HelpEntry(
      title: 'Practice',
      subtitle: 'Personalised roleplay scenarios',
      icon: Icons.theater_comedy_rounded,
      overview:
          'Practice gives you a feed of AI-generated roleplay scenarios '
          'tailored to your persona. Pick one, read the briefing, and start '
          'a session to rehearse before the real thing.',
      sections: [
        HelpSection(
          icon: Icons.swipe_rounded,
          title: 'Scenario feed',
          body:
              'Swipe a card away to dismiss it; tap to open the briefing. '
              'New scenarios generate via the floating button.',
        ),
        HelpSection(
          icon: Icons.menu_book_rounded,
          title: 'Briefing sheet',
          body:
              'Each scenario includes the situation, your goal, success '
              'criteria, and a suggested opening line. Read it before you '
              'start.',
        ),
        HelpSection(
          icon: Icons.play_circle_fill_rounded,
          title: 'Start scenario',
          body:
              'Tap Start to launch Live Wingman pre-loaded with the scenario '
              'context — no manual setup needed.',
        ),
        HelpSection(
          icon: Icons.flag_rounded,
          title: 'Results',
          body:
              'After ending the session you land on a results screen showing '
              'pass/fail and AI feedback against the success criteria.',
        ),
      ],
      tips: [
        'Generate scenarios that match a real conversation you have coming up.',
        'Read the goal twice — the AI grades you against it.',
        'Dismiss what does not apply so the feed stays relevant.',
      ],
    ),
    HelpScreen.scenarioResults: HelpEntry(
      title: 'Scenario results',
      subtitle: 'Roleplay feedback',
      icon: Icons.flag_rounded,
      overview:
          'After ending a scenario session, this screen polls the server for '
          'an AI grade based on your transcript and the success criteria.',
      sections: [
        HelpSection(
          icon: Icons.check_circle_rounded,
          title: 'Pass / fail card',
          body:
              'A clear verdict with a short rationale. Pass means you hit the '
              'criteria; fail explains what was missing.',
        ),
        HelpSection(
          icon: Icons.lightbulb_rounded,
          title: 'Feedback',
          body:
              'Specific, actionable feedback you can apply next time. Save '
              'mistakes you want to drill via the Drills tab.',
        ),
      ],
      tips: [
        'Take a screenshot if the feedback is gold — you can revisit later.',
        'Failed scenarios are not bad — they show you what to work on.',
      ],
    ),
    HelpScreen.sessions: HelpEntry(
      title: 'Sessions',
      subtitle: 'Your full history',
      icon: Icons.history_rounded,
      overview:
          'Every Live Wingman or scenario session is saved here with '
          'transcripts, mistakes, and analytics. Search and filter to find '
          'specific moments.',
      sections: [
        HelpSection(
          icon: Icons.search_rounded,
          title: 'Search',
          body:
              'Search by title or transcript content. Results highlight the '
              'matching text inside each session.',
        ),
        HelpSection(
          icon: Icons.analytics_rounded,
          title: 'Analytics',
          body:
              'Tap a session to see its analytics tab: confidence over time, '
              'mistakes, sentiment, and the full transcript.',
        ),
      ],
      tips: [
        'Long-press a session for quick actions.',
        'Use search to find a phrase you remember saying.',
      ],
    ),
    HelpScreen.settings: HelpEntry(
      title: 'Settings',
      subtitle: 'Tune Bubbles to fit you',
      icon: Icons.settings_rounded,
      overview:
          'Customise everything: your persona, theme, voice assistant, '
          'language, permissions, and data. Use Replay tutorial to revisit '
          'the onboarding carousel.',
      sections: [
        HelpSection(
          icon: Icons.badge_outlined,
          title: 'Performa',
          body:
              'Your persona — role, goals, communication style. The whole AI '
              'experience adapts to this profile.',
        ),
        HelpSection(
          icon: Icons.tune_rounded,
          title: 'Preferences',
          body:
              'Theme, accent colour, language. Changes apply instantly.',
        ),
        HelpSection(
          icon: Icons.mic_rounded,
          title: 'Voice assistant',
          body:
              'Tune wake-word sensitivity, voice enrollment, and assistant '
              'behaviour.',
        ),
        HelpSection(
          icon: Icons.replay_rounded,
          title: 'Replay tutorial',
          body:
              'Re-open the onboarding carousel anytime to refresh your memory.',
        ),
      ],
      tips: [
        'Update your Performa whenever your role or goals shift.',
        'Voice enrollment improves transcription accuracy noticeably.',
      ],
    ),
    HelpScreen.performa: HelpEntry(
      title: 'Performa',
      subtitle: 'Your personal AI persona',
      icon: Icons.badge_outlined,
      overview:
          'Performa tells Bubbles who you are, what you do, and how you want '
          'to communicate. Every suggestion, scenario, and drill is shaped '
          'by this profile.',
      sections: [
        HelpSection(
          icon: Icons.person_rounded,
          title: 'Identity',
          body: 'Your name, role, and the context you operate in.',
        ),
        HelpSection(
          icon: Icons.language_rounded,
          title: 'Language',
          body:
              'Your primary spoken and written language. Affects suggestions '
              'and transcription.',
        ),
        HelpSection(
          icon: Icons.flag_rounded,
          title: 'Goals',
          body:
              'What you are trying to achieve with Bubbles. Used to seed '
              'scenarios and suggestions.',
        ),
      ],
      tips: [
        'Be specific in goals — vague goals produce vague AI output.',
        'Revisit Performa every month or after a role change.',
      ],
    ),
    HelpScreen.voiceEnrollment: HelpEntry(
      title: 'Voice enrollment',
      subtitle: 'Teach Bubbles your voice',
      icon: Icons.graphic_eq_rounded,
      overview:
          'Reading a few prompts aloud lets Bubbles separate your voice from '
          'others in the room — improving transcription, mistake detection, '
          'and confidence scoring.',
      sections: [
        HelpSection(
          icon: Icons.headphones_rounded,
          title: 'Quiet room',
          body: 'Find somewhere quiet. Background noise pollutes the model.',
        ),
        HelpSection(
          icon: Icons.record_voice_over_rounded,
          title: 'Speak naturally',
          body:
              'Use your normal speaking voice — not extra-slow or extra-loud. '
              'The model needs your everyday baseline.',
        ),
      ],
      tips: [
        'Re-enroll if your audio environment changes (new mic, new room).',
        'Enrollment is reversible — you can redo it from Settings.',
      ],
    ),
    HelpScreen.gameCenter: HelpEntry(
      title: 'Game Center',
      subtitle: 'Streaks, levels, and quests',
      icon: Icons.emoji_events_rounded,
      overview:
          'Game Center turns practice into progress: track your XP, level, '
          'streak, and active quests. Completing quests unlocks bonus XP.',
      sections: [
        HelpSection(
          icon: Icons.star_rounded,
          title: 'XP & levels',
          body:
              'XP comes from sessions, drill reviews, and quest completions. '
              'Each level requires more XP than the last.',
        ),
        HelpSection(
          icon: Icons.task_alt_rounded,
          title: 'Quests',
          body:
              'Short-term challenges (e.g. complete 5 drills today). Refresh '
              'daily or weekly depending on type.',
        ),
      ],
      tips: [
        'Streaks survive on a single small action a day — even one drill.',
        'Quests are the fastest XP source — check them every morning.',
      ],
    ),
    HelpScreen.insights: HelpEntry(
      title: 'Insights',
      subtitle: 'AI-generated patterns',
      icon: Icons.lightbulb_rounded,
      overview:
          'Insights are short observations Bubbles writes about your '
          'conversations — recurring mistakes, mood patterns, and growth '
          'opportunities.',
      sections: [
        HelpSection(
          icon: Icons.auto_awesome_rounded,
          title: 'Insight cards',
          body:
              'Each card highlights one pattern with a concrete example. Tap '
              'to expand.',
        ),
        HelpSection(
          icon: Icons.swipe_left_rounded,
          title: 'Dismiss',
          body:
              'Swipe an insight away if it is not useful — the AI learns from '
              'dismissals.',
        ),
      ],
      tips: [
        'Read insights weekly — they spot trends you would miss day-to-day.',
        'Convert recurring mistakes into drills with one tap.',
      ],
    ),
  };

  static HelpEntry get(HelpScreen screen) =>
      entries[screen] ??
      const HelpEntry(
        title: 'Help',
        subtitle: '',
        icon: Icons.help_outline_rounded,
        overview: 'No help content yet for this screen.',
        sections: [],
        tips: [],
      );
}
