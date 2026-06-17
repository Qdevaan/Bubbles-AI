// Purpose: Wizard step 2 — collects the user's target language and proficiency level.
import 'package:flutter/material.dart';

import '../draft.dart';

/// Step 2 of the PerformaWizard. Language preferences and communication style.
class Step2Language extends StatefulWidget {
  const Step2Language({
    super.key,
    required this.draft,
    required this.onChanged,
  });

  final PerformaDraft draft;
  final VoidCallback onChanged;

  static const proficiencyLevels = <String>[
    'beginner',
    'intermediate',
    'advanced',
    'fluent',
  ];

  static const formalityLevels = <String>[
    'casual',
    'neutral',
    'formal',
    'mixed',
  ];

  static const communicationStyles = <String>[
    'assertive',
    'friendly',
    'concise',
    'detailed',
    'humorous',
    'empathetic',
  ];

  @override
  State<Step2Language> createState() => _Step2LanguageState();
}

class _Step2LanguageState extends State<Step2Language> {
  late final TextEditingController _native;
  late final TextEditingController _learning;

  @override
  void initState() {
    super.initState();
    _native =
        TextEditingController(text: widget.draft.nativeLanguage ?? 'en');
    _learning =
        TextEditingController(text: widget.draft.learningLanguage ?? 'en');
    // Sync defaults back into the draft so step1->step2 navigation has them.
    widget.draft.nativeLanguage ??= 'en';
    widget.draft.learningLanguage ??= 'en';
  }

  @override
  void dispose() {
    _native.dispose();
    _learning.dispose();
    super.dispose();
  }

  void _toggleStyle(String style) {
    final list = widget.draft.communicationStyle;
    setState(() {
      if (list.contains(style)) {
        list.remove(style);
      } else if (list.length < 3) {
        list.add(style);
      }
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    return ListView(
      children: [
        TextField(
          controller: _native,
          decoration: const InputDecoration(
            labelText: 'Native language',
            hintText: 'e.g. en, ur, es',
          ),
          onChanged: (v) {
            draft.nativeLanguage = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _learning,
          decoration: const InputDecoration(
            labelText: 'Learning language',
            hintText: 'e.g. en',
          ),
          onChanged: (v) {
            draft.learningLanguage = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 16),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('Proficiency (self-rated)'),
        ),
        RadioGroup<String>(
          groupValue: draft.proficiencySelfRated,
          onChanged: (v) {
            setState(() => draft.proficiencySelfRated = v);
            widget.onChanged();
          },
          child: Column(
            children: [
              for (final lvl in Step2Language.proficiencyLevels)
                RadioListTile<String>(
                  title: Text(lvl),
                  value: lvl,
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('Formality preference'),
        ),
        RadioGroup<String>(
          groupValue: draft.formalityPreference,
          onChanged: (v) {
            setState(() => draft.formalityPreference = v ?? 'neutral');
            widget.onChanged();
          },
          child: Column(
            children: [
              for (final f in Step2Language.formalityLevels)
                RadioListTile<String>(
                  title: Text(f),
                  value: f,
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('Communication style (max 3)'),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final style in Step2Language.communicationStyles)
              FilterChip(
                label: Text(style),
                selected: draft.communicationStyle.contains(style),
                onSelected: (_) => _toggleStyle(style),
              ),
          ],
        ),
      ],
    );
  }
}
