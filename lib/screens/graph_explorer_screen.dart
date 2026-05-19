import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/connection_service.dart';
import '../repositories/graph_repository.dart';
import '../widgets/animated_background.dart';
import '../widgets/skeleton_loader.dart';
import '../theme/design_tokens.dart';

import '../widgets/app_snack_bar.dart';
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
  String? _currentGraphSessionId;

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final js = 'updateGraph(`$nodesStr`, `$edgesStr`, ${isDark ? 'true' : 'false'});';
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

  /// Stop-words filtered from queries before matching.
  static const _stopWords = {
    'the','a','an','is','are','was','were','be','been','being','of','in','on',
    'at','to','for','with','by','from','as','that','this','these','those','it',
    'its','his','her','their','my','our','your','and','or','but','not','no','do',
    'does','did','have','has','had','can','could','should','would','will','what',
    'when','where','why','how','who','whom','which','about','tell','me','show',
    'find','list','give','say','says','said','please',
  };

  /// Tokenize a query into normalised, deduplicated content words.
  Set<String> _tokenize(String query) => query
      .toLowerCase()
      .split(RegExp(r"[^a-z0-9']+"))
      .where((w) => w.length > 2 && !_stopWords.contains(w))
      .toSet();

  /// Scaled Levenshtein-lite similarity for short tokens. Returns 0..1 where
  /// 1 == exact match. Avoids full DP cost: prefix + length-difference heuristic.
  double _tokenSimilarity(String a, String b) {
    if (a == b) return 1.0;
    if (a.contains(b) || b.contains(a)) return 0.85;
    final maxLen = a.length > b.length ? a.length : b.length;
    final minLen = a.length > b.length ? b.length : a.length;
    if (maxLen - minLen > 3) return 0.0;
    int common = 0;
    for (int i = 0; i < minLen; i++) {
      if (a.codeUnitAt(i) == b.codeUnitAt(i)) common++ ; else break;
    }
    if (common >= 3) return common / maxLen;
    return 0.0;
  }

  /// Extract graph entities relevant to [query], plus their immediate neighbours
  /// so the LLM can answer relationship questions ("who works with X?").
  /// Returns up to 25 entities scored on label match, type match, and adjacency.
  List<Map<String, dynamic>> _extractGraphEntities(String query) {
    if (_rawNodes.isEmpty) return [];
    final tokens = _tokenize(query);
    if (tokens.isEmpty) {
      // Fall back to top-mentioned nodes when the question has no content words.
      final fallback = [..._rawNodes]
        ..sort((a, b) {
          int mc(Map m) => (m['mention_count'] is int)
              ? m['mention_count'] as int
              : int.tryParse('${m['mention_count']}') ?? 0;
          return mc(b).compareTo(mc(a));
        });
      return fallback.take(15).map(_nodeSummary).toList();
    }

    // Score every node on label/type fuzzy match.
    final Map<String, double> scoreById = {};
    for (final n in _rawNodes) {
      final id = n['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final label = (n['label']?.toString() ?? '').toLowerCase();
      final type = ((n['type'] ?? n['entity_type'])?.toString() ?? '').toLowerCase();
      double score = 0;
      for (final t in tokens) {
        // Type-keyword bonus ("event", "person") boosts every node of that type.
        if (t == type) score += 0.6;
        // Direct label hits weighted higher than fuzzy ones.
        for (final lw in label.split(RegExp(r"\s+"))) {
          if (lw.isEmpty) continue;
          final sim = _tokenSimilarity(t, lw);
          if (sim > 0) score += sim;
        }
        // Whole-label substring catches multi-word entities ("john doe").
        if (label.contains(t)) score += 0.5;
      }
      if (score > 0) scoreById[id] = score;
    }

    if (scoreById.isEmpty) return [];

    // Promote neighbours of top hits so the model can answer relationship Qs.
    final topIds = (scoreById.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(5)
        .map((e) => e.key)
        .toSet();
    for (final link in _rawLinks) {
      final src = link['source']?.toString() ?? '';
      final tgt = link['target']?.toString() ?? '';
      if (topIds.contains(src) && !scoreById.containsKey(tgt)) {
        scoreById[tgt] = 0.25;
      } else if (topIds.contains(tgt) && !scoreById.containsKey(src)) {
        scoreById[src] = 0.25;
      }
    }

    final ranked = scoreById.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final byId = {for (final n in _rawNodes) (n['id']?.toString() ?? ''): n};
    return ranked.take(25).map((entry) {
      final n = byId[entry.key]!;
      final summary = _nodeSummary(n);
      summary['relevance'] = double.parse(entry.value.toStringAsFixed(3));
      return summary;
    }).toList();
  }

  Map<String, dynamic> _nodeSummary(Map<String, dynamic> n) => {
        'id': n['id']?.toString() ?? '',
        'label': n['label']?.toString() ?? '',
        'type': (n['type'] ?? n['entity_type'])?.toString() ?? '',
        if (n['mention_count'] != null) 'mention_count': n['mention_count'],
      };

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

    // 2. No entity match → natural language question; extract relevant entities first
    final userId = AuthService.instance.currentUser?.id ?? '';
    if (userId.isEmpty) return;

    final graphEntities = _extractGraphEntities(query);

    setState(() => _graphQueryLoading = true);
    _graphQueryController.clear();
    FocusScope.of(context).unfocus();

    try {
      final api = context.read<ApiService>();
      final result = await api.askGraphQuery(
        userId,
        query,
        sessionId: _currentGraphSessionId,
        graphEntities: graphEntities,
      );
      final answer = result['answer'] as String;
      final sid = result['session_id'] as String?;

      if (!mounted) return;
      setState(() {
        _graphQueryLoading = false;
        if (sid != null) _currentGraphSessionId = sid;
      });

      final isDark = Theme.of(context).brightness == Brightness.dark;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _GraphQueryResultSheet(
          initialQuery: query,
          initialAnswer: answer,
          sessionId: _currentGraphSessionId,
          userId: userId,
          api: api,
          isDark: isDark,
          graphEntities: graphEntities,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _graphQueryLoading = false);
      AppSnackBar.show(context, message: 'Could not get an answer: $e');
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
                      color: cs.onSurface.withValues(alpha: 0.6),
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
                        size: 64, color: cs.onSurface.withValues(alpha: 0.3)),
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage ?? 'Your knowledge graph is empty. Start a session to build your memory.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.6)),
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
        color: cs.surfaceContainerHigh.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
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
                        color: cs.onSurface.withValues(alpha: 0.8))),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Graph Query Bar ────────────────────────────────────────────────────────────

class _GraphQueryBar extends StatefulWidget {
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
  State<_GraphQueryBar> createState() => _GraphQueryBarState();
}

class _GraphQueryBarState extends State<_GraphQueryBar> {
  final FocusNode _focusNode = FocusNode();
  bool _hasFocus = false;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (mounted) setState(() => _hasFocus = _focusNode.hasFocus);
    });
    widget.controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final hasText = widget.controller.text.trim().isNotEmpty;
    if (hasText != _hasText && mounted) {
      setState(() => _hasText = hasText);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = widget.isDark;
    final accent = cs.primary;
    final canSubmit = _hasText && !widget.isLoading;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          if (_hasFocus)
            BoxShadow(
              color: accent.withAlpha(50),
              blurRadius: 20,
              spreadRadius: -4,
              offset: const Offset(0, 4),
            )
          else
            BoxShadow(
              color: Colors.black.withAlpha(isDark ? 50 : 16),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withAlpha(_hasFocus ? 20 : 12)
                  : Colors.white.withAlpha(_hasFocus ? 245 : 225),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: _hasFocus
                    ? accent.withAlpha(180)
                    : (isDark
                        ? Colors.white.withAlpha(28)
                        : AppColors.slate200.withAlpha(180)),
                width: _hasFocus ? 1.4 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: _hasFocus
                      ? accent
                      : (isDark ? AppColors.slate400 : AppColors.slate500),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    focusNode: _focusNode,
                    style: GoogleFonts.manrope(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white : AppColors.slate900,
                    ),
                    cursorColor: accent,
                    cursorRadius: const Radius.circular(2),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      border: InputBorder.none,
                      hintText: 'Search or ask your graph…',
                      hintStyle: GoogleFonts.manrope(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w400,
                        color: isDark ? AppColors.slate500 : AppColors.slate400,
                      ),
                    ),
                    onSubmitted: (_) => widget.onSubmit(),
                    textInputAction: TextInputAction.search,
                  ),
                ),
                if (_hasText && !widget.isLoading)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    splashRadius: 20,
                    onPressed: () => widget.controller.clear(),
                    icon: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: isDark ? AppColors.slate400 : AppColors.slate500,
                    ),
                  ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(left: 6),
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: canSubmit
                          ? [accent, accent.withAlpha(190)]
                          : [
                              (isDark ? AppColors.slate700 : AppColors.slate200),
                              (isDark ? AppColors.slate800 : AppColors.slate200),
                            ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: canSubmit ? widget.onSubmit : null,
                      child: Center(
                        child: widget.isLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation(Colors.white),
                                ),
                              )
                            : Icon(
                                Icons.arrow_upward_rounded,
                                size: 18,
                                color: canSubmit
                                    ? Colors.white
                                    : (isDark ? AppColors.slate500 : AppColors.slate400),
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Graph Query Result Sheet ───────────────────────────────────────────────────

class _GraphQueryResultSheet extends StatefulWidget {
  final String initialQuery;
  final String initialAnswer;
  final String? sessionId;
  final String userId;
  final ApiService api;
  final bool isDark;
  final List<Map<String, dynamic>> graphEntities;

  const _GraphQueryResultSheet({
    required this.initialQuery,
    required this.initialAnswer,
    this.sessionId,
    required this.userId,
    required this.api,
    required this.isDark,
    this.graphEntities = const [],
  });

  @override
  State<_GraphQueryResultSheet> createState() => _GraphQueryResultSheetState();
}

class _GraphQueryResultSheetState extends State<_GraphQueryResultSheet> {
  late List<Map<String, String>> _messages;
  final TextEditingController _followUpController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _loading = false;
  String? _sessionId;

  @override
  void initState() {
    super.initState();
    _sessionId = widget.sessionId;
    _messages = [
      {'role': 'user', 'content': widget.initialQuery},
      {'role': 'ai', 'content': widget.initialAnswer},
    ];
  }

  @override
  void dispose() {
    _followUpController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _submitFollowUp() async {
    final text = _followUpController.text.trim();
    if (text.isEmpty || _loading) return;

    setState(() {
      _messages.add({'role': 'user', 'content': text});
      _loading = true;
      _followUpController.clear();
    });
    _scrollToBottom();

    try {
      final result = await widget.api.askGraphQuery(
        widget.userId,
        text,
        sessionId: _sessionId,
        graphEntities: widget.graphEntities,
      );

      if (!mounted) return;
      setState(() {
        _messages.add({'role': 'ai', 'content': result['answer'] as String});
        if (result['session_id'] != null) _sessionId = result['session_id'] as String;
        _loading = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add({'role': 'ai', 'content': 'Sorry, I couldn\'t get an answer: $e'});
        _loading = false;
      });
      _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (_, scrollController) => Container(
        margin: EdgeInsets.fromLTRB(12, 0, 12, 12 + bottomInset),
        decoration: BoxDecoration(
          color: widget.isDark
              ? const Color(0xFF0F172A).withValues(alpha: 0.98)
              : Colors.white.withValues(alpha: 0.98),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: cs.primary.withValues(alpha: 0.2), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: widget.isDark ? Colors.white24 : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome, color: cs.primary, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    'Graph Insights',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: widget.isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                    color: widget.isDark ? Colors.white54 : Colors.black54,
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 0.5),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                itemCount: _messages.length,
                itemBuilder: (ctx, index) {
                  final msg = _messages[index];
                  final isUser = msg['role'] == 'user';
                  return Align(
                    alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: isUser
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        if (isUser)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4, right: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.account_tree_rounded,
                                    size: 10,
                                    color: cs.primary.withValues(alpha: 0.7)),
                                const SizedBox(width: 3),
                                Text(
                                  'Asked on Graph Screen',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: cs.primary.withValues(alpha: 0.7),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(14),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.75,
                          ),
                          decoration: BoxDecoration(
                            color: isUser
                                ? cs.primary
                                : (widget.isDark
                                    ? const Color(0xFF1E293B)
                                    : const Color(0xFFF1F5F9)),
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(16),
                              topRight: const Radius.circular(16),
                              bottomLeft: Radius.circular(isUser ? 16 : 4),
                              bottomRight: Radius.circular(isUser ? 4 : 16),
                            ),
                          ),
                          child: Text(
                            msg['content']!,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.5,
                              color: isUser
                                  ? Colors.white
                                  : (widget.isDark
                                      ? Colors.white.withValues(alpha: 0.9)
                                      : const Color(0xFF334155)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            if (_loading)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.primary,
                    ),
                  ),
                ),
              ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.1))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: widget.isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: cs.primary.withValues(alpha: 0.1),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: _followUpController,
                        onSubmitted: (_) => _submitFollowUp(),
                        style: TextStyle(
                          fontSize: 14,
                          color: widget.isDark ? Colors.white : Colors.black87,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Ask a follow-up...',
                          border: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          enabledBorder: InputBorder.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _submitFollowUp,
                    icon: const Icon(Icons.send_rounded, size: 18),
                    style: IconButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: Colors.white,
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
              ? const Color(0xFF192B33).withValues(alpha: 0.97)
              : Colors.white.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: widget.color.withValues(alpha: 0.3)),
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
                    color: widget.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: widget.color.withValues(alpha: 0.3)),
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
                          color: widget.color.withValues(alpha: 0.15),
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
                  color: widget.color.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: widget.color.withValues(alpha: 0.12)),
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
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonLoader.line(width: 140),
                    SkeletonLoader.line(width: 200),
                    SkeletonLoader.line(width: 160),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cs.primary.withValues(alpha: 0.12)),
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
                side: BorderSide(color: cs.primary.withValues(alpha: 0.4)),
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
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color.withValues(alpha: 0.7)),
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
