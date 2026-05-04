import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class TeleprompterPanel extends StatefulWidget {
  final List<String> hints;
  final double initialHeightFraction;
  final bool hasUncertainSpeaker;
  final VoidCallback? onClose;

  const TeleprompterPanel({
    super.key,
    required this.hints,
    this.initialHeightFraction = 0.38,
    this.hasUncertainSpeaker = false,
    this.onClose,
  });

  @override
  State<TeleprompterPanel> createState() => _TeleprompterPanelState();
}

enum _PanelSnap { compact, normal, expanded }

class _TeleprompterPanelState extends State<TeleprompterPanel> {
  static const _snaps = {
    _PanelSnap.compact: 0.22,
    _PanelSnap.normal: 0.38,
    _PanelSnap.expanded: 0.68,
  };

  _PanelSnap _snap = _PanelSnap.normal;
  double _currentFraction = 0.38;
  final ScrollController _scroll = ScrollController();
  bool _userScrolled = false;

  @override
  void initState() {
    super.initState();
    _currentFraction = widget.initialHeightFraction;
    _snap = _snapForFraction(_currentFraction);
    _scroll.addListener(() {
      if (_scroll.hasClients) {
        final atBottom = _scroll.offset >= _scroll.position.maxScrollExtent - 16;
        if (!atBottom && !_userScrolled) setState(() => _userScrolled = true);
        if (atBottom && _userScrolled) setState(() => _userScrolled = false);
      }
    });
  }

  @override
  void didUpdateWidget(TeleprompterPanel old) {
    super.didUpdateWidget(old);
    if (widget.hints.length > old.hints.length && !_userScrolled && _snap != _PanelSnap.compact) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients && _scroll.position.hasContentDimensions) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
        }
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  _PanelSnap _snapForFraction(double f) {
    if (f < 0.28) return _PanelSnap.compact;
    if (f < 0.52) return _PanelSnap.normal;
    return _PanelSnap.expanded;
  }

  void _cycleSnap() {
    setState(() {
      switch (_snap) {
        case _PanelSnap.compact: _snap = _PanelSnap.normal; break;
        case _PanelSnap.normal: _snap = _PanelSnap.expanded; break;
        case _PanelSnap.expanded: _snap = _PanelSnap.compact; break;
      }
      _currentFraction = _snaps[_snap]!;
    });
  }

  void _onDragStart(DragStartDetails _) {}

  void _onDragUpdate(DragUpdateDetails d) {
    final screenH = MediaQuery.of(context).size.height;
    setState(() {
      _currentFraction = (_currentFraction - d.delta.dy / screenH).clamp(0.18, 0.75);
    });
  }

  void _onDragEnd(DragEndDetails d) {
    final velocity = d.primaryVelocity ?? 0;
    final _PanelSnap target;
    if (velocity < -300) {
      target = _snap == _PanelSnap.compact ? _PanelSnap.normal : _PanelSnap.expanded;
    } else if (velocity > 300) {
      target = _snap == _PanelSnap.expanded ? _PanelSnap.normal : _PanelSnap.compact;
    } else {
      target = _snapForFraction(_currentFraction);
    }
    setState(() {
      _snap = target;
      _currentFraction = _snaps[target]!;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.hints.isEmpty) return const SizedBox.shrink();
    final screenH = MediaQuery.of(context).size.height;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panelH = screenH * _currentFraction;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      height: panelH,
      decoration: BoxDecoration(
        color: isDark
            ? Colors.black.withAlpha(180)
            : Colors.white.withAlpha(230),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: scheme.primary.withAlpha(60)),
        boxShadow: [BoxShadow(color: scheme.primary.withAlpha(30), blurRadius: 20, spreadRadius: 2)],
      ),
      child: Column(children: [
        _header(scheme),
        Expanded(child: _snap == _PanelSnap.compact ? _compactBody() : _scrollBody(isDark, scheme)),
      ]),
    );
  }

  Widget _header(ColorScheme scheme) {
    return GestureDetector(
      onDoubleTap: _cycleSnap,
      onVerticalDragStart: _onDragStart,
      onVerticalDragUpdate: _onDragUpdate,
      onVerticalDragEnd: _onDragEnd,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: scheme.primary.withAlpha(40),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('${widget.hints.length} hints',
                style: TextStyle(fontSize: 11, color: scheme.primary, fontWeight: FontWeight.w600)),
          ),
          const Spacer(),
          Container(width: 36, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2))),
          const Spacer(),
          if (widget.hasUncertainSpeaker)
            Container(
              width: 8, height: 8, margin: const EdgeInsets.only(right: 8),
              decoration: const BoxDecoration(color: Colors.amber, shape: BoxShape.circle),
            ).animate(onPlay: (c) => c.repeat()).shimmer(duration: const Duration(seconds: 1)),
          GestureDetector(
            onTap: _cycleSnap,
            child: Icon(
              _snap == _PanelSnap.expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
              size: 20, color: scheme.onSurface.withAlpha(150),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _compactBody() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(widget.hints.last,
          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500),
          maxLines: 3, overflow: TextOverflow.ellipsis),
    );
  }

  Widget _scrollBody(bool isDark, ColorScheme scheme) {
    return Stack(children: [
      ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        itemCount: widget.hints.length,
        itemBuilder: (ctx, i) {
          final isLatest = i == widget.hints.length - 1;
          return _HintEntry(
            hint: widget.hints[i],
            index: i + 1,
            isLatest: isLatest,
            isDark: isDark,
            scheme: scheme,
          );
        },
      ),
      if (_userScrolled)
        Positioned(
          bottom: 8, right: 12,
          child: FilledButton.icon(
            onPressed: () {
              setState(() => _userScrolled = false);
              _scroll.animateTo(_scroll.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
            },
            icon: const Icon(Icons.arrow_downward, size: 14),
            label: const Text('Latest', style: TextStyle(fontSize: 12)),
            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
        ),
    ]);
  }
}

class _HintEntry extends StatelessWidget {
  final String hint;
  final int index;
  final bool isLatest;
  final bool isDark;
  final ColorScheme scheme;

  const _HintEntry({
    required this.hint,
    required this.index,
    required this.isLatest,
    required this.isDark,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 20, height: 20, margin: const EdgeInsets.only(right: 8, top: 2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isLatest ? scheme.primary : scheme.primary.withAlpha(50),
          ),
          child: Center(child: Text('$index',
            style: TextStyle(fontSize: 10,
                color: isLatest ? Colors.white : scheme.primary,
                fontWeight: FontWeight.bold))),
        ),
        Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isLatest
                  ? (isDark ? scheme.primary.withAlpha(30) : scheme.primary.withAlpha(15))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: isLatest ? Border(left: BorderSide(color: scheme.primary, width: 2)) : null,
            ),
            child: Opacity(
              opacity: isLatest ? 1.0 : 0.75,
              child: Text(hint,
                  style: TextStyle(fontSize: isLatest ? 14.5 : 13, height: 1.4)),
            ),
          ),
        ),
      ]),
    ).animate().slideY(begin: 0.3, end: 0, duration: 250.ms).fadeIn(duration: 250.ms);
  }
}
