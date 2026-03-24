import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/tags_provider.dart';

/// Bottom sheet displaying the user's tags with checkboxes for a given session.
/// Allows toggling tags on/off and creating new tags.
class TagsBottomSheet extends StatefulWidget {
  final String? sessionId;
  final String? entityId;
  final List<Map<String, dynamic>> currentTags; // already applied to this session/entity

  const TagsBottomSheet({
    super.key,
    this.sessionId,
    this.entityId,
    required this.currentTags,
  }) : assert(sessionId != null || entityId != null, 'Must provide sessionId or entityId');

  @override
  State<TagsBottomSheet> createState() => _TagsBottomSheetState();
}

class _TagsBottomSheetState extends State<TagsBottomSheet> {
  late Set<String> _appliedTagIds;
  final TextEditingController _newTagController = TextEditingController();
  String _newTagColor = '#6C63FF';
  bool _adding = false;

  // Preset colours for new tags
  static const _palette = [
    '#6C63FF', '#FF6584', '#F9A825', '#00C853', '#0288D1', '#7B1FA2',
  ];

  @override
  void initState() {
    super.initState();
    _appliedTagIds = widget.currentTags.map((t) => t['id'] as String).toSet();
    // Ensure tags are loaded
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TagsProvider>().loadTags();
    });
  }

  @override
  void dispose() {
    _newTagController.dispose();
    super.dispose();
  }

  Color _hexColor(String hex) {
    hex = hex.replaceAll('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }

  Future<void> _toggleTag(String tagId, TagsProvider provider) async {
    if (_appliedTagIds.contains(tagId)) {
      final ok = widget.sessionId != null
          ? await provider.untagSession(widget.sessionId!, tagId)
          : await provider.untagEntity(widget.entityId!, tagId);
      if (ok && mounted) setState(() => _appliedTagIds.remove(tagId));
    } else {
      final ok = widget.sessionId != null
          ? await provider.tagSession(widget.sessionId!, tagId)
          : await provider.tagEntity(widget.entityId!, tagId);
      if (ok && mounted) setState(() => _appliedTagIds.add(tagId));
    }
  }

  Future<void> _createAndApply(TagsProvider provider) async {
    final name = _newTagController.text.trim();
    if (name.isEmpty) return;
    setState(() => _adding = true);
    final newTag = await provider.createTag(name, _newTagColor);
    if (newTag != null) {
      if (widget.sessionId != null) {
        await provider.tagSession(widget.sessionId!, newTag['id']);
      } else {
        await provider.tagEntity(widget.entityId!, newTag['id']);
      }
      if (mounted) {
        setState(() {
          _appliedTagIds.add(newTag['id'] as String);
          _newTagController.clear();
          _adding = false;
        });
      }
    } else {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Consumer<TagsProvider>(
      builder: (context, provider, _) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.onSurface.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      const Icon(Icons.label_outline, size: 20),
                      const SizedBox(width: 8),
                      Text('Tags', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Tag list
                if (!provider.loaded)
                  const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
                else if (provider.tags.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Text('No tags yet. Create one below.', style: TextStyle(color: colorScheme.onSurface.withOpacity(0.5))),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: provider.tags.length,
                    itemBuilder: (context, i) {
                      final tag = provider.tags[i];
                      final tagId = tag['id'] as String;
                      final applied = _appliedTagIds.contains(tagId);
                      final tagColor = _hexColor(tag['color'] as String? ?? '#6C63FF');
                      return CheckboxListTile(
                        value: applied,
                        onChanged: (_) => _toggleTag(tagId, provider),
                        title: Row(
                          children: [
                            Container(
                              width: 10, height: 10,
                              decoration: BoxDecoration(color: tagColor, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 8),
                            Text(tag['name'] as String),
                          ],
                        ),
                        secondary: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: () => provider.deleteTag(tagId),
                          color: colorScheme.error.withOpacity(0.6),
                        ),
                        activeColor: tagColor,
                        dense: true,
                      );
                    },
                  ),
                const Divider(),
                // New tag input
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('＋ New tag', style: theme.textTheme.labelMedium),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _newTagController,
                              decoration: const InputDecoration(
                                hintText: 'Tag name…',
                                isDense: true,
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              onSubmitted: (_) => _createAndApply(provider),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _adding
                              ? const SizedBox(width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 2))
                              : IconButton(
                                  icon: const Icon(Icons.check_circle),
                                  color: colorScheme.primary,
                                  onPressed: () => _createAndApply(provider),
                                ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Color picker
                      Wrap(
                        spacing: 6,
                        children: _palette.map((hex) {
                          final c = _hexColor(hex);
                          return GestureDetector(
                            onTap: () => setState(() => _newTagColor = hex),
                            child: Container(
                              width: 24, height: 24,
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: _newTagColor == hex
                                    ? Border.all(width: 2.5, color: colorScheme.onSurface)
                                    : null,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }
}
