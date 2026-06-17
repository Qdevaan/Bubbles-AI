// Purpose: Wizard step 3 — collects the user's communication goals and focus areas.
import 'package:flutter/material.dart';

import '../draft.dart';

/// Step 3 of the PerformaWizard. Goals, scenarios, and free-form context.
class Step3Goals extends StatefulWidget {
  const Step3Goals({
    super.key,
    required this.draft,
    required this.onChanged,
  });

  final PerformaDraft draft;
  final VoidCallback onChanged;

  static const goals = <String>[
    'confidence',
    'fluency',
    'interview_prep',
    'work_meetings',
    'academic',
    'social',
    'presentations',
  ];

  static const scenarios = <String>[
    'lectures',
    '1on1_tutoring',
    'work_meetings',
    'casual_chat',
    'interviews',
    'presentations',
    'customer_service',
  ];

  @override
  State<Step3Goals> createState() => _Step3GoalsState();
}

class _Step3GoalsState extends State<Step3Goals> {
  late final TextEditingController _cultural;
  late final TextEditingController _avoid;

  @override
  void initState() {
    super.initState();
    _cultural =
        TextEditingController(text: widget.draft.culturalContext ?? '');
    _avoid = TextEditingController(text: widget.draft.avoidList ?? '');
  }

  @override
  void dispose() {
    _cultural.dispose();
    _avoid.dispose();
    super.dispose();
  }

  void _toggleInList(List<String> list, String value, int max) {
    setState(() {
      if (list.contains(value)) {
        list.remove(value);
      } else if (list.length < max) {
        list.add(value);
      }
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    return ListView(
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('Primary goals (max 3)'),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final g in Step3Goals.goals)
              FilterChip(
                label: Text(g),
                selected: draft.primaryGoals.contains(g),
                onSelected: (_) => _toggleInList(draft.primaryGoals, g, 3),
              ),
          ],
        ),
        const SizedBox(height: 16),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('Typical scenarios (max 4)'),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in Step3Goals.scenarios)
              FilterChip(
                label: Text(s),
                selected: draft.typicalScenarios.contains(s),
                onSelected: (_) => _toggleInList(draft.typicalScenarios, s, 4),
              ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _cultural,
          decoration: const InputDecoration(
            labelText: 'Cultural context',
            hintText: 'Optional notes about cultural background',
          ),
          maxLines: 2,
          onChanged: (v) {
            draft.culturalContext = v.isEmpty ? null : v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _avoid,
          decoration: const InputDecoration(
            labelText: 'Topics or words to avoid',
            hintText: 'Optional, comma-separated',
          ),
          maxLines: 2,
          onChanged: (v) {
            draft.avoidList = v.isEmpty ? null : v;
            widget.onChanged();
          },
        ),
      ],
    );
  }
}
