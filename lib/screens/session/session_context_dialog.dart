// Purpose: Session context dialog — lets the user set scenario, role-mode, and notes before starting a new live session.
import 'package:flutter/material.dart';

import '../../widgets/app_dialog.dart';

Future<Map<String, dynamic>?> showSessionContextDialog(BuildContext ctx) {
  String scenario = 'casual';
  const roleMode = 'default';
  String notes = '';
  const scenarios = [
    ['lecture', 'Lecture'],
    ['1on1', '1-on-1'],
    ['work_meeting', 'Work meeting'],
    ['casual', 'Casual'],
    ['interview', 'Interview'],
    ['presentation', 'Presentation'],
  ];
  return AppDialog.show<Map<String, dynamic>>(
    context: ctx,
    title: 'Quick context (optional)',
    icon: Icons.event_note_outlined,
    tone: AppDialogTone.info,
    content: StatefulBuilder(
      builder: (sdctx, setState) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Scenario'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: scenarios
                .map((p) => ChoiceChip(
                      label: Text(p[1]),
                      selected: scenario == p[0],
                      onSelected: (_) =>
                          setState(() => scenario = p[0]),
                    ))
                .toList(),
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(labelText: 'Notes'),
            onChanged: (v) => notes = v,
          ),
        ],
      ),
    ),
    actions: [
      AppDialogAction(
        label: 'Skip',
        onTap: () => Navigator.of(ctx).pop(null),
      ),
      AppDialogAction(
        label: 'Start session',
        primary: true,
        onTap: () => Navigator.of(ctx).pop({
          'scenario': scenario,
          'role_mode': roleMode,
          'notes': notes.isEmpty ? null : notes,
        }),
      ),
    ],
  );
}
