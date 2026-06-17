// Purpose: Wizard step 1 — collects the user's name, role, and industry for the Performa persona.
import 'package:flutter/material.dart';

import '../../../services/auth_service.dart';
import '../draft.dart';

/// Step 1 of the PerformaWizard. Collects identity-level information:
/// display name, age range, primary role, profession detail, and a small
/// list of expertise tags.
class Step1Identity extends StatefulWidget {
  const Step1Identity({
    super.key,
    required this.draft,
    required this.onChanged,
  });

  final PerformaDraft draft;
  final VoidCallback onChanged;

  static const ageRanges = <String>['<18', '18-24', '25-34', '35-44', '45+'];

  /// Role enum values shown as ChoiceChips. The label is title-cased for
  /// display while the underlying value stored on the draft is lower-cased
  /// (matches the DB enum used in `lib/models/persona.dart`).
  static const roles = <_RoleOption>[
    _RoleOption('student', 'Student'),
    _RoleOption('teacher', 'Teacher'),
    _RoleOption('professional', 'Professional'),
    _RoleOption('manager', 'Manager'),
    _RoleOption('freelancer', 'Freelancer'),
    _RoleOption('homemaker', 'Homemaker'),
    _RoleOption('other', 'Other'),
  ];

  @override
  State<Step1Identity> createState() => _Step1IdentityState();
}

class _RoleOption {
  final String value;
  final String label;
  const _RoleOption(this.value, this.label);
}

class _Step1IdentityState extends State<Step1Identity> {
  late final TextEditingController _displayName;
  late final TextEditingController _profession;
  late final TextEditingController _newTag;

  @override
  void initState() {
    super.initState();
    final existing = widget.draft.displayName;
    final initialName =
        (existing != null && existing.isNotEmpty) ? existing : _nameFromAuth();
    _displayName = TextEditingController(text: initialName);
    if ((existing == null || existing.isEmpty) && initialName.isNotEmpty) {
      // Push the prefilled name onto the draft so the wizard advances
      // without forcing the user to retype it.
      widget.draft.displayName = initialName;
    }
    _profession =
        TextEditingController(text: widget.draft.professionDetail ?? '');
    _newTag = TextEditingController();
  }

  /// Pulls a sensible default display name from the Supabase auth session:
  /// `user_metadata.full_name`, falling back to the email's local-part.
  static String _nameFromAuth() {
    final user = AuthService.instance.currentUser;
    final metaName = user?.userMetadata?['full_name'];
    if (metaName is String && metaName.trim().isNotEmpty) {
      return metaName.trim();
    }
    final email = user?.email;
    if (email != null && email.contains('@')) {
      final local = email.split('@').first.trim();
      if (local.isNotEmpty) return local;
    }
    return '';
  }

  @override
  void dispose() {
    _displayName.dispose();
    _profession.dispose();
    _newTag.dispose();
    super.dispose();
  }

  void _addTag(String raw) {
    final tag = raw.trim();
    if (tag.isEmpty) return;
    if (widget.draft.expertiseTags.contains(tag)) return;
    if (widget.draft.expertiseTags.length >= 5) return; // ignore further additions
    setState(() {
      widget.draft.expertiseTags.add(tag);
      _newTag.clear();
    });
    widget.onChanged();
  }

  void _removeTag(String tag) {
    setState(() {
      widget.draft.expertiseTags.remove(tag);
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    return ListView(
      children: [
        TextField(
          controller: _displayName,
          decoration: const InputDecoration(
            labelText: 'Display name',
            hintText: 'How should we address you?',
          ),
          onChanged: (v) {
            draft.displayName = v.isEmpty ? null : v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: draft.ageRange,
          decoration: const InputDecoration(labelText: 'Age range'),
          items: [
            for (final r in Step1Identity.ageRanges)
              DropdownMenuItem(value: r, child: Text(r)),
          ],
          onChanged: (v) {
            setState(() => draft.ageRange = v);
            widget.onChanged();
          },
        ),
        const SizedBox(height: 16),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('Primary role'),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final role in Step1Identity.roles)
              ChoiceChip(
                label: Text(role.label),
                selected: draft.rolePrimary == role.value,
                onSelected: (_) {
                  setState(() => draft.rolePrimary = role.value);
                  widget.onChanged();
                },
              ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _profession,
          decoration: const InputDecoration(
            labelText: 'Profession detail',
            hintText: 'Optional, e.g. "5th-grade math teacher"',
          ),
          onChanged: (v) {
            draft.professionDetail = v.isEmpty ? null : v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 16),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('Expertise tags (max 5)'),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tag in draft.expertiseTags)
              InputChip(
                label: Text(tag),
                onDeleted: () => _removeTag(tag),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _newTag,
          decoration: InputDecoration(
            labelText: 'Add tag',
            hintText: draft.expertiseTags.length >= 5
                ? 'Maximum 5 tags reached'
                : 'Press enter to add',
            suffixIcon: IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => _addTag(_newTag.text),
            ),
          ),
          onSubmitted: _addTag,
        ),
      ],
    );
  }
}
