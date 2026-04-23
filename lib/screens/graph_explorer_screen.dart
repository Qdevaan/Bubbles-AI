import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/connection_service.dart';
import '../repositories/graph_repository.dart';
import '../widgets/animated_background.dart';

Color _colorForType(String? type) {
  switch ((type ?? '').toLowerCase()) {
    case 'person':
      return const Color(0xFF6366F1);
    case 'organization':
      return const Color(0xFFF59E0B);
    case 'place':
      return const Color(0xFF10B981);
    case 'event':
      return const Color(0xFFEC4899);
    case 'concept':
      return const Color(0xFF8B5CF6);
    case 'object':
      return const Color(0xFF06B6D4);
    default:
      return const Color(0xFF64748B);
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

enum _ViewMode { flat, space3d }

// ─────────────────────────────────────────────────────────────────────────────

class GraphExplorerScreen extends StatefulWidget {
  const GraphExplorerScreen({super.key});

  @override
  State<GraphExplorerScreen> createState() => _GraphExplorerScreenState();
}

class _GraphExplorerScreenState extends State<GraphExplorerScreen>
    with TickerProviderStateMixin {
  GraphController<Node<Map<String, dynamic>>,
      Edge<Node<Map<String, dynamic>>, Map<String, dynamic>>>? _controller;
  bool _isLoading = true;
  String? _errorMessage;
  final Map<String, Node<Map<String, dynamic>>> _nodesMap = {};
  List<Map<String, dynamic>> _rawNodes = [];
  List<Map<String, dynamic>> _rawLinks = [];

  _ViewMode _viewMode = _ViewMode.flat;

  // ── Graph Query Engine ───────────────────────────────────────────────────
  final TextEditingController _graphQueryController = TextEditingController();
  bool _graphQueryLoading = false;

  // 3D rotation state
  double _rotX = 0.3;
  double _rotY = 0.0;
  bool _isDragging = false;
  late AnimationController _autoRotateCtrl;

  @override
  void initState() {
    super.initState();
    _autoRotateCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 40),
    )..repeat();
    _loadGraph();
  }

  @override
  void dispose() {
    _autoRotateCtrl.dispose();
    _graphQueryController.dispose();
    super.dispose();
  }

  Future<void> _loadGraph({bool swr = false}) async {
    setState(() {
      _isLoading = !swr;
      _errorMessage = null;
    });

    final userId = AuthService.instance.currentUser?.id ?? '';
    if (userId.isEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Please log in to view your knowledge graph.';
      });
      return;
    }

    try {
      final repo = context.read<GraphRepository>();
      final result = await repo.getGraphExport(userId, forceRefresh: !swr);
      final data = result.data;
      
      if (data == null) {
        if (swr) return; // Keep existing if SWR failed
        setState(() {
          _isLoading = false;
          _errorMessage = 'Could not load graph data.';
        });
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
        _rawNodes = nodesData.map((n) => Map<String, dynamic>.from(n)).toList();
        _rawLinks = linksData.map((l) => Map<String, dynamic>.from(l)).toList();
        _isLoading = false;
      });
    } catch (e) {
      if (swr) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load graph: $e';
      });
    }
  }

  void _onNodeLongPress(
      BuildContext context, Node<Map<String, dynamic>> node) {
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
            final nodeId = node.data['id']?.toString();
            _nodesMap.remove(nodeId);
            if (nodeId != null) {
              _rawNodes.removeWhere((n) => n['id'].toString() == nodeId);
            }
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

  // ── Node single-tap: entity quick reference ──────────────────────────────
  void _onNodeTap(BuildContext context, Node<Map<String, dynamic>> node) {
    final label = node.data['label'] as String? ?? node.data['id']?.toString() ?? 'Unknown';
    final entityType = node.data['type'] as String? ?? 'unknown';
    final color = _colorForType(entityType);
    final icon = _iconForType(entityType);
    final userId = AuthService.instance.currentUser?.id ?? '';
    final api = context.read<ApiService>();
    final isConnected = context.read<ConnectionService>().isConnected;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _EntityQuickReferenceSheet(
          label: label,
          entityType: entityType,
          color: color,
          icon: icon,
          userId: userId,
          api: api,
          isConnected: isConnected,
          onViewInEntities: () {
            Navigator.pop(ctx);
            Navigator.pushNamed(context, '/entities');
          },
        );
      },
    );
  }

  // ── Graph Query submission ────────────────────────────────────────────────
  Future<void> _submitGraphQuery() async {
    final query = _graphQueryController.text.trim();
    if (query.isEmpty) return;
    final userId = AuthService.instance.currentUser?.id ?? '';
    final api = context.read<ApiService>();
    final isConnected = context.read<ConnectionService>().isConnected;
    if (!isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connect to the server to query the graph.')),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _graphQueryLoading = true);
    final answer = await api.askGraphQuery(userId, query);
    if (!mounted) return;
    setState(() => _graphQueryLoading = false);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _GraphQueryResultSheet(query: query, answer: answer, isDark: isDark),
    );
  }

  Widget _buildNodeWidget(
      BuildContext context, Node<Map<String, dynamic>> node) {
    final label = node.data['label'] as String? ??
        node.data['id']?.toString() ??
        '?';
    final entityType = node.data['type'] as String?;
    final color = _colorForType(entityType);
    final icon = _iconForType(entityType);

    return GestureDetector(
      onTap: () => _onNodeTap(context, node),
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surface
                    .withOpacity(0.85),
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
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          title: const Text('Knowledge Graph'),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: Stack(
          children: [
            Positioned.fill(
                child: AnimatedAmbientBackground(isDark: isDark)),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.hub_rounded,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  )
                      .animate(onPlay: (c) => c.repeat())
                      .scale(
                        begin: const Offset(0.85, 0.85),
                        end: const Offset(1.15, 1.15),
                        duration: 900.ms,
                        curve: Curves.easeInOut,
                      )
                      .then()
                      .scale(
                        begin: const Offset(1.15, 1.15),
                        end: const Offset(0.85, 0.85),
                        duration: 900.ms,
                        curve: Curves.easeInOut,
                      ),
                  const SizedBox(height: 20),
                  Text(
                    'Loading your knowledge graph…',
                    style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null ||
        _controller == null ||
        _controller!.nodes.isEmpty) {
      return Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          title: const Text('Knowledge Graph'),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: Stack(
          children: [
            Positioned.fill(
                child: AnimatedAmbientBackground(isDark: isDark)),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.hub_outlined,
                        size: 64,
                        color: cs.onSurface.withOpacity(0.3)),
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage ?? 'Your knowledge graph is empty. Start a session to build your memory.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurface.withOpacity(0.6)),
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
          ],
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
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              color: _viewMode == _ViewMode.space3d
                  ? cs.primary.withOpacity(0.15)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: IconButton(
              icon: Icon(
                _viewMode == _ViewMode.space3d
                    ? Icons.view_in_ar_rounded
                    : Icons.bubble_chart_outlined,
              ),
              tooltip: _viewMode == _ViewMode.space3d
                  ? 'Switch to 2D layout'
                  : 'Switch to 3D space view',
              onPressed: () => setState(() {
                _viewMode = _viewMode == _ViewMode.flat
                    ? _ViewMode.space3d
                    : _ViewMode.flat;
              }),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Reload graph',
            onPressed: _loadGraph,
          ),
        ],
      ),
      body: Stack(
        children: [
          // Ambient animated background
          Positioned.fill(
              child: AnimatedAmbientBackground(isDark: isDark)),

          // Graph content — switches between 2D and 3D
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: _viewMode == _ViewMode.flat
                ? _buildFlatView(cs)
                : _build3DView(isDark),
          ),

          // Legend overlay
          Positioned(
            bottom: 24,
            right: 16,
            child:
                _EntityTypeLegend().animate().fadeIn(delay: 400.ms),
          ),

          // ── Floating Graph Query Bar ──────────────────────────────────────
          Positioned(
            top: 10,
            left: 16,
            right: 16,
            child: _GraphQueryBar(
              controller: _graphQueryController,
              isLoading: _graphQueryLoading,
              onSubmit: _submitGraphQuery,
              isDark: isDark,
            ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.3, end: 0),
          ),

          // 3D drag hint
          if (_viewMode == _ViewMode.space3d)
            Positioned(
              bottom: 24,
              left: 16,
              child: _DragHintBadge()
                  .animate()
                  .fadeIn(delay: 600.ms),
            ),
        ],
      ),
    );
  }

  Widget _buildFlatView(ColorScheme cs) {
    return GraphView<Node<Map<String, dynamic>>,
        Edge<Node<Map<String, dynamic>>, Map<String, dynamic>>>(
      key: const ValueKey('flat'),
      controller: _controller!,
      canvasSize: const GraphCanvasSize.proportional(2.0),
      layoutAlgorithm: const FruchtermanReingoldAlgorithm(
        iterations: 200,
        optimalDistance: 120,
      ),
      nodeBuilder: (context, node) {
        final idx = _rawNodes.indexWhere(
            (n) => n['id'].toString() == node.data['id']?.toString());
        final delay =
            Duration(milliseconds: 80 + (idx.clamp(0, 60) * 25));
        return _buildNodeWidget(context, node)
            .animate()
            .fadeIn(delay: delay, duration: 300.ms)
            .scale(
              begin: const Offset(0.4, 0.4),
              delay: delay,
              duration: 300.ms,
              curve: Curves.easeOutBack,
            );
      },
      edgePainter: LineEdgePainter(
        color: cs.onSurface.withOpacity(0.2),
      ),
      labelBuilder: BottomLabelBuilder(
        labelSize: const Size(0, 0),
        builder: (context, node) => const SizedBox(),
      ),
    );
  }

  Widget _build3DView(bool isDark) {
    return GestureDetector(
      key: const ValueKey('3d'),
      onPanStart: (_) => setState(() => _isDragging = true),
      onPanEnd: (_) => setState(() => _isDragging = false),
      onPanCancel: () => setState(() => _isDragging = false),
      onPanUpdate: (d) => setState(() {
        _rotY += d.delta.dx * 0.006;
        _rotX += d.delta.dy * 0.006;
        _rotX = _rotX.clamp(-pi / 2.2, pi / 2.2);
      }),
      child: AnimatedBuilder(
        animation: _autoRotateCtrl,
        builder: (context, _) {
          final autoRotY = _isDragging
              ? _rotY
              : _rotY + _autoRotateCtrl.value * 2 * pi * 0.25;
          return CustomPaint(
            painter: _Graph3DPainter(
              nodes: _rawNodes,
              links: _rawLinks,
              rotX: _rotX,
              rotY: autoRotY,
              isDark: isDark,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

// ── 3D Graph CustomPainter ─────────────────────────────────────────────────────

class _Graph3DPainter extends CustomPainter {
  final List<Map<String, dynamic>> nodes;
  final List<Map<String, dynamic>> links;
  final double rotX;
  final double rotY;
  final bool isDark;

  const _Graph3DPainter({
    required this.nodes,
    required this.links,
    required this.rotX,
    required this.rotY,
    required this.isDark,
  });

  // Fibonacci sphere — evenly distributes N points on a unit sphere surface
  static List<(double, double, double)> _fibonacciSphere(int n) {
    if (n <= 0) return [];
    if (n == 1) return [(0, 0, 1)];
    final pts = <(double, double, double)>[];
    const phi = pi * (3.0 - 2.2360679774997896); // pi*(3-sqrt(5))
    for (int i = 0; i < n; i++) {
      final y = 1.0 - (i / (n - 1.0)) * 2.0;
      final r = sqrt(max(0.0, 1.0 - y * y));
      final theta = phi * i;
      pts.add((cos(theta) * r, y, sin(theta) * r));
    }
    return pts;
  }

  (double, double, double) _rotate(double x, double y, double z) {
    // Rotate around X
    final y1 = y * cos(rotX) - z * sin(rotX);
    final z1 = y * sin(rotX) + z * cos(rotX);
    // Rotate around Y
    final x2 = x * cos(rotY) + z1 * sin(rotY);
    final z2 = -x * sin(rotY) + z1 * cos(rotY);
    return (x2, y1, z2);
  }

  Offset _project(
      double x, double y, double z, double cx, double cy, double r) {
    const fov = 2.5;
    final s = fov / (fov + z);
    return Offset(cx + x * s * r, cy + y * s * r);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (nodes.isEmpty) return;

    final cx = size.width / 2;
    final cy = size.height / 2;
    final sphereR = min(size.width, size.height) * 0.38;

    final basePos = _fibonacciSphere(nodes.length);

    // Build projected positions and depth per node
    final projected = <String, Offset>{};
    final depths = <String, double>{};

    for (int i = 0; i < nodes.length; i++) {
      final id = nodes[i]['id'].toString();
      final (bx, by, bz) = basePos[i];
      final (rx, ry, rz) = _rotate(bx, by, bz);
      projected[id] = _project(rx, ry, rz, cx, cy, sphereR);
      depths[id] = rz;
    }

    // Draw edges (sorted back-to-front by average depth)
    final sortedLinks = [...links]
      ..sort((a, b) {
        final az = (depths[a['source'].toString()] ?? 0) +
            (depths[a['target'].toString()] ?? 0);
        final bz = (depths[b['source'].toString()] ?? 0) +
            (depths[b['target'].toString()] ?? 0);
        return az.compareTo(bz);
      });

    final edgePaint = Paint()..style = PaintingStyle.stroke;

    for (final link in sortedLinks) {
      final srcId = link['source'].toString();
      final dstId = link['target'].toString();
      final src = projected[srcId];
      final dst = projected[dstId];
      if (src == null || dst == null) continue;

      final avgZ =
          ((depths[srcId] ?? 0) + (depths[dstId] ?? 0)) / 2;
      // Map depth (-1..1) to opacity
      final opacity =
          ((avgZ + 1) / 2 * 0.45 + 0.05).clamp(0.04, 0.5);
      edgePaint
        ..color =
            (isDark ? Colors.white : Colors.black87).withOpacity(opacity)
        ..strokeWidth = 0.8 + opacity;
      canvas.drawLine(src, dst, edgePaint);
    }

    // Draw nodes sorted back-to-front
    final sortedIdx = List.generate(nodes.length, (i) => i)
      ..sort((a, b) => (depths[nodes[a]['id'].toString()] ?? 0)
          .compareTo(depths[nodes[b]['id'].toString()] ?? 0));

    for (final i in sortedIdx) {
      final node = nodes[i];
      final id = node['id'].toString();
      final pt = projected[id]!;
      final depth = depths[id]!;
      final color = _colorForType(node['type'] as String?);

      // Perspective scale: far nodes smaller
      final scale = ((depth + 2.5) / 3.5).clamp(0.4, 1.0);
      final radius = 16.0 * scale;

      // Glow halo
      canvas.drawCircle(
        pt,
        radius * 1.7,
        Paint()
          ..color = color.withOpacity(0.18 * scale)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );

      // Fill
      canvas.drawCircle(
        pt,
        radius,
        Paint()..color = color.withOpacity(0.15 + 0.12 * scale),
      );

      // Border ring
      canvas.drawCircle(
        pt,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = color.withOpacity(0.6 + 0.4 * scale)
          ..strokeWidth = 1.5 * scale,
      );

      // Label — only for nodes in front half
      if (depth > -0.15) {
        final raw =
            node['label'] as String? ?? id;
        final lbl = raw.length > 13 ? '${raw.substring(0, 11)}…' : raw;
        final tp = TextPainter(
          text: TextSpan(
            text: lbl,
            style: TextStyle(
              fontSize: (9 * scale).clamp(7.0, 11.0),
              color: (isDark ? Colors.white : Colors.black87)
                  .withOpacity(0.45 + 0.55 * scale),
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 90);
        tp.paint(
            canvas, Offset(pt.dx - tp.width / 2, pt.dy + radius + 3));
      }
    }
  }

  @override
  bool shouldRepaint(_Graph3DPainter old) =>
      old.rotX != rotX ||
      old.rotY != rotY ||
      old.nodes != nodes ||
      old.links != links;
}

// ── Drag hint badge ────────────────────────────────────────────────────────────

class _DragHintBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh.withOpacity(0.88),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outline.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.touch_app_outlined,
              size: 14, color: cs.onSurface.withOpacity(0.6)),
          const SizedBox(width: 6),
          Text(
            'Drag to rotate',
            style: TextStyle(
                fontSize: 11, color: cs.onSurface.withOpacity(0.6)),
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
          Center(
            child: Container(
              width: 40,
              height: 4,
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
                child:
                    Icon(_iconForType(nodeType), color: color, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nodeLabel,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    Text(nodeType ?? 'Entity',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: color)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          ListTile(
            leading:
                Icon(Icons.delete_outline, color: theme.colorScheme.error),
            title: Text('Remove from graph view',
                style: TextStyle(color: theme.colorScheme.error)),
            subtitle: const Text(
                'Removes this node from the visual graph locally.'),
            contentPadding: EdgeInsets.zero,
            onTap: () {
              Navigator.pop(context);
              onDelete();
            },
          ),
          ListTile(
            leading: Icon(Icons.info_outline,
                color: cs.onSurface.withOpacity(0.6)),
            title: const Text('View details'),
            subtitle:
                const Text('Coming soon — entity deep-dive panel.'),
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
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle, color: color),
                ),
                const SizedBox(width: 8),
                Text(t.$2,
                    style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurface.withOpacity(0.8))),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Graph Query Bar ────────────────────────────────────────────────────────────

class _GraphQueryBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isLoading;
  final VoidCallback onSubmit;
  final bool isDark;

  const _GraphQueryBar({
    required this.controller,
    required this.isLoading,
    required this.onSubmit,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1A2632).withOpacity(0.92)
            : Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.primary.withOpacity(0.25), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withOpacity(0.12),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          Icon(Icons.search_rounded, size: 20, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
              decoration: InputDecoration(
                hintText: 'Ask anything about your graph…',
                hintStyle: TextStyle(
                  fontSize: 14,
                  color: isDark
                      ? Colors.white38
                      : const Color(0xFF94A3B8),
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onSubmitted: (_) => onSubmit(),
              textInputAction: TextInputAction.search,
            ),
          ),
          if (isLoading)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: cs.primary,
                ),
              ),
            )
          else
            GestureDetector(
              onTap: onSubmit,
              child: Container(
                margin: const EdgeInsets.only(right: 6),
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: cs.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_forward_rounded,
                    color: Colors.white, size: 18),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Graph Query Result Sheet ───────────────────────────────────────────────────

class _GraphQueryResultSheet extends StatelessWidget {
  final String query;
  final String answer;
  final bool isDark;

  const _GraphQueryResultSheet({
    required this.query,
    required this.answer,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      maxChildSize: 0.9,
      minChildSize: 0.3,
      builder: (_, scrollController) => Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF111827).withOpacity(0.97)
              : Colors.white.withOpacity(0.97),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: cs.primary.withOpacity(0.2)),
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cs.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.search_rounded, color: cs.primary, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    query,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cs.primary.withOpacity(0.15)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.psychology_rounded, color: cs.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      answer,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.6,
                        color: isDark ? Colors.white70 : const Color(0xFF334155),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Dismiss', style: TextStyle(color: cs.primary)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Entity Quick Reference Sheet ───────────────────────────────────────────────

class _EntityQuickReferenceSheet extends StatefulWidget {
  final String label;
  final String entityType;
  final Color color;
  final IconData icon;
  final String userId;
  final ApiService api;
  final bool isConnected;
  final VoidCallback onViewInEntities;

  const _EntityQuickReferenceSheet({
    required this.label,
    required this.entityType,
    required this.color,
    required this.icon,
    required this.userId,
    required this.api,
    required this.isConnected,
    required this.onViewInEntities,
  });

  @override
  State<_EntityQuickReferenceSheet> createState() =>
      _EntityQuickReferenceSheetState();
}

class _EntityQuickReferenceSheetState
    extends State<_EntityQuickReferenceSheet> {
  String? _answer;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    if (!widget.isConnected) {
      setState(() {
        _answer = 'Connect to the server to get an AI summary.';
        _loading = false;
      });
      return;
    }
    final result = await widget.api.askAboutEntity(widget.userId, widget.label);
    if (mounted) setState(() { _answer = result; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.45,
      maxChildSize: 0.85,
      minChildSize: 0.25,
      builder: (_, scrollController) => Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF111827).withOpacity(0.97)
              : Colors.white.withOpacity(0.97),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: widget.color.withOpacity(0.3)),
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: widget.color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(widget.icon, color: widget.color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.label,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        widget.entityType.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: widget.color,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_loading)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: CircularProgressIndicator(color: widget.color),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: widget.color.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: widget.color.withOpacity(0.15)),
                ),
                child: Text(
                  _answer ?? '—',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: isDark ? Colors.white70 : const Color(0xFF334155),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: widget.onViewInEntities,
              icon: Icon(Icons.open_in_new_rounded, size: 16, color: cs.primary),
              label: Text('View in Entities', style: TextStyle(color: cs.primary)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: cs.primary.withOpacity(0.4)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
