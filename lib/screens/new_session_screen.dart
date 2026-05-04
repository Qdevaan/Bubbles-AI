import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../widgets/teleprompter_panel.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../theme/design_tokens.dart';
import '../widgets/glass_morphism.dart';
import '../services/api_service.dart';
import '../providers/performa_provider.dart';
import '../screens/performa_screen.dart';
import '../services/auth_service.dart';
import '../services/deepgram_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/connection_service.dart';
import '../providers/session_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/feedback_dialog.dart';
import '../widgets/session/session_widgets.dart';

// ============================================================================
//  NEW SESSION SCREEN  (Live Wingman)
//  Business logic managed by SessionProvider; animations stay local.
// ============================================================================
class NewSessionScreen extends StatefulWidget {
  const NewSessionScreen({super.key});

  @override
  State<NewSessionScreen> createState() => _NewSessionScreenState();
}

class _NewSessionScreenState extends State<NewSessionScreen>
    with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();

  // Pre-session settings
  bool _isIncognito = false;
  String _selectedPersona = 'casual';
  bool _toneInitialized = false;

  // Animations (local only)
  late AnimationController _pulseController;
  late AnimationController _blobController;

  SessionProvider get _session =>
      Provider.of<SessionProvider>(context, listen: false);

  @override
  void initState() {
    super.initState();
    final deepgram = Provider.of<DeepgramService>(context, listen: false);
    deepgram.addListener(_onDeepgramUpdate);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _blobController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_toneInitialized) {
      final defaultTone = context.read<SettingsProvider>().defaultLiveTone;
      // Normalise: only accept tones we support in the UI
      const supported = ['casual', 'semi-formal', 'formal'];
      _selectedPersona = supported.contains(defaultTone) ? defaultTone : 'casual';
      _toneInitialized = true;
    }
  }

  String _toneLabel(String tone) {
    switch (tone) {
      case 'formal':
        return 'Formal';
      case 'semi-formal':
        return 'Semi-Formal';
      default:
        return 'Casual';
    }
  }

  IconData _toneIcon(String tone) {
    switch (tone) {
      case 'formal':
        return Icons.work_outline_rounded;
      case 'semi-formal':
        return Icons.handshake_outlined;
      default:
        return Icons.sentiment_satisfied_rounded;
    }
  }

  @override
  void dispose() {
    final deepgram = Provider.of<DeepgramService>(context, listen: false);
    deepgram.removeListener(_onDeepgramUpdate);
    deepgram.disconnect();
    _scrollController.dispose();
    _pulseController.dispose();
    _blobController.dispose();
    super.dispose();
  }

  void _onDeepgramUpdate() {
    if (!mounted) return;
    final deepgram = Provider.of<DeepgramService>(context, listen: false);
    final api = Provider.of<ApiService>(context, listen: false);
    _session.onTranscriptReceived(deepgram, api);
    _scrollToBottom();
  }

  void _toggleSession() async {
    final deepgram = Provider.of<DeepgramService>(context, listen: false);
    final api = Provider.of<ApiService>(context, listen: false);
    final user = AuthService.instance.currentUser;

    // Retrieve arguments
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final targetEntityId = args?['targetEntityId'] as String?;

    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("User not found. Please login again.")),
        );
      }
      return;
    }

    if (_session.isSessionActive) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            insetPadding: const EdgeInsets.symmetric(horizontal: 24),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.xxl),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF0D1B1F).withAlpha(235)
                        : Colors.white.withAlpha(242),
                    borderRadius: BorderRadius.circular(AppRadius.xxl),
                    border: Border.all(
                      color: isDark
                          ? AppColors.glassBorder
                          : Colors.grey.shade200,
                    ),
                  ),
                  padding: const EdgeInsets.all(24),
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
                            child: const Icon(
                              Icons.stop_circle_outlined,
                              color: AppColors.error,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'End Session?',
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
                        'Your conversation will be saved.',
                        style: GoogleFonts.manrope(
                          fontSize: 14,
                          color: isDark
                              ? AppColors.slate400
                              : AppColors.slate500,
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
                                color: isDark
                                    ? AppColors.slate400
                                    : AppColors.slate500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.error,
                            ),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('End Session'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
      if (confirm != true) return;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Saving Session to Memory...")),
        );
      }

      final completedSessionId = _session.sessionId;
      final success = await _session.endSession(api, deepgram);

      if (mounted) {
        if (success) {
          // Show recording saved notification if audio was captured
          final savedPaths = _session.lastRecordingPaths;
          if (mounted && savedPaths != null) {
            final hasAudio = savedPaths['audio'] != null;
            final hasTx = savedPaths['transcript'] != null;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  hasAudio && hasTx
                      ? 'Session saved â€” audio + transcript recorded to device'
                      : hasTx
                          ? 'Session saved â€” transcript recorded to device'
                          : 'Session saved â€” audio recorded to device',
                ),
                backgroundColor: AppColors.success,
                duration: const Duration(seconds: 4),
              ),
            );
          } else if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Session Saved!"),
                backgroundColor: AppColors.success,
              ),
            );
          }

          await FeedbackDialog.show(context, sessionId: completedSessionId);

          if (mounted) {
            if (completedSessionId != null) {
              Navigator.pop(context); // Close new session screen
              Navigator.pushNamed(
                context,
                '/session_analytics',
                arguments: {
                  'sessionId': completedSessionId,
                  'sessionTitle': 'Live Session',
                },
              );
            } else {
              Navigator.pop(context);
            }
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Failed to save."),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } else {
      final serverUrl = context.read<ConnectionService>().serverUrl;
      final jwt = Supabase.instance.client.auth.currentSession?.accessToken ?? '';
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null && mounted) {
        context.read<PerformaProvider>().load(userId);
      }
      await _session.startSession(
        api,
        deepgram,
        targetEntityId: targetEntityId,
        tone: _selectedPersona,
        isEphemeral: _isIncognito,
        serverUrl: serverUrl,
        jwt: jwt,
      );
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        _scrollController.animateTo(
          0.0,
          duration: AppDurations.dialog,
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return MeshGradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Selector<SessionProvider, (bool, bool)>(
          selector: (_, s) => (s.isSessionActive, s.isConnecting),
          builder: (context, state, _) {
            final isSessionActive = state.$1;
            final isConnecting = state.$2;
            return Stack(
              children: [
                ..._buildBlobs(isDark, isSessionActive),
                SafeArea(
                  child: isSessionActive
                      ? (isConnecting
                          ? _buildConnectingState(isDark)
                          : _buildActiveSession(isDark))
                      : _buildPreSession(isDark),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _buildBlobs(bool isDark, bool isActive) {
    return [
      AnimatedBuilder(
        animation: _blobController,
        builder: (_, __) => Positioned(
          top: -100 + sin(_blobController.value * 2 * pi) * 30,
          right: -60 + cos(_blobController.value * 2 * pi) * 20,
          child: Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(
                context,
              ).colorScheme.primary.withAlpha(isActive ? 20 : 31),
            ),
          ),
        ),
      ),
      AnimatedBuilder(
        animation: _blobController,
        builder: (_, __) => Positioned(
          bottom: -80 + cos(_blobController.value * 2 * pi) * 25,
          left: -50 + sin(_blobController.value * 2 * pi) * 15,
          child: Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.purple.withAlpha(isActive ? 10 : 20),
            ),
          ),
        ),
      ),
    ];
  }

  // ========================
  // PRE-SESSION VIEW
  // ========================
  Widget _buildPreSession(bool isDark) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
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
                child: Center(
                  child: Text(
                    (ModalRoute.of(context)?.settings.arguments as Map?)?['targetEntityName'] != null
                        ? 'Roleplay: ${(ModalRoute.of(context)!.settings.arguments as Map)['targetEntityName']}'
                        : 'Live Wingman',
                    style: GoogleFonts.manrope(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : AppColors.slate900,
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.person_outline),
                tooltip: 'Performa',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PerformaScreen()),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Consumer<ConnectionService>(
            builder: (context, conn, _) {
              final isServerOnline = conn.isConnected;
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CheckItem(
                    icon: Icons.mic,
                    label: 'Microphone',
                    status: 'Ready',
                    color: AppColors.success,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 12),
                  CheckItem(
                    icon: Icons.wifi,
                    label: 'Server',
                    status: isServerOnline ? 'Connected' : 'Offline',
                    color: isServerOnline ? AppColors.success : AppColors.error,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 12),
                  CheckItem(
                    icon: Icons.bluetooth,
                    label: 'Bluetooth',
                    status: 'Optional',
                    color: AppColors.warning,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 20),

                  // Section 5 Settings
                  _buildSection5Settings(isDark),
                  const SizedBox(height: 20),

                  // Server offline warning banner
                  if (!isServerOnline) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.error.withAlpha(26),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.error.withAlpha(102),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.cloud_off,
                              color: AppColors.error,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Server Offline',
                                    style: GoogleFonts.manrope(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: AppColors.error,
                                    ),
                                  ),
                                  Text(
                                    'Set your server URL in Connections to enable sessions.',
                                    style: GoogleFonts.manrope(
                                      fontSize: 12,
                                      color: AppColors.error.withAlpha(204),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: () =>
                                  Navigator.pushNamed(context, '/connections'),
                              child: Text(
                                'Fix',
                                style: GoogleFonts.manrope(
                                  color: AppColors.error,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ] else
                    const SizedBox(height: 20),

                  // START Button
                  GestureDetector(
                    onTap: isServerOnline
                        ? _toggleSession
                        : () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Server is offline. Connect to the server first.',
                                ),
                                backgroundColor: AppColors.error,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                    child: AnimatedBuilder(
                      animation: _pulseController,
                      builder: (_, child) {
                        final scale = isServerOnline
                            ? 1.0 + sin(_pulseController.value * 2 * pi) * 0.03
                            : 1.0;
                        return Transform.scale(
                          scale: scale,
                          child: Opacity(
                            opacity: isServerOnline ? 1.0 : 0.4,
                            child: Container(
                              width: 140,
                              height: 140,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: isServerOnline
                                      ? [
                                          Theme.of(context).colorScheme.primary,
                                          Theme.of(
                                            context,
                                          ).colorScheme.primary.withAlpha(200),
                                        ]
                                      : [
                                          Colors.grey.shade500,
                                          Colors.grey.shade700,
                                        ],
                                ),
                                boxShadow: isServerOnline
                                    ? [
                                        BoxShadow(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary.withAlpha(89),
                                          blurRadius: 30,
                                          spreadRadius: 5,
                                        ),
                                      ]
                                    : [],
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    isServerOnline
                                        ? Icons.mic
                                        : Icons.cloud_off,
                                    color: Colors.white,
                                    size: 36,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    isServerOnline ? 'START' : 'OFFLINE',
                                    style: GoogleFonts.manrope(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      letterSpacing: 2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    isServerOnline
                        ? 'Tap to start listening'
                        : 'Connect to server to begin',
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      color: isDark ? AppColors.slate400 : AppColors.slate500,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  // ========================
  // GETTING READY STATE
  // ========================
  Widget _buildConnectingState(bool isDark) {
    return Column(
      children: [
        // Minimal header with LIVE badge
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.error.withAlpha(51),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.error.withAlpha(102)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.error, shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'LIVE',
                    style: GoogleFonts.manrope(
                      fontSize: 13, fontWeight: FontWeight.w700,
                      color: AppColors.error, letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Centered connecting animation
        Expanded(
          child: AnimatedBuilder(
            animation: _pulseController,
            builder: (_, __) {
              final pulse = (sin(_pulseController.value * 2 * pi) + 1) / 2;
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        // Outer glow ring
                        Container(
                          width: 120 + pulse * 20,
                          height: 120 + pulse * 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Theme.of(context).colorScheme.primary
                                .withAlpha((20 + (pulse * 30).toInt())),
                          ),
                        ),
                        // Inner circle
                        Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Theme.of(context).colorScheme.primary
                                .withAlpha(40),
                            border: Border.all(
                              color: Theme.of(context).colorScheme.primary
                                  .withAlpha(120),
                              width: 2,
                            ),
                          ),
                          child: Center(
                            child: SizedBox(
                              width: 36,
                              height: 36,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    Text(
                      'Getting Ready',
                      style: GoogleFonts.manrope(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : AppColors.slate900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Selector<SessionProvider, String>(
                      selector: (_, s) => s.currentSuggestion,
                      builder: (_, status, __) => Text(
                        status,
                        style: GoogleFonts.manrope(
                          fontSize: 14,
                          color: isDark ? AppColors.slate400 : AppColors.slate500,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ========================
  // ACTIVE SESSION VIEW
  // ========================
  Widget _buildActiveSession(bool isDark) {
    return Column(
      children: [
        // Header with LIVE badge
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Row(
            children: [
              const SizedBox(width: 48),
              Expanded(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.error.withAlpha(51),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.error.withAlpha(102)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.error,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'LIVE',
                          style: GoogleFonts.manrope(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.error,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.person_outline),
                tooltip: 'Performa',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PerformaScreen()),
                ),
              ),
            ],
          ),
        ),

        // Chat transcript
        Expanded(
          child: Selector<SessionProvider, List<Map<String, dynamic>>>(
            selector: (_, s) => s.sessionLogs,
            builder: (context, logs, _) {
              return logs.isEmpty
                  ? Center(
                      child: AnimatedBuilder(
                        animation: _pulseController,
                        builder: (_, __) {
                          return Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Theme.of(context).colorScheme.primary.withAlpha(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Theme.of(context).colorScheme.primary.withAlpha(
                                          (20 + sin(_pulseController.value * 2 * pi) * 20).toInt()),
                                      blurRadius: 40,
                                      spreadRadius: 10,
                                    )
                                  ],
                                ),
                                child: Icon(
                                  Icons.mic_none_rounded,
                                  size: 40,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              const SizedBox(height: 24),
                              Text(
                                "Listening...",
                                style: GoogleFonts.manrope(
                                  color: isDark ? AppColors.slate400 : AppColors.slate500,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      padding: const EdgeInsets.all(16),
                      itemCount: logs.length,
                      itemBuilder: (context, index) {
                        final actualIdx = logs.length - 1 - index;
                        final msg = logs[actualIdx];
                        final bool isMe = msg['speaker'] == 'User';
                        final bool uncertain = msg['isUncertain'] == true;
                        final String label = isMe
                            ? (uncertain ? 'You?' : 'You')
                            : (uncertain ? 'Them?' : 'Them');
                        return ChatBubble(
                          text: msg['text'] as String,
                          isUser: isMe,
                          speakerLabel: label,
                          isUncertain: uncertain,
                          onSwitchSpeaker: () => _reattribute(context, actualIdx, !isMe),
                          onAttributionChange: (asMe) => _reattribute(context, actualIdx, asMe),
                        );
                      },
                    );
            },
          ),
        ),

        // HUD Panel
        ClipRRect(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.xxl),
          ),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              decoration: BoxDecoration(
                color: isDark ? AppColors.backgroundDark.withAlpha(200) : Colors.white.withAlpha(220),
                border: Border(
                  top: BorderSide(
                    color: isDark ? AppColors.glassBorder : Colors.white.withAlpha(255),
                  ),
                ),
              ),
              child: Column(
            children: [
              // ── Teleprompter Panel ───────────────────────────────────────
              Consumer<SessionProvider>(
                builder: (ctx, sp, _) => TeleprompterPanel(
                  hints: sp.adviceHistory,
                  hasUncertainSpeaker: _hasUncertainSpeaker(sp),
                ),
              ),


              // Controls
              Selector<SessionProvider, bool>(
                selector: (_, s) => s.isSaving,
                builder: (context, isSaving, _) {
                  if (isSaving) {
                    return Column(
                      children: [
                        CircularProgressIndicator(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          "Saving Memories...",
                          style: GoogleFonts.manrope(color: AppColors.textMuted),
                        ),
                      ],
                    );
                  }
                  return Consumer<DeepgramService>(
                    builder: (context, deepgram, _) {
                      final muted = deepgram.isMuted;
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Mute toggle
                          GestureDetector(
                            onTap: deepgram.isConnected
                                ? () {
                                    deepgram.toggleMute();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(deepgram.isMuted
                                            ? 'Mic muted'
                                            : 'Mic active'),
                                        duration:
                                            const Duration(milliseconds: 800),
                                      ),
                                    );
                                  }
                                : null,
                            child: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: muted
                                    ? AppColors.error.withAlpha(40)
                                    : (isDark
                                          ? AppColors.glassWhite
                                          : Colors.grey.shade200),
                                border: muted
                                    ? Border.all(
                                        color: AppColors.error.withAlpha(153),
                                        width: 1.5,
                                      )
                                    : null,
                              ),
                              child: Icon(
                                muted ? Icons.mic_off : Icons.mic,
                                color: muted
                                    ? AppColors.error
                                    : (isDark
                                          ? Colors.white54
                                          : Colors.grey),
                                size: 22,
                              ),
                            ),
                          ),
                          const SizedBox(width: 20),
                          // End session
                          GestureDetector(
                            onTap: _toggleSession,
                            child: Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.error,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.error.withAlpha(102),
                                    blurRadius: 16,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.stop_rounded,
                                color: Colors.white,
                                size: 32,
                              ),
                            ),
                          ),
                          const SizedBox(width: 20),
                          // Swap speakers
                          Selector<SessionProvider, bool>(
                            selector: (_, s) => s.swapSpeakers,
                            builder: (context, swapSpeakers, _) {
                              return Tooltip(
                                message: 'Flips all past messages',
                                child: GestureDetector(
                                onTap: () {
                                  context.read<SessionProvider>().toggleSwapSpeakers();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Speakers swapped'),
                                      duration: Duration(milliseconds: 800),
                                    ),
                                  );
                                },
                                child: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: swapSpeakers
                                        ? Theme.of(context)
                                              .colorScheme
                                              .primary
                                              .withAlpha(40)
                                        : (isDark
                                              ? AppColors.glassWhite
                                              : Colors.grey.shade200),
                                    border: swapSpeakers
                                        ? Border.all(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary
                                                .withAlpha(153),
                                            width: 1.5,
                                          )
                                        : null,
                                  ),
                                  child: Icon(
                                    Icons.swap_horiz_rounded,
                                    color: swapSpeakers
                                        ? Theme.of(context).colorScheme.primary
                                        : (isDark
                                              ? Colors.white54
                                              : Colors.grey),
                                    size: 22,
                                  ),
                                ),
                              ));
                            },
                          ),
                          const SizedBox(width: 20),
                          // Change Tone
                          Selector<SessionProvider, String>(
                            selector: (_, s) => s.currentLiveTone,
                            builder: (context, currentTone, _) {
                              return GestureDetector(
                                onTap: () => _showTonePicker(context, isDark, currentTone),
                                child: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isDark ? AppColors.glassWhite : Colors.grey.shade200,
                                  ),
                                  child: Icon(
                                    Icons.tune_rounded,
                                    color: isDark ? Colors.white54 : Colors.grey,
                                    size: 22,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
        ),
        ),
      ],
    );
  }

  void _showTonePicker(BuildContext context, bool isDark, String currentTone) {
    // Tones must match the pre-session dropdown and backend expectations
    const tones = [
      {'id': 'casual', 'title': 'Casual & Friendly'},
      {'id': 'semi-formal', 'title': 'Semi-Formal'},
      {'id': 'formal', 'title': 'Formal & Professional'},
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.slate600 : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  'Assistant Tone',
                  style: GoogleFonts.manrope(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : AppColors.slate900,
                  ),
                ),
                const SizedBox(height: 12),
                ...tones.map((tone) {
                  final id = tone['id']!;
                  final title = tone['title']!;
                  final isSelected = currentTone == id;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    leading: Icon(
                      _toneIcon(id),
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : (isDark ? AppColors.slate400 : AppColors.slate500),
                    ),
                    title: Text(
                      title,
                      style: GoogleFonts.manrope(
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : (isDark ? Colors.white : AppColors.slate900),
                      ),
                    ),
                    trailing: isSelected
                        ? Icon(Icons.check_circle_rounded,
                            color: Theme.of(context).colorScheme.primary)
                        : null,
                    onTap: () {
                      setState(() => _selectedPersona = id);
                      context.read<SessionProvider>().changeLiveTone(id);
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Tone: $_selectedPersona'),
                          duration: const Duration(milliseconds: 600),
                        ),
                      );
                    },
                  );
                }),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }


  // ========================
  // PRE-SESSION SETTINGS
  // ========================
  Widget _buildSection5Settings(bool isDark) {
    const tones = ['casual', 'semi-formal', 'formal'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Tone chips ──────────────────────────────
          Text(
            'Conversation Mode',
            style: GoogleFonts.manrope(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.slate400 : AppColors.slate500,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: tones.map((tone) {
              final isSelected = _selectedPersona == tone;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedPersona = tone),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : (isDark
                              ? AppColors.glassWhite
                              : Colors.grey.shade100),
                      border: Border.all(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          _toneIcon(tone),
                          size: 20,
                          color: isSelected
                              ? Colors.white
                              : (isDark ? AppColors.slate400 : AppColors.slate500),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _toneLabel(tone),
                          style: GoogleFonts.manrope(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? Colors.white
                                : (isDark ? AppColors.slate300 : AppColors.slate700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // ── Incognito toggle ────────────────────────
          GestureDetector(
            onTap: () => setState(() => _isIncognito = !_isIncognito),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: _isIncognito
                    ? AppColors.warning.withAlpha(30)
                    : (isDark ? AppColors.glassWhite : Colors.grey.shade100),
                border: Border.all(
                  color: _isIncognito
                      ? AppColors.warning.withAlpha(120)
                      : Colors.transparent,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _isIncognito ? Icons.visibility_off : Icons.visibility_off_outlined,
                    size: 20,
                    color: _isIncognito
                        ? AppColors.warning
                        : (isDark ? AppColors.slate400 : AppColors.slate500),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Incognito Session',
                          style: GoogleFonts.manrope(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: _isIncognito
                                ? AppColors.warning
                                : (isDark ? Colors.white : AppColors.slate900),
                          ),
                        ),
                        Text(
                          'Not saved to memory',
                          style: GoogleFonts.manrope(
                            fontSize: 11,
                            color: isDark ? AppColors.slate400 : AppColors.slate500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _isIncognito,
                    onChanged: (v) => setState(() => _isIncognito = v),
                    activeColor: AppColors.warning,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _reattribute(BuildContext context, int index, bool asMe) {
    context.read<SessionProvider>().reattributeTurn(
      index,
      asMe,
      context.read<ApiService>(),
    );
  }

  bool _hasUncertainSpeaker(SessionProvider sp) {
    if (sp.sessionLogs.isEmpty) return false;
    final last = sp.sessionLogs.last;
    return last['isUncertain'] == true;
  }

}

// ============================================================================
//  TELEPROMPTER PANEL
//  Stacks AI coaching responses bottom-to-top. Auto-scrolls to the newest
//  entry; user can freely scroll up to review all previous responses.
// ============================================================================
