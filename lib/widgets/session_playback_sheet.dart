import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/design_tokens.dart';

class SessionPlaybackSheet extends StatefulWidget {
  final String sessionId;
  final String audioPath;
  final String timingPath;

  const SessionPlaybackSheet({
    super.key,
    required this.sessionId,
    required this.audioPath,
    required this.timingPath,
  });

  static Future<void> show(
    BuildContext context, {
    required String sessionId,
    required String audioPath,
    required String timingPath,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SessionPlaybackSheet(
        sessionId: sessionId,
        audioPath: audioPath,
        timingPath: timingPath,
      ),
    );
  }

  @override
  State<SessionPlaybackSheet> createState() => _SessionPlaybackSheetState();
}

class _SessionPlaybackSheetState extends State<SessionPlaybackSheet> {
  final AudioPlayer _player = AudioPlayer();
  final ScrollController _scrollController = ScrollController();

  // Combined display lines: {role, text, start (nullable for LLM lines)}
  List<_PlaybackLine> _lines = [];
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  PlayerState _playerState = PlayerState.stopped;
  int _currentAudioIndex = -1; // index into audio-only lines for sync

  // Indices of audio-only lines within _lines (for position sync)
  final List<int> _audioLineIndices = [];

  @override
  void initState() {
    super.initState();
    _loadData();

    _player.onPositionChanged.listen((pos) {
      if (!mounted) return;
      final secs = pos.inMilliseconds / 1000.0;

      // Find which audio segment we're in
      int audioIdx = -1;
      for (int i = _audioLineIndices.length - 1; i >= 0; i--) {
        final li = _audioLineIndices[i];
        final start = _lines[li].start ?? 0.0;
        if (secs >= start) {
          audioIdx = i;
          break;
        }
      }

      if (mounted) {
        setState(() {
          _position = pos;
          if (audioIdx != _currentAudioIndex) {
            _currentAudioIndex = audioIdx;
            if (audioIdx >= 0) {
              _scrollToLine(_audioLineIndices[audioIdx]);
            }
          }
        });
      }
    });

    _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playerState = s);
    });
  }

  Future<void> _loadData() async {
    // Load timing JSON (audio timestamps by index)
    List<Map<String, dynamic>> timing = [];
    try {
      final content = await File(widget.timingPath).readAsString();
      final list = jsonDecode(content) as List;
      timing = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      debugPrint('Playback: failed to load timing: $e');
    }

    // Load session_logs from Supabase (correct roles + LLM responses)
    List<Map<String, dynamic>> dbLogs = [];
    try {
      final res = await Supabase.instance.client
          .from('session_logs')
          .select('role, content, turn_index')
          .eq('session_id', widget.sessionId)
          .order('turn_index', ascending: true);
      dbLogs = List<Map<String, dynamic>>.from(res as List);
    } catch (e) {
      debugPrint('Playback: failed to load session_logs: $e');
    }

    // Build display lines by merging DB logs with timing data.
    // Audio turns (user/others) get timestamps from timing[] by their
    // appearance order. LLM turns are inserted after their preceding others turn.
    final combined = <_PlaybackLine>[];
    final audioIndices = <int>[];

    int timingIdx = 0;
    for (final log in dbLogs) {
      final role = log['role'] as String? ?? '';
      final text = log['content'] as String? ?? '';
      if (text.isEmpty) continue;

      if (role == 'llm') {
        combined.add(_PlaybackLine(role: 'llm', text: text, start: null));
      } else {
        // user or others — pull next timing entry for start time
        double? start;
        if (timingIdx < timing.length) {
          start = (timing[timingIdx]['start'] as num?)?.toDouble();
          timingIdx++;
        }
        final idx = combined.length;
        combined.add(_PlaybackLine(role: role, text: text, start: start));
        audioIndices.add(idx);
      }
    }

    // Fallback: if DB had no logs, fall back to timing JSON alone
    if (combined.isEmpty && timing.isNotEmpty) {
      for (final t in timing) {
        final role = t['speaker'] as String? ?? 'others';
        final text = t['text'] as String? ?? '';
        final start = (t['start'] as num?)?.toDouble();
        final idx = combined.length;
        combined.add(_PlaybackLine(role: role, text: text, start: start));
        audioIndices.add(idx);
      }
    }

    if (mounted) {
      setState(() {
        _lines = combined;
        _audioLineIndices
          ..clear()
          ..addAll(audioIndices);
      });
    }
  }

  void _scrollToLine(int lineIdx) {
    if (!_scrollController.hasClients) return;
    const itemHeight = 76.0;
    final offset = (lineIdx * itemHeight) -
        (_scrollController.position.viewportDimension / 2) +
        itemHeight / 2;
    _scrollController.animateTo(
      offset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Future<void> _togglePlay() async {
    if (_playerState == PlayerState.playing) {
      await _player.pause();
    } else {
      if (_playerState == PlayerState.completed) {
        await _player.seek(Duration.zero);
      }
      await _player.play(DeviceFileSource(widget.audioPath));
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _player.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool _isCurrentLine(int i) {
    if (_currentAudioIndex < 0) return false;
    final audioLineIdx = _audioLineIndices[_currentAudioIndex];

    // Current audio line is highlighted; the LLM response right after it too
    if (i == audioLineIdx) return true;
    if (i > audioLineIdx &&
        _lines[i].role == 'llm' &&
        (i + 1 >= _lines.length ||
            _lines[i + 1].role != 'llm')) {
      // LLM line immediately following the current audio line
      // (between current and next audio line)
      final nextAudioIdx = _currentAudioIndex + 1 < _audioLineIndices.length
          ? _audioLineIndices[_currentAudioIndex + 1]
          : _lines.length;
      if (i < nextAudioIdx) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final h = MediaQuery.of(context).size.height * 0.82;

    return Container(
      height: h,
      decoration: BoxDecoration(
        color: isDark ? AppColors.slate900 : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? AppColors.slate600 : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Title
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Row(
              children: [
                Icon(Icons.graphic_eq_rounded,
                    color: Theme.of(context).colorScheme.primary, size: 20),
                const SizedBox(width: 10),
                Text(
                  'Session Playback',
                  style: GoogleFonts.manrope(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : AppColors.slate900,
                  ),
                ),
                const Spacer(),
                // Legend
                _LegendDot(color: Theme.of(context).colorScheme.primary, label: 'You'),
                const SizedBox(width: 10),
                const _LegendDot(color: Colors.orange, label: 'Other'),
                const SizedBox(width: 10),
                const _LegendDot(color: Colors.purple, label: 'AI'),
              ],
            ),
          ),
          const Divider(height: 1),
          // Lines (lyrics)
          Expanded(
            child: _lines.isEmpty
                ? Center(
                    child: Text('Loading transcript...',
                        style: GoogleFonts.manrope(color: AppColors.textMuted)))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: _lines.length,
                    itemBuilder: (context, i) {
                      final line = _lines[i];
                      final isCurrent = _isCurrentLine(i);
                      return _buildLine(line, isCurrent, isDark);
                    },
                  ),
          ),
          const Divider(height: 1),
          // Player controls
          Padding(
            padding: EdgeInsets.fromLTRB(
                20, 10, 20, 10 + MediaQuery.of(context).padding.bottom),
            child: Column(
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 14),
                  ),
                  child: Slider(
                    value: _duration.inMilliseconds > 0
                        ? _position.inMilliseconds
                            .toDouble()
                            .clamp(0, _duration.inMilliseconds.toDouble())
                        : 0,
                    max: _duration.inMilliseconds > 0
                        ? _duration.inMilliseconds.toDouble()
                        : 1,
                    onChanged: (v) =>
                        _player.seek(Duration(milliseconds: v.toInt())),
                    activeColor: Theme.of(context).colorScheme.primary,
                    inactiveColor:
                        isDark ? AppColors.slate700 : Colors.grey.shade300,
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_fmt(_position),
                        style: GoogleFonts.manrope(
                            fontSize: 12, color: AppColors.textMuted)),
                    Text(_fmt(_duration),
                        style: GoogleFonts.manrope(
                            fontSize: 12, color: AppColors.textMuted)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.replay_10_rounded),
                      iconSize: 30,
                      color: isDark ? Colors.white70 : AppColors.slate700,
                      onPressed: () => _player.seek(Duration(
                          milliseconds: (_position.inMilliseconds - 10000)
                              .clamp(0, _duration.inMilliseconds))),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: _togglePlay,
                      child: Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        child: Icon(
                          _playerState == PlayerState.playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton(
                      icon: const Icon(Icons.forward_10_rounded),
                      iconSize: 30,
                      color: isDark ? Colors.white70 : AppColors.slate700,
                      onPressed: () => _player.seek(Duration(
                          milliseconds: (_position.inMilliseconds + 10000)
                              .clamp(0, _duration.inMilliseconds))),
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

  Widget _buildLine(_PlaybackLine line, bool isCurrent, bool isDark) {
    final Color roleColor;
    final String label;

    switch (line.role) {
      case 'user':
        roleColor = Theme.of(context).colorScheme.primary;
        label = 'You';
      case 'llm':
        roleColor = Colors.purple;
        label = 'AI';
      default:
        roleColor = Colors.orange;
        label = 'Other';
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: isCurrent
            ? roleColor.withAlpha(isDark ? 35 : 20)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: isCurrent
            ? Border.all(color: roleColor.withAlpha(100), width: 1.5)
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2, right: 10),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: roleColor.withAlpha(isCurrent ? 70 : 35),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              label,
              style: GoogleFonts.manrope(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: roleColor,
              ),
            ),
          ),
          Expanded(
            child: Text(
              line.text,
              style: GoogleFonts.manrope(
                fontSize: isCurrent ? 15 : 14,
                fontWeight:
                    isCurrent ? FontWeight.w700 : FontWeight.w400,
                color: isCurrent
                    ? (isDark ? Colors.white : AppColors.slate900)
                    : (isDark ? AppColors.slate400 : AppColors.slate500),
                height: 1.4,
              ),
            ),
          ),
          if (line.role == 'llm')
            Padding(
              padding: const EdgeInsets.only(left: 6, top: 2),
              child: Icon(Icons.auto_awesome_rounded,
                  size: 13, color: Colors.purple.withAlpha(160)),
            ),
        ],
      ),
    );
  }
}

class _PlaybackLine {
  final String role;
  final String text;
  final double? start; // null for LLM lines (no audio position)

  const _PlaybackLine(
      {required this.role, required this.text, required this.start});
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 7,
            height: 7,
            decoration:
                BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label,
            style: GoogleFonts.manrope(
                fontSize: 11,
                color: AppColors.textMuted,
                fontWeight: FontWeight.w600)),
      ],
    );
  }
}
