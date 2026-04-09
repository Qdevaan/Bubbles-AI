import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';

/// Returns a color for a given entity type, matching the knowledge graph
/// taxonomy used by the server (person, place, organization, event, etc.)
Color _colorForType(String? type) {
  switch ((type ?? '').toLowerCase()) {
    case 'person':
      return const Color(0xFF6366F1); // indigo
    case 'organization':
      return const Color(0xFFF59E0B); // amber
    case 'place':
      return const Color(0xFF10B981); // emerald
    case 'event':
      return const Color(0xFFEC4899); // pink
    case 'concept':
      return const Color(0xFF8B5CF6); // violet
    case 'object':
      return const Color(0xFF06B6D4); // cyan
    default:
      return const Color(0xFF64748B); // slate
  }
}

IconData _iconForType(String? type) {
  switch ((type ?? '').toLowerCase()) {
    case 'person':
      return Icons.person_outline;
    case 'organization':
      return Icons.business_outlined;
    case 'place':
      return Icons.place_outlined;
    case 'event':
      return Icons.event_outlined;
    case 'concept':
      return Icons.lightbulb_outline;
    case 'object':
      return Icons.category_outlined;
    default:
      return Icons.circle_outlined;
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class GraphExplorerScreen extends StatefulWidget {
  const GraphExplorerScreen({super.key});

  @override
  State<GraphExplorerScreen> createState() => _GraphExplorerScreenState();
}

class _GraphExplorerScreenState extends State<GraphExplorerScreen> {
  GraphController<Node<Map<String, dynamic>>,
      Edge<Node<Map<String, dynamic>>, Map<String, dynamic>>>? _controller;
  bool _isLoading = true;
  String? _errorMessage;
  String? _selectedType; // for legend filter (future extension)

  // Track nodes separately so we can delete by id
  final Map<String, Node<Map<String, dynamic>>> _nodesMap = {};

  @override
  void initState() {
    super.initState();
    _loadGraph();
  }

  Future<void> _loadGraph() async {
    setState(() { _isLoading = true; _errorMessage = null; });

    final apiService = context.read<ApiService>();
    final userId = AuthService.instance.currentUser?.id ?? '';
    if (userId.isEmpty) {
      setState(() { _isLoading = false; _errorMessage = 'Please log in to view your knowledge graph.'; });
      return;
    }

    try {
      final data = await apiService.getGraphExport(userId);
      if (data == null) {
        setState(() { _isLoading = false; _errorMessage = 'No graph data yet. Start a session to build your memory.'; });
        return;
      }

      if (!mounted) return;

      final controller = GraphController<Node<Map<String, dynamic>>,
          Edge<Node<Map<String, dynamic>>, Map<String, dynamic>>>();

      final nodesData = data['nodes'] as List<dynamic>? ?? [];
      final linksData = data['links'] as List<dynamic>? ?? [];
      _nodesMap.clear();

      controller.mutate((mutator) {
        for (final n in nodesData) {
          final id = n['id'].toString();
          final node = Node(data: Map<String, dynamic>.from(n), size: 48.0);
          _nodesMap[id] = node;
          mutator.addNode(node);
        }

        for (final l in linksData) {
          final sourceId = l['source'].toString();
          final targetId = l['target'].toString();
          final relation = l['relation'] ?? l['label'] ?? '';
          final sourceNode = _nodesMap[sourceId];
          final targetNode = _nodesMap[targetId];
          if (sourceNode != null && targetNode != null) {
            mutator.addEdge(Edge(
              source: sourceNode,
              destination: targetNode,
              data: {'relation': relation},
            ));
          }
        }
      });

      setState(() {
        _controller = controller;
        _isLoading = false;
      });
    } catch (e) {
      setState(() { _isLoading = false; _errorMessage = 'Failed to load graph: $e'; });
    }
  }

  void _onNodeLongPress(
    BuildContext context,
    Node<Map<String, dynamic>> node,
  ) {
    final label = node.data['label'] as String? ??
        node.data['id']?.toString() ??
        'Unknown';
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _NodeActionSheet(
        nodeLabel: label,
        nodeType: node.data['type'] as String?,
        onDelete: () {
          try {
            _controller?.mutate((m) => m.removeNode(node));
            _nodesMap.remove(node.data['id']?.toString());
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Memory "$label" removed from local view.'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          } catch (e) {
            debugPrint('Node delete error: $e');
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Knowledge Graph'), backgroundColor: Colors.transparent, elevation: 0),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading your knowledge graph…'),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null || _controller == null || _controller!.nodes.isEmpty) {
      return Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(title: const Text('Knowledge Graph'), backgroundColor: Colors.transparent, elevation: 0),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.hub_outlined, size: 64, color: cs.onSurface.withOpacity(0.3)),
                const SizedBox(height: 16),
                Text(
                  _errorMessage ?? 'No graph data found.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurface.withOpacity(0.6)),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _loadGraph,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Knowledge Graph'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Reload graph',
            onPressed: _loadGraph,
          ),
        ],
      ),
      body: Stack(
        children: [
          // ── Graph view ────────────────────────────────────────────────────
          GraphView<Node<Map<String, dynamic>>,
              Edge<Node<Map<String, dynamic>>, Map<String, dynamic>>>(
            controller: _controller!,
            canvasSize: const GraphCanvasSize.proportional(2.0),
            layoutAlgorithm: const FruchtermanReingoldAlgorithm(
              iterations: 200,
              optimalDistance: 120,
            ),
            nodeBuilder: (context, node) {
              final label = node.data['label'] as String? ??
                  node.data['id']?.toString() ??
                  '?';
              final entityType = node.data['type'] as String?;
              final color = _colorForType(entityType);
              final icon = _iconForType(entityType);

              return GestureDetector(
                onLongPress: () => _onNodeLongPress(context, node),
                child: Tooltip(
                  message: '${entityType ?? 'unknown'}: $label',
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color.withOpacity(0.15),
                          border: Border.all(color: color, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: color.withOpacity(0.3),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Icon(icon, size: 20, color: color),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        constraints: const BoxConstraints(maxWidth: 80),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 9,
                            color: color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
            edgePainter: LineEdgePainter(
              color: cs.onSurface.withOpacity(0.2),
            ),
            labelBuilder: BottomLabelBuilder(
              labelSize: const Size(0, 0),
              builder: (context, node) => const SizedBox(),
            ),
          ),

          // ── Legend overlay ────────────────────────────────────────────────
          Positioned(
            bottom: 24,
            right: 16,
            child: _EntityTypeLegend().animate().fadeIn(delay: 400.ms),
          ),
        ],
      ),
    );
  }
}

// ── Node Action Bottom Sheet ───────────────────────────────────────────────────
class _NodeActionSheet extends StatelessWidget {
  final String nodeLabel;
  final String? nodeType;
  final VoidCallback onDelete;

  const _NodeActionSheet({
    required this.nodeLabel,
    required this.nodeType,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = _colorForType(nodeType);

    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: cs.onSurface.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withOpacity(0.1),
                  border: Border.all(color: color.withOpacity(0.4)),
                ),
                child: Icon(_iconForType(nodeType), color: color, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nodeLabel, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    Text(nodeType ?? 'Entity', style: theme.textTheme.bodySmall?.copyWith(color: color)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          ListTile(
            leading: Icon(Icons.delete_outline, color: theme.colorScheme.error),
            title: Text('Remove from graph view', style: TextStyle(color: theme.colorScheme.error)),
            subtitle: const Text('Removes this node from the visual graph locally.'),
            contentPadding: EdgeInsets.zero,
            onTap: () {
              Navigator.pop(context);
              onDelete();
            },
          ),
          ListTile(
            leading: Icon(Icons.info_outline, color: cs.onSurface.withOpacity(0.6)),
            title: const Text('View details'),
            subtitle: const Text('Coming soon — entity deep-dive panel.'),
            contentPadding: EdgeInsets.zero,
            enabled: false,
          ),
        ],
      ),
    );
  }
}

// ── Legend Widget ──────────────────────────────────────────────────────────────
class _EntityTypeLegend extends StatelessWidget {
  final _types = const [
    ('person', 'Person'),
    ('organization', 'Org'),
    ('place', 'Place'),
    ('event', 'Event'),
    ('concept', 'Concept'),
    ('object', 'Object'),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh.withOpacity(0.92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _types.map((t) {
          final color = _colorForType(t.$1);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10, height: 10,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: color),
                ),
                const SizedBox(width: 8),
                Text(t.$2, style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.8))),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
