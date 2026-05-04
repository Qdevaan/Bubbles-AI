import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/performa.dart';
import '../providers/performa_provider.dart';

class PerformaApprovalSheet extends StatelessWidget {
  final List<PerformaInsight> insights;
  const PerformaApprovalSheet({super.key, required this.insights});

  static Future<void> showIfNeeded(BuildContext context) async {
    final prov = context.read<PerformaProvider>();
    final userId = Supabase.instance.client.auth.currentUser?.id ?? '';
    if (userId.isEmpty) return;

    await prov.load(userId);
    final pending = prov.performa?.pendingInsights ?? [];
    if (pending.isEmpty) return;

    if (context.mounted) {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => PerformaApprovalSheet(insights: pending),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.9,
      builder: (ctx, scroll) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)),
          )),
          const SizedBox(height: 16),
          Text('We learned a few things about you',
              style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Approve or dismiss each insight',
              style: Theme.of(ctx).textTheme.bodySmall),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.separated(
              controller: scroll,
              itemCount: insights.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) => _InsightRow(insight: insights[i]),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
            child: const Text('Done'),
          ),
        ]),
      ),
    );
  }
}

class _InsightRow extends StatelessWidget {
  final PerformaInsight insight;
  const _InsightRow({required this.insight});

  @override
  Widget build(BuildContext context) {
    final userId = Supabase.instance.client.auth.currentUser?.id ?? '';
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          Expanded(child: Text(insight.text, style: Theme.of(context).textTheme.bodyMedium)),
          IconButton(
            icon: const Icon(Icons.check_circle_outline, color: Colors.green),
            onPressed: () => context.read<PerformaProvider>().approveInsight(userId, insight.id),
          ),
          IconButton(
            icon: const Icon(Icons.cancel_outlined, color: Colors.red),
            onPressed: () => context.read<PerformaProvider>().rejectInsight(userId, insight.id),
          ),
        ]),
      ),
    );
  }
}
