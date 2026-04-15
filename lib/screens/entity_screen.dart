
import '../services/app_cache_service.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/design_tokens.dart';
import '../widgets/glass_morphism.dart';
import '../widgets/tags_bottom_sheet.dart';
import '../providers/tags_provider.dart';

/// Displays the user's knowledge graph entities (people, places, orgs, etc.)
/// backed by the `entities`, `entity_attributes`, and `entity_relations` tables.
/// This is the structured entity viewer described in Section 3.6.
class EntityScreen extends StatefulWidget {
  const EntityScreen({super.key});

  @override
  State<EntityScreen> createState() => _EntityScreenState();
}

class _EntityScreenState extends State<EntityScreen> {
  Timer? _debounceTimer;
  final _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _entities = [];
  bool _loading = true;
  String? _error;
  String _search = '';
  String _filterType = 'all';

  Map<String, Color> get _typeColors => {
    'person': Theme.of(context).colorScheme.secondary,
    'place': Color(0xFF34D399),
    'organization': Color(0xFFFBBF24),
    'event': Color(0xFFF87171),
    'object': Color(0xFF60A5FA),
    'concept': Color(0xFFA78BFA),
  };

  static const _typeIcons = {
    'person': Icons.person_rounded,
    'place': Icons.place_rounded,
    'organization': Icons.business_rounded,
    'event': Icons.event_rounded,
    'object': Icons.category_rounded,
    'concept': Icons.lightbulb_rounded,
  };

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final uid = AuthService.instance.currentUser?.id;
    // context.read is safe in initState() — AppCacheService is a root provider (listen: false)
    final cache = context.read<AppCacheService>();
    if (cache.entities != null && cache.cacheUserId == uid) {
      _entities = List.from(cache.entities!);
      _loading = false;
    } else {
      _loadEntities();
    }
  }

  Future<void> _loadEntities() async {
    context.read<AppCacheService>().invalidateEntities();
    setState(() {
      _loading = true;
      _error = null;
    });
    final user = AuthService.instance.currentUser;
    if (user == null) {
      setState(() {
        _loading = false;
        _error = 'Not logged in.';
      });
      return;
    }
    try {
      // Fetch entities with their attributes as a joined query
      final entRes = await _supabase
          .from('entities')
          .select(
            'id, display_name, canonical_name, entity_type, description, mention_count, last_seen_at',
          )
          .eq('user_id', user.id)
          .order('mention_count', ascending: false)
          .limit(100);

      // Fetch attributes separately, then attach client-side
      final attRes = await _supabase
          .from('entity_attributes')
          .select('entity_id, attribute_key, attribute_value');

      // Fetch relations
      final relRes = await _supabase
          .from('entity_relations')
          .select('source_id, target_id, relation')
          .eq('user_id', user.id);

      // Fetch tags
      final tagRes = await _supabase
          .from('entity_tags')
          .select('entity_id, tags(id, name, color)')
          .eq('user_id', user.id);

      // Build attribute map
      final Map<String, List<Map<String, String>>> attrMap = {};
      for (final a in (attRes as List)) {
        final eid = a['entity_id'] as String;
        attrMap.putIfAbsent(eid, () => []);
        attrMap[eid]!.add({
          'key': a['attribute_key'] as String,
          'value': a['attribute_value'] as String,
        });
      }

      // Build relation map (source_id -> list of {relation, target_name})
      final relList = relRes as List;
      final entityNameMap = <String, String>{};
      for (final e in (entRes as List)) {
        entityNameMap[e['id'] as String] = e['display_name'] as String;
      }
      final Map<String, List<Map<String, String>>> relMap = {};
      for (final r in relList) {
        final src = r['source_id'] as String;
        final tgt = entityNameMap[r['target_id']] ?? r['target_id'] as String;
        final rel = r['relation'] as String;
        relMap.putIfAbsent(src, () => []);
        relMap[src]!.add({'relation': rel, 'target': tgt});
      }

      // Build tag map
      final Map<String, List<Map<String, dynamic>>> tagMap = {};
      for (final t in (tagRes as List)) {
        final eid = t['entity_id'] as String;
        tagMap.putIfAbsent(eid, () => []);
        tagMap[eid]!.add(t['tags'] as Map<String, dynamic>);
      }

      final enriched = entRes.map<Map<String, dynamic>>((e) {
        final id = e['id'] as String;
        return {
          ...e,
          'attributes': attrMap[id] ?? [],
          'relations': relMap[id] ?? [],
          'tags': tagMap[id] ?? [],
        };
      }).toList();

      if (!mounted) return;
      context.read<AppCacheService>().setEntities(enriched, user.id);
      setState(() {
        _entities = enriched;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _deleteEntity(String entityId) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => GlassDialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.error.withAlpha(26),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Delete Entity?',
                        style: GoogleFonts.manrope(
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                          color: isDark ? Colors.white : AppColors.slate900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'This will also remove all attributes and relations for this entity.',
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      color: isDark ? AppColors.slate400 : AppColors.slate500,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(
                          'Cancel',
                          style: GoogleFonts.manrope(
                            fontWeight: FontWeight.w700,
                            color: isDark ? AppColors.slate400 : AppColors.slate500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );

    if (confirm != true) return;

    try {
      // Cascade: delete attributes and relations first (if no DB cascade set)
      await _supabase
          .from('entity_attributes')
          .delete()
          .eq('entity_id', entityId);
      await _supabase
          .from('entity_relations')
          .delete()
          .eq('source_id', entityId);
      await _supabase
          .from('entity_relations')
          .delete()
          .eq('target_id', entityId);
      await _supabase.from('entities').delete().eq('id', entityId);

      setState(() {
        _entities.removeWhere((e) => e['id'] == entityId);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Entity deleted.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Delete failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filtered {
    var list = _entities;
    if (_filterType != 'all') {
      list = list.where((e) => e['entity_type'] == _filterType).toList();
    }
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list
          .where(
            (e) =>
                (e['display_name'] as String).toLowerCase().contains(q) ||
                ((e['description'] ?? '') as String).toLowerCase().contains(q),
          )
          .toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity != null && details.primaryVelocity! > 300) {
          // Swipe Right -> go back
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: isDark
            ? AppColors.backgroundDark
            : AppColors.backgroundLight,
        body: Stack(
          children: [
            const MeshGradientBackground(),
            SafeArea(
          child: Column(
            children: [
              // ---- Header ----
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(
                        Icons.arrow_back,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Knowledge Graph',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.manrope(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: isDark
                              ? Colors.white
                              : AppColors.slate900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _loadEntities,
                      icon: Icon(
                        Icons.refresh,
                        color: isDark ? Colors.white70 : Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),

              // ---- Search ----
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  onChanged: (v) {
                    if (_debounceTimer?.isActive ?? false)
                      _debounceTimer!.cancel();
                    _debounceTimer = Timer(
                      AppDurations.dialog,
                      () {
                        setState(() => _search = v);
                      },
                    );
                  },
                  style: GoogleFonts.manrope(
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search entities...',
                    hintStyle: GoogleFonts.manrope(
                      color: isDark
                          ? AppColors.slate500
                          : Colors.grey.shade500,
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      color: isDark
                          ? AppColors.slate500
                          : Colors.grey.shade500,
                    ),
                    filled: true,
                    fillColor: isDark
                        ? AppColors.glassInput
                        : Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      borderSide: isDark
                          ? const BorderSide(color: AppColors.glassBorder)
                          : BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                  ),
                ),
              ),

              // ---- Type Filter ----
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _TypeChip(
                      label: 'All',
                      selected: _filterType == 'all',
                      onTap: () => setState(() => _filterType = 'all'),
                      isDark: isDark,
                    ),
                    ...[
                      'person',
                      'place',
                      'organization',
                      'event',
                      'object',
                      'concept',
                    ].map(
                      (t) => _TypeChip(
                        label: t[0].toUpperCase() + t.substring(1),
                        selected: _filterType == t,
                        onTap: () => setState(() => _filterType = t),
                        color: _typeColors[t],
                        isDark: isDark,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // ---- Count badge ----
              if (!_loading && _error == null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${_filtered.length} entit${_filtered.length == 1 ? 'y' : 'ies'}',
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        color: isDark
                            ? AppColors.slate500
                            : Colors.grey.shade500,
                      ),
                    ),
                  ),
                ),

              // ---- List ----
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? _ErrorView(
                        error: _error!,
                        onRetry: _loadEntities,
                        isDark: isDark,
                      )
                    : _filtered.isEmpty
                    ? _EmptyView(isDark: isDark)
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: _filtered.length,
                        itemBuilder: (ctx, i) => _EntityCard(
                          entity: _filtered[i],
                          isDark: isDark,
                          typeColors: _typeColors,
                          typeIcons: _typeIcons,
                          onRefresh: _loadEntities,
                          onDelete: () =>
                              _deleteEntity(_filtered[i]['id'] as String),
                        ),
                      ),
              ),
            ],
          ),
          ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------
//  ENTITY CARD
// ------------------------------------------------------------
class _EntityCard extends StatefulWidget {
  final Map<String, dynamic> entity;
  final bool isDark;
  final Map<String, Color> typeColors;
  final Map<String, IconData> typeIcons;
  final VoidCallback onRefresh;
  final VoidCallback onDelete;

  const _EntityCard({
    required this.entity,
    required this.isDark,
    required this.typeColors,
    required this.typeIcons,
    required this.onRefresh,
    required this.onDelete,
  });

  @override
  State<_EntityCard> createState() => _EntityCardState();
}

class _EntityCardState extends State<_EntityCard> {
  bool _expanded = false;
  bool _askingAi = false;
  bool _saving = false;

  Future<void> _editEntity(BuildContext context) async {
    final e = widget.entity;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final nameCtrl = TextEditingController(text: e['display_name'] as String? ?? '');
    final descCtrl = TextEditingController(text: e['description'] as String? ?? '');
    String selectedType = e['entity_type'] as String? ?? 'concept';

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: StatefulBuilder(
          builder: (ctx, setModal) => GlassBottomSheet(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36, height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.glassBorder : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text('Edit Entity', style: GoogleFonts.manrope(fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : AppColors.slate900)),
                const SizedBox(height: 16),
                TextField(
                  controller: nameCtrl,
                  style: GoogleFonts.manrope(
                      color: isDark ? Colors.white : AppColors.slate900),
                  decoration: InputDecoration(
                    labelText: 'Name',
                    labelStyle: GoogleFonts.manrope(
                        color: isDark ? AppColors.slate400 : AppColors.slate500),
                    filled: true,
                    fillColor: isDark ? AppColors.glassInput : Colors.grey.shade100,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        borderSide: isDark
                            ? const BorderSide(color: AppColors.glassBorder)
                            : BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Type', style: GoogleFonts.manrope(fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppColors.slate400 : AppColors.slate500)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8, runSpacing: 6,
                  children: ['person', 'place', 'organization', 'event', 'object', 'concept']
                      .map((t) {
                    final active = selectedType == t;
                    final color = widget.typeColors[t] ?? AppColors.slate400;
                    return GestureDetector(
                      onTap: () => setModal(() => selectedType = t),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: active
                              ? color.withAlpha(46)
                              : (isDark ? AppColors.glassWhite : Colors.grey.shade100),
                          borderRadius: BorderRadius.circular(AppRadius.full),
                          border: Border.all(
                              color: active ? color : Colors.transparent,
                              width: 1.5),
                        ),
                        child: Text(t[0].toUpperCase() + t.substring(1),
                            style: GoogleFonts.manrope(fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: active
                                    ? color
                                    : (isDark
                                        ? AppColors.slate400
                                        : Colors.grey.shade600))),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  maxLines: 3,
                  style: GoogleFonts.manrope(
                      color: isDark ? Colors.white : AppColors.slate900),
                  decoration: InputDecoration(
                    labelText: 'Description (optional)',
                    labelStyle: GoogleFonts.manrope(
                        color: isDark ? AppColors.slate400 : AppColors.slate500),
                    filled: true,
                    fillColor: isDark ? AppColors.glassInput : Colors.grey.shade100,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        borderSide: isDark
                            ? const BorderSide(color: AppColors.glassBorder)
                            : BorderSide.none),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text('Cancel',
                          style: GoogleFonts.manrope(fontWeight: FontWeight.w700,
                              color: isDark
                                  ? AppColors.slate400
                                  : AppColors.slate500)),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (saved != true) return;
    final newName = nameCtrl.text.trim();
    if (newName.isEmpty) return;

    setState(() => _saving = true);
    try {
      final supabase = Supabase.instance.client;
      await supabase.from('entities').update({
        'display_name': newName,
        'entity_type': selectedType,
        'description':
            descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
      }).eq('id', e['id'] as String);

      widget.entity['display_name'] = newName;
      widget.entity['entity_type'] = selectedType;
      widget.entity['description'] =
          descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Entity updated.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        widget.onRefresh();
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $err'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _askAboutEntity(BuildContext context) async {
    final user = AuthService.instance.currentUser;
    if (user == null) return;
    final entityName = widget.entity['display_name'] as String? ?? '';
    if (entityName.isEmpty) return;

    setState(() => _askingAi = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final summary = await api.askAboutEntity(user.id, entityName);
      if (!mounted) return;
      final isDark = Theme.of(context).brightness == Brightness.dark;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xxl)),
        ),
        builder: (_) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.5,
          maxChildSize: 0.85,
          builder: (_, controller) => GlassBottomSheet(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.glassBorder : Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            size: 18,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'AI Summary: $entityName',
                              style: GoogleFonts.manrope(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: isDark ? Colors.white : AppColors.slate900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: SingleChildScrollView(
                          controller: controller,
                          child: Text(
                            summary,
                            style: GoogleFonts.manrope(
                              fontSize: 14,
                              height: 1.6,
                              color: isDark ? AppColors.slate300 : AppColors.slate700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('AI query failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _askingAi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entity;
    final entityType = e['entity_type'] as String? ?? 'concept';
    final color = widget.typeColors[entityType] ?? AppColors.slate400;
    final icon = widget.typeIcons[entityType] ?? Icons.circle_outlined;
    final attrs = e['attributes'] as List<Map<String, String>>? ?? [];
    final rels = e['relations'] as List<Map<String, String>>? ?? [];
    final tags = e['tags'] as List<Map<String, dynamic>>? ?? [];
    final mentionCount = e['mention_count'] as int? ?? 1;

    Color hexToColor(String hexString) {
      var hexColor = hexString.replaceAll('#', '');
      if (hexColor.length == 6) hexColor = 'FF$hexColor';
      return Color(int.tryParse(hexColor, radix: 16) ?? 0xFF6C63FF);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: widget.isDark ? AppColors.glassWhite : Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        border: Border.all(
          color: widget.isDark
              ? AppColors.glassBorder
              : Colors.grey.shade200,
        ),
      ),
      child: Column(
        children: [
          // ---- Header row ----
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(AppRadius.xxl),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: color.withAlpha(46),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e['display_name'] as String? ?? 'Unknown',
                          style: GoogleFonts.manrope(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: widget.isDark
                                ? Colors.white
                                : AppColors.slate900,
                          ),
                        ),
                        Row(
                          children: [
                            Text(
                              entityType[0].toUpperCase() + entityType.substring(1),
                              style: GoogleFonts.manrope(
                                fontSize: 12,
                                color: color,
                              ),
                            ),
                            if (tags.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              ...tags.take(3).map((t) => Container(
                                margin: const EdgeInsets.only(right: 3),
                                width: 8, height: 8,
                                decoration: BoxDecoration(
                                  color: hexToColor(t['color'] as String? ?? ''),
                                  shape: BoxShape.circle,
                                ),
                              )),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Mention count badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: color.withAlpha(31),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'x$mentionCount',
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: widget.isDark
                        ? AppColors.slate500
                        : Colors.grey.shade500,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),

          // ---- Expanded detail ----
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (e['description'] != null &&
                      (e['description'] as String).isNotEmpty) ...[
                    Text(
                      e['description'] as String,
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        color: widget.isDark
                            ? AppColors.slate400
                            : AppColors.slate500,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  // Attributes
                  if (attrs.isNotEmpty) ...[
                    _SectionLabel('Attributes', widget.isDark),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: attrs
                          .map(
                            (a) => _AttributeChip(
                              attrKey: a['key']!,
                              attrValue: a['value']!,
                              isDark: widget.isDark,
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 10),
                  ],

                  // Relations
                  if (rels.isNotEmpty) ...[
                    _SectionLabel('Relations', widget.isDark),
                    const SizedBox(height: 6),
                    ...rels.map(
                      (r) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Icon(Icons.arrow_forward, size: 14, color: color),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                '${r['relation']} -> ${r['target']}',
                                style: GoogleFonts.manrope(
                                  fontSize: 13,
                                  color: widget.isDark
                                      ? AppColors.slate300
                                      : AppColors.slate700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  // Delete + Ask AI + Tags actions
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: _saving ? null : () => _editEntity(context),
                        icon: _saving
                            ? const SizedBox(
                                width: 14, height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : Icon(Icons.edit_outlined, size: 16, color: color),
                        label: Text('Edit',
                            style: GoogleFonts.manrope(fontSize: 13, color: color)),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          final pTags = await context.read<TagsProvider>().getTagsForEntity(widget.entity['id'] as String);
                          if (!mounted) return;
                          await showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Theme.of(context).colorScheme.surface,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                            ),
                            builder: (_) => TagsBottomSheet(
                              entityId: widget.entity['id'] as String,
                              currentTags: pTags,
                            ),
                          );
                          widget.onRefresh();
                        },
                        icon: Icon(
                          Icons.label_outline,
                          size: 16,
                          color: color,
                        ),
                        label: Text(
                          'Tags',
                          style: GoogleFonts.manrope(
                            fontSize: 13,
                            color: color,
                          ),
                        ),
                      ),
                      // Ask AI button
                      TextButton.icon(
                        onPressed: _askingAi
                            ? null
                            : () => _askAboutEntity(context),
                        icon: _askingAi
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                Icons.auto_awesome,
                                size: 16,
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                        label: Text(
                          'Ask AI',
                          style: GoogleFonts.manrope(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: widget.onDelete,
                        icon: Icon(
                          Icons.delete_outline,
                          size: 16,
                          color: AppColors.error,
                        ),
                        label: Text(
                          'Delete',
                          style: GoogleFonts.manrope(
                            fontSize: 13,
                            color: AppColors.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------
//  HELPERS
// ------------------------------------------------------------
class _TypeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;
  final bool isDark;

  const _TypeChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = color ?? Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppDurations.fast,
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? activeColor.withAlpha(46)
              : (isDark ? AppColors.glassWhite : Colors.grey.shade100),
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(
            color: selected ? activeColor : (isDark ? AppColors.glassBorder : Colors.transparent),
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected
                ? activeColor
                : (isDark ? AppColors.slate400 : Colors.grey.shade600),
          ),
        ),
      ),
    );
  }
}

class _AttributeChip extends StatelessWidget {
  final String attrKey;
  final String attrValue;
  final bool isDark;

  const _AttributeChip({
    required this.attrKey,
    required this.attrValue,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isDark ? AppColors.glassWhite : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: isDark ? AppColors.glassBorder : Colors.grey.shade200,
        ),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$attrKey: ',
              style: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isDark ? AppColors.slate400 : Colors.grey.shade600,
              ),
            ),
            TextSpan(
              text: attrValue,
              style: GoogleFonts.manrope(
                fontSize: 12,
                color: isDark
                    ? AppColors.slate200
                    : AppColors.slate900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final bool isDark;
  const _SectionLabel(this.text, this.isDark);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: GoogleFonts.manrope(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
        color: isDark ? AppColors.slate500 : Colors.grey.shade500,
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  final bool isDark;
  const _ErrorView({
    required this.error,
    required this.onRetry,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: AppColors.error, size: 48),
            const SizedBox(height: 12),
            Text(
              'Failed to load entities',
              style: GoogleFonts.manrope(
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              error,
              style: GoogleFonts.manrope(
                fontSize: 12,
                color: AppColors.textMuted,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final bool isDark;
  const _EmptyView({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.hub_outlined,
              size: 52,
              color: isDark ? AppColors.slate700 : Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              'No entities yet',
              style: GoogleFonts.manrope(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: isDark ? AppColors.slate500 : Colors.grey.shade500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Start a Wingman session to automatically\nbuild your knowledge graph.',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                fontSize: 13,
                color: isDark ? AppColors.slate600 : Colors.grey.shade400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
