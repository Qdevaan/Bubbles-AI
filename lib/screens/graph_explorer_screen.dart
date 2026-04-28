import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/connection_service.dart';
import '../repositories/graph_repository.dart';
import '../widgets/animated_background.dart';

Color _colorForType(String? type) {
  switch ((type ?? '').toLowerCase()) {
    case 'person': return const Color(0xFF6366F1);
    case 'organization': return const Color(0xFFF59E0B);
    case 'place': return const Color(0xFF10B981);
    case 'event': return const Color(0xFFEC4899);
    case 'concept': return const Color(0xFF8B5CF6);
    case 'object': return const Color(0xFF06B6D4);
    default: return const Color(0xFF64748B);
  }
}

String _colorHexForType(String? type) {
  final c = _colorForType(type);
  return '#' + c.value.toRadixString(16).substring(2).padLeft(6, '0');
}

IconData _iconForType(String? type) {
  switch ((type ?? '').toLowerCase()) {
    case 'person': return Icons.person_outline;
    case 'organization': return Icons.business_outlined;
    case 'place': return Icons.place_outlined;
    case 'event': return Icons.event_outlined;
    case 'concept': return Icons.lightbulb_outline;
    case 'object': return Icons.category_outlined;
    default: return Icons.circle_outlined;
  }
}


class GraphExplorerScreen extends StatefulWidget {
  const GraphExplorerScreen({super.key});

  @override
  State<GraphExplorerScreen> createState() => _GraphExplorerScreenState();
}

class _GraphExplorerScreenState extends State<GraphExplorerScreen> {
  WebViewController? _webViewController;
  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _rawNodes = [];
  List<Map<String, dynamic>> _rawLinks = [];

  final TextEditingController _graphQueryController = TextEditingController();
  bool _graphQueryLoading = false;

  @override
  void initState() {
    super.initState();
    _initWebView();
    _loadGraph();
  }

  void _initWebView() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..addJavaScriptChannel(
        'GraphChannel',
        onMessageReceived: (JavaScriptMessage message) {
          try {
            final data = jsonDecode(message.message);
            if (data['action'] == 'ready') {
              _injectGraphData();
            } else if (data['action'] == 'nodeClick') {
              _onNodeTap(data);
            }
          } catch (e) {
            debugPrint('Error parsing webview message: $e');
          }
        },
      );
  }

  @override
  void dispose() {
    _graphQueryController.dispose();
    super.dispose();
  }

  void _injectGraphData() {
    if (_webViewController == null || _rawNodes.isEmpty) return;

    // Compute degree per node from links
    final degreeMap = <String, int>{};
    for (final n in _rawNodes) {
      degreeMap[n['id'].toString()] = 0;
    }
    for (final l in _rawLinks) {
      final from = l['source']?.toString() ?? '';
      final to = l['target']?.toString() ?? '';
      degreeMap[from] = (degreeMap[from] ?? 0) + 1;
      degreeMap[to] = (degreeMap[to] ?? 0) + 1;
    }

    final nodes = _rawNodes.map((n) {
      final id = n['id'].toString();
      return {
        'id': id,
        'label': n['label']?.toString() ?? id,
        'type': n['type']?.toString() ?? n['entity_type']?.toString() ?? '',
        'degree': degreeMap[id] ?? 0,
      };
    }).toList();

    final edges = _rawLinks.map((l) {
      return {
        'from': l['source'].toString(),
        'to': l['target'].toString(),
        'label': l['relation']?.toString() ?? l['label']?.toString() ?? '',
      };
    }).toList();

    final nodesStr = jsonEncode(nodes);
    final edgesStr = jsonEncode(edges);

    // Use backtick template literals for safe injection
    final js = 'updateGraph(`$nodesStr`, `$edgesStr`);';
    _webViewController!.runJavaScript(js).then((_) {
      // Check if we need to focus on a specific node
      final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      final focusId = args?['focusId']?.toString();
      if (focusId != null && focusId.isNotEmpty) {
        Future.delayed(const Duration(milliseconds: 1000), () {
          _webViewController?.runJavaScript("focusNode('$focusId');");
        });
      }
    });
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
        if (swr) return;
        setState(() {
          _isLoading = false;
          _errorMessage = 'Could not load graph data.';
        });
        return;
      }

      if (!mounted) return;

      final nodesData = data['nodes'] as List<dynamic>? ?? [];
      final linksData = data['links'] as List<dynamic>? ?? [];

      setState(() {
        _rawNodes = nodesData.map((n) => Map<String, dynamic>.from(n)).toList();
        _rawLinks = linksData.map((l) => Map<String, dynamic>.from(l)).toList();
        _isLoading = false;
      });

      _loadTemplate();
    } catch (e) {
      if (swr) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load graph: $e';
      });
    }
  }

  Future<void> _loadTemplate() async {
    final template = await rootBundle.loadString('assets/text/graph_template.html');
    _webViewController?.loadHtmlString(template);
  }

  void _onNodeTap(Map<String, dynamic> data) {
    final label = data['label']?.toString() ?? 'Unknown';
    final entityType = data['type']?.toString() ?? '';
    final typeLabel = data['typeLabel']?.toString() ?? entityType;
    final description = data['description']?.toString() ?? '';
    final degree = data['degree'] ?? 0;
    final mentionCount = data['mentionCount'] ?? 0;
    final connections = (data['connections'] as List<dynamic>?)?.map((c) => Map<String, dynamic>.from(c)).toList() ?? [];
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
          entityType: typeLabel.isNotEmpty ? typeLabel : entityType,
          description: description,
          degree: degree is int ? degree : int.tryParse(degree.toString()) ?? 0,
          mentionCount: mentionCount is int ? mentionCount : int.tryParse(mentionCount.toString()) ?? 0,
          connections: connections,
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

  Future<void> _submitGraphQuery() async {
    final query = _graphQueryController.text.trim();
    if (query.isEmpty) return;

    final queryLower = query.toLowerCase();

    // 1. Try to find a matching entity (case-insensitive)
    final match = _rawNodes.firstWhere(
      (n) => (n['label']?.toString().toLowerCase() ?? '').contains(queryLower),
      orElse: () => <String, dynamic>{},
    );

    if (match.isNotEmpty) {
      // Found an entity → focus the graph camera on it
      final id = match['id'].toString();
      _webViewController?.runJavaScript("focusNode('$id');");
      _graphQueryController.clear();
      FocusScope.of(context).unfocus();
      return;
    }

    // 2. No entity match → treat as a natural language question about the graph
    final userId = AuthService.instance.currentUser?.id ?? '';
    if (userId.isEmpty) return;

    setState(() => _graphQueryLoading = true);
    _graphQueryController.clear();
    FocusScope.of(context).unfocus();

    try {
      final api = context.read<ApiService>();
      final answer = await api.askGraphQuery(userId, query);

      if (!mounted) return;
      setState(() => _graphQueryLoading = false);

      final isDark = Theme.of(context).brightness == Brightness.dark;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _GraphQueryResultSheet(
          query: query,
          answer: answer,
          isDark: isDark,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _graphQueryLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not get an answer: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    if (_isLoading && _rawNodes.isEmpty) {
      return Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          title: const Text('Knowledge Graph'),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: Stack(
          children: [
            Positioned.fill(child: AnimatedAmbientBackground(isDark: isDark)),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.hub_rounded, size: 64, color: cs.primary)
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
                    'Loading your knowledge graph...',
                    style: TextStyle(
                      color: cs.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null || _rawNodes.isEmpty) {
      return Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          title: const Text('Knowledge Graph'),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: Stack(
          children: [
            Positioned.fill(child: AnimatedAmbientBackground(isDark: isDark)),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.hub_outlined,
                        size: 64, color: cs.onSurface.withOpacity(0.3)),
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage ?? 'Your knowledge graph is empty. Start a session to build your memory.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurface.withOpacity(0.6)),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => _loadGraph(),
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
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadGraph(swr: false),
            tooltip: 'Refresh Graph',
          ),
          const SizedBox(width: 8),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          Positioned.fill(child: AnimatedAmbientBackground(isDark: isDark)),
          
          if (_webViewController != null)
            Positioned.fill(
              child: WebViewWidget(controller: _webViewController!),
            ),
            
          Positioned(
            bottom: 24,
            right: 16,
            child: _EntityTypeLegend(),
          ),

          Positioned(
            top: kToolbarHeight + 40,
            left: 16,
            right: 16,
            child: _GraphQueryBar(
              controller: _graphQueryController,
              isLoading: _graphQueryLoading,
              onSubmit: _submitGraphQuery,
              isDark: isDark,
            ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.3, end: 0),
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
  final String description;
  final int degree;
  final int mentionCount;
  final List<Map<String, dynamic>> connections;
  final Color color;
  final IconData icon;
  final String userId;
  final ApiService api;
  final bool isConnected;
  final VoidCallback onViewInEntities;

  const _EntityQuickReferenceSheet({
    required this.label,
    required this.entityType,
    this.description = '',
    this.degree = 0,
    this.mentionCount = 0,
    this.connections = const [],
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
      initialChildSize: 0.5,
      maxChildSize: 0.88,
      minChildSize: 0.25,
      builder: (_, scrollController) => Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF192B33).withOpacity(0.97)
              : Colors.white.withOpacity(0.97),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: widget.color.withOpacity(0.3)),
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          children: [
            // Drag handle
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

            // Header: icon + name + type badge
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: widget.color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: widget.color.withOpacity(0.3)),
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
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: widget.color.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          widget.entityType.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: widget.color,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Stats row
            if (widget.degree > 0 || widget.mentionCount > 0) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  if (widget.degree > 0)
                    _StatChip(
                      icon: Icons.hub_rounded,
                      label: '${widget.degree} connections',
                      color: widget.color,
                      isDark: isDark,
                    ),
                  if (widget.degree > 0 && widget.mentionCount > 0)
                    const SizedBox(width: 8),
                  if (widget.mentionCount > 0)
                    _StatChip(
                      icon: Icons.chat_bubble_outline_rounded,
                      label: '${widget.mentionCount} mentions',
                      color: widget.color,
                      isDark: isDark,
                    ),
                ],
              ),
            ],

            // Description
            if (widget.description.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: widget.color.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: widget.color.withOpacity(0.12)),
                ),
                child: Text(
                  widget.description,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: isDark ? Colors.white70 : const Color(0xFF334155),
                  ),
                ),
              ),
            ],

            // Connections list
            if (widget.connections.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'CONNECTIONS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              ...widget.connections.take(8).map((conn) {
                final connType = conn['nodeType']?.toString() ?? '';
                final connColor = _colorForType(connType);
                final relation = conn['relation']?.toString() ?? '';
                final nodeLabel = conn['nodeLabel']?.toString() ?? '';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: connColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? Colors.white70 : const Color(0xFF334155),
                            ),
                            children: [
                              TextSpan(
                                text: nodeLabel,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              if (relation.isNotEmpty) ...[
                                TextSpan(
                                  text: '  ·  ',
                                  style: TextStyle(
                                    color: isDark ? Colors.white24 : Colors.grey,
                                  ),
                                ),
                                TextSpan(
                                  text: relation,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontStyle: FontStyle.italic,
                                    color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              if (widget.connections.length > 8)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '+${widget.connections.length - 8} more',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                    ),
                  ),
                ),
            ],

            // AI Summary
            const SizedBox(height: 16),
            Text(
              'AI SUMMARY',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            if (_loading)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: widget.color,
                    ),
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cs.primary.withOpacity(0.12)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.psychology_rounded, color: cs.primary, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _answer ?? '—',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.6,
                          color: isDark ? Colors.white70 : const Color(0xFF334155),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 14),
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

// ── Small stat chip ────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isDark;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color.withOpacity(0.7)),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white60 : const Color(0xFF475569),
            ),
          ),
        ],
      ),
    );
  }
}
