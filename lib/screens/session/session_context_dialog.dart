import 'package:flutter/material.dart';

Future<Map<String, dynamic>?> showSessionContextDialog(BuildContext ctx) {
  String scenario = 'casual';
  String roleMode = 'default';
  String notes = '';
  return showDialog<Map<String, dynamic>>(
    context: ctx,
    builder: (dctx) {
      const scenarios = [
        ['lecture', 'Lecture'],
        ['1on1', '1-on-1'],
        ['work_meeting', 'Work meeting'],
        ['casual', 'Casual'],
        ['interview', 'Interview'],
        ['presentation', 'Presentation'],
      ];
      return StatefulBuilder(builder: (sdctx, setState) {
        return AlertDialog(
          title: const Text('Quick context (optional)'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Scenario'),
                Wrap(
                  spacing: 8,
                  children: scenarios
                      .map((p) => ChoiceChip(
                            label: Text(p[1]),
                            selected: scenario == p[0],
                            onSelected: (_) => setState(() => scenario = p[0]),
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
            TextButton(
              onPressed: () => Navigator.of(dctx).pop(null),
              child: const Text('Skip'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dctx).pop({
                'scenario': scenario,
                'role_mode': roleMode,
                'notes': notes.isEmpty ? null : notes,
              }),
              child: const Text('Start session'),
            ),
          ],
        );
      });
    },
  );
}
