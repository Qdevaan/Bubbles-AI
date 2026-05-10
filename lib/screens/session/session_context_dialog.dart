import 'package:flutter/material.dart';

import '../../widgets/app_dialog.dart';

Future<Map<String, dynamic>?> showSessionContextDialog(BuildContext ctx) {
  String scenario = 'casual';
  String roleMode = 'default';
  String notes = '';
  const scenarios = [
    ['lecture', 'Lecture'],
    ['1on1', '1-on-1'],
    ['work_meeting', 'Work meeting'],
    ['casual', 'Casual'],
    ['interview', 'Interview'],
    ['presentation', 'Presentation'],
  ];
  return showDialog<Map<String, dynamic>>(
    context: ctx,
    builder: (dctx) {
      return StatefulBuilder(builder: (sdctx, setState) {
        return AppDialog(
          icon: Icons.event_note_outlined,
          title: 'Quick context (optional)',
          tone: AppDialogTone.info,
          content: Column(
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
          actions: [
            AppDialogAction(
              label: 'Skip',
              onTap: () => Navigator.of(dctx).pop(null),
            ),
            AppDialogAction(
              label: 'Start session',
              primary: true,
              onTap: () => Navigator.of(dctx).pop({
                'scenario': scenario,
                'role_mode': roleMode,
                'notes': notes.isEmpty ? null : notes,
              }),
            ),
          ],
        );
      });
    },
  );
}
