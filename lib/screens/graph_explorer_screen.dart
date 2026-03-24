import 'package:flutter/material.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';

class GraphExplorerScreen extends StatefulWidget {
  const GraphExplorerScreen({super.key});

  @override
  State<GraphExplorerScreen> createState() => _GraphExplorerScreenState();
}

class _GraphExplorerScreenState extends State<GraphExplorerScreen> {
  GraphController<Node<Map<String, dynamic>>, Edge<Node<Map<String, dynamic>>, Map<String, dynamic>>>? _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadGraph();
  }

  Future<void> _loadGraph() async {
    final apiService = context.read<ApiService>();
    final userId = AuthService.instance.currentUser?.id ?? '';
    if (userId.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    final data = await apiService.getGraphExport(userId);
    if (data != null && mounted) {
      final controller = GraphController<Node<Map<String, dynamic>>, Edge<Node<Map<String, dynamic>>, Map<String, dynamic>>>();

      final nodesData = data['nodes'] as List<dynamic>? ?? [];
      final linksData = data['links'] as List<dynamic>? ?? [];

      final nodesMap = <String, Node<Map<String, dynamic>>>{};

      controller.mutate((mutator) {
        for (final n in nodesData) {
          final id = n['id'].toString();
          final node = Node(data: Map<String, dynamic>.from(n), size: 40.0);
          nodesMap[id] = node;
          mutator.addNode(node);
        }

        for (final l in linksData) {
          final sourceId = l['source'].toString();
          final targetId = l['target'].toString();
          final relation = l['relation'] ?? l['label'] ?? '';

          final sourceNode = nodesMap[sourceId];
          final targetNode = nodesMap[targetId];

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
    } else {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_controller == null || _controller!.nodes.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Knowledge Graph')),
        body: const Center(child: Text('No graph data found.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Knowledge Graph')),
      body: GraphView<Node<Map<String, dynamic>>, Edge<Node<Map<String, dynamic>>, Map<String, dynamic>>>(
        controller: _controller!,
        canvasSize: const GraphCanvasSize.proportional(1.5),
        layoutAlgorithm: const FruchtermanReingoldAlgorithm(),
        nodeBuilder: (context, node) {
          return Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).primaryColor,
            ),
            padding: const EdgeInsets.all(8),
            child: Center(
              child: Text(
                node.data['id'] ?? '?',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 10),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          );
        },
        edgePainter: const LineEdgePainter(
          color: Colors.grey,
        ),
        labelBuilder: BottomLabelBuilder(
          labelSize: const Size(0, 0),
          builder: (context, node) => const SizedBox(),
        ),
      ),
    );
  }
}
