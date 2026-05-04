import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/performa.dart';
import '../providers/performa_provider.dart';
import '../repositories/performa_repository.dart';

class PerformaScreen extends StatefulWidget {
  const PerformaScreen({super.key});

  @override
  State<PerformaScreen> createState() => _PerformaScreenState();
}

class _PerformaScreenState extends State<PerformaScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userId = Supabase.instance.client.auth.currentUser?.id ?? '';
      if (userId.isNotEmpty) context.read<PerformaProvider>().load(userId);
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Performa'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'About'),
            Tab(text: 'People'),
            Tab(text: 'AI Insights'),
            Tab(text: 'Export'),
          ],
        ),
      ),
      body: Consumer<PerformaProvider>(
        builder: (ctx, prov, _) {
          if (prov.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          final p = prov.performa ?? Performa(userId: '');
          return TabBarView(
            controller: _tabs,
            children: [
              _AboutTab(performa: p, onSave: (updated) => _save(ctx, updated)),
              _PeopleTab(performa: p, onSave: (updated) => _save(ctx, updated)),
              _InsightsTab(performa: p),
              _ExportTab(performa: p),
            ],
          );
        },
      ),
    );
  }

  Future<void> _save(BuildContext ctx, Performa updated) async {
    final userId = Supabase.instance.client.auth.currentUser?.id ?? '';
    if (userId.isEmpty) return;
    await ctx.read<PerformaProvider>().save(userId, updated);
  }
}

// -- Tab 1: About -------------------------------------------------------------

class _AboutTab extends StatefulWidget {
  final Performa performa;
  final void Function(Performa) onSave;
  const _AboutTab({required this.performa, required this.onSave});
  @override
  State<_AboutTab> createState() => _AboutTabState();
}

class _AboutTabState extends State<_AboutTab> {
  late TextEditingController _name, _role, _industry, _company, _bg;
  String _style = '';
  late List<String> _goals, _scenarios, _languages;

  @override
  void initState() {
    super.initState();
    final p = widget.performa;
    _name = TextEditingController(text: p.fullName);
    _role = TextEditingController(text: p.role);
    _industry = TextEditingController(text: p.industry);
    _company = TextEditingController(text: p.company);
    _bg = TextEditingController(text: p.background);
    _style = p.communicationStyle;
    _goals = List.from(p.goals);
    _scenarios = List.from(p.conversationScenarios);
    _languages = List.from(p.languages);
  }

  @override
  void dispose() {
    _name.dispose(); _role.dispose(); _industry.dispose();
    _company.dispose(); _bg.dispose();
    super.dispose();
  }

  Performa _build() => widget.performa.copyWith(
    fullName: _name.text.trim(),
    role: _role.text.trim(),
    industry: _industry.text.trim(),
    company: _company.text.trim(),
    background: _bg.text.trim(),
    communicationStyle: _style,
    goals: _goals,
    conversationScenarios: _scenarios,
    languages: _languages,
  );

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _field(_name, 'Full name'),
        _field(_role, 'Role / Title'),
        _field(_industry, 'Industry'),
        _field(_company, 'Company'),
        const SizedBox(height: 8),
        _styleDropdown(),
        const SizedBox(height: 16),
        _chipSection('Goals', _goals, (v) => setState(() => _goals = v)),
        _chipSection('Scenarios', _scenarios, (v) => setState(() => _scenarios = v)),
        _chipSection('Languages', _languages, (v) => setState(() => _languages = v)),
        const SizedBox(height: 8),
        TextField(
          controller: _bg,
          decoration: const InputDecoration(labelText: 'Background (free text)'),
          maxLines: 4,
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => widget.onSave(_build()),
          child: const Text('Save'),
        ),
      ]),
    );
  }

  Widget _field(TextEditingController c, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(controller: c, decoration: InputDecoration(labelText: label)),
  );

  Widget _styleDropdown() => DropdownButtonFormField<String>(
    initialValue: _style.isEmpty ? null : _style,
    decoration: const InputDecoration(labelText: 'Communication Style'),
    items: ['direct', 'diplomatic', 'analytical']
        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
        .toList(),
    onChanged: (v) => setState(() => _style = v ?? ''),
  );

  Widget _chipSection(String label, List<String> items, void Function(List<String>) onChanged) {
    final controller = TextEditingController();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: Theme.of(context).textTheme.labelLarge),
      Wrap(
        spacing: 8,
        children: [
          ...items.map((s) => Chip(
            label: Text(s),
            onDeleted: () => onChanged(items.where((x) => x != s).toList()),
          )),
          ActionChip(
            label: const Text('+'),
            onPressed: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: Text('Add $label'),
                content: TextField(controller: controller, autofocus: true),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  FilledButton(
                    onPressed: () {
                      final v = controller.text.trim();
                      if (v.isNotEmpty) onChanged([...items, v]);
                      Navigator.pop(context);
                    },
                    child: const Text('Add'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
    ]);
  }
}

// -- Tab 2: People ------------------------------------------------------------

class _PeopleTab extends StatefulWidget {
  final Performa performa;
  final void Function(Performa) onSave;
  const _PeopleTab({required this.performa, required this.onSave});
  @override
  State<_PeopleTab> createState() => _PeopleTabState();
}

class _PeopleTabState extends State<_PeopleTab> {
  late List<PerformaContact> _contacts;
  late List<String> _keywords;

  @override
  void initState() {
    super.initState();
    _contacts = List.from(widget.performa.recurringContacts);
    _keywords = List.from(widget.performa.customKeywords);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Key People', style: Theme.of(context).textTheme.titleMedium),
          IconButton(icon: const Icon(Icons.person_add), onPressed: _addContact),
        ]),
        ..._contacts.asMap().entries.map((e) => _contactCard(e.key, e.value)),
        const Divider(height: 32),
        Text('Watch Keywords', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            ..._keywords.map((k) => Chip(
              label: Text(k),
              onDeleted: () => setState(() {
                _keywords.remove(k);
                _save();
              }),
            )),
            ActionChip(
              label: const Text('+'),
              onPressed: _addKeyword,
            ),
          ],
        ),
      ]),
    );
  }

  Widget _contactCard(int idx, PerformaContact c) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      title: Text(c.name),
      subtitle: Text('${c.relationship}${c.notes.isNotEmpty ? " · ${c.notes}" : ""}'),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () => _editContact(idx, c)),
        IconButton(icon: const Icon(Icons.delete, size: 18), onPressed: () => setState(() {
          _contacts.removeAt(idx);
          _save();
        })),
      ]),
    ),
  );

  void _addContact() => _editContact(null, null);

  void _editContact(int? idx, PerformaContact? existing) {
    final namec = TextEditingController(text: existing?.name ?? '');
    final relc = TextEditingController(text: existing?.relationship ?? '');
    final notec = TextEditingController(text: existing?.notes ?? '');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(existing == null ? 'Add Contact' : 'Edit Contact'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: namec, decoration: const InputDecoration(labelText: 'Name'), autofocus: true),
          TextField(controller: relc, decoration: const InputDecoration(labelText: 'Relationship')),
          TextField(controller: notec, decoration: const InputDecoration(labelText: 'Notes')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final contact = PerformaContact(
                name: namec.text.trim(),
                relationship: relc.text.trim(),
                notes: notec.text.trim(),
              );
              setState(() {
                if (idx != null) _contacts[idx] = contact;
                else _contacts.add(contact);
              });
              _save();
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _addKeyword() {
    final c = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add Keyword'),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final v = c.text.trim();
              if (v.isNotEmpty) setState(() { _keywords.add(v); _save(); });
              Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _save() => widget.onSave(widget.performa.copyWith(
    recurringContacts: _contacts,
    customKeywords: _keywords,
  ));
}

// -- Tab 3: AI Insights -------------------------------------------------------

class _InsightsTab extends StatelessWidget {
  final Performa performa;
  const _InsightsTab({required this.performa});

  @override
  Widget build(BuildContext context) {
    final insights = performa.aiInsights.where((i) => i.approved).toList();
    if (insights.isEmpty) {
      return const Center(child: Text('No AI insights yet. Complete a few sessions to see patterns.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: insights.length,
      itemBuilder: (ctx, i) {
        final insight = insights[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(insight.text, style: Theme.of(ctx).textTheme.bodyMedium),
              const SizedBox(height: 6),
              LinearProgressIndicator(value: insight.confidence, minHeight: 3),
              const SizedBox(height: 4),
              Text('${(insight.confidence * 100).round()}% confidence',
                  style: Theme.of(ctx).textTheme.labelSmall),
            ]),
          ),
        );
      },
    );
  }
}

// -- Tab 4: Export ------------------------------------------------------------

class _ExportTab extends StatelessWidget {
  final Performa performa;
  const _ExportTab({required this.performa});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Export your Performa profile', style: TextStyle(fontSize: 16)),
        const SizedBox(height: 24),
        _exportButton(context, Icons.code, 'Export JSON', _doJson),
        const SizedBox(height: 12),
        _exportButton(context, Icons.description, 'Export Markdown', _doMarkdown),
        const SizedBox(height: 12),
        _exportButton(context, Icons.picture_as_pdf, 'Export PDF', _doPdf),
      ]),
    );
  }

  Widget _exportButton(BuildContext ctx, IconData icon, String label,
      Future<void> Function(BuildContext) action) => FilledButton.icon(
    icon: Icon(icon),
    label: Text(label),
    onPressed: () => action(ctx),
    style: FilledButton.styleFrom(minimumSize: const Size(200, 48)),
  );

  Future<void> _doJson(BuildContext ctx) async {
    try {
      final repo = ctx.read<PerformaRepository>();
      final file = await repo.exportJson(performa);
      await Share.shareXFiles([XFile(file.path)]);
    } catch (e) {
      _showError(ctx, e);
    }
  }

  Future<void> _doMarkdown(BuildContext ctx) async {
    try {
      final repo = ctx.read<PerformaRepository>();
      final file = await repo.exportMarkdown(performa);
      await Share.shareXFiles([XFile(file.path)]);
    } catch (e) {
      _showError(ctx, e);
    }
  }

  Future<void> _doPdf(BuildContext ctx) async {
    try {
      final repo = ctx.read<PerformaRepository>();
      final file = await repo.exportPdf(performa);
      await Share.shareXFiles([XFile(file.path)]);
    } catch (e) {
      _showError(ctx, e);
    }
  }

  void _showError(BuildContext ctx, Object e) =>
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Export failed: $e')));
}
