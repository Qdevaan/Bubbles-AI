import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../providers/settings_provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/design_tokens.dart';

class VoiceEnrollmentScreen extends StatefulWidget {
  const VoiceEnrollmentScreen({super.key});

  @override
  State<VoiceEnrollmentScreen> createState() => _VoiceEnrollmentScreenState();
}

class _VoiceEnrollmentScreenState extends State<VoiceEnrollmentScreen>
    with SingleTickerProviderStateMixin {
  final _recorder = AudioRecorder();

  bool _isRecording = false;
  bool _isUploading = false;
  String? _errorMessage;
  String? _recordingPath;
  int _countdown = 0;
  Timer? _countdownTimer;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  static const int _recordSeconds = 7;

  static const List<String> _phrases = [
    '"Hey Bubbles, start a new session."',
    '"Let me tell you what happened today."',
    '"I need some advice on this situation."',
  ];
  int _phraseIndex = 0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.stop();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pulseController.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      setState(() => _errorMessage = 'Microphone permission denied.');
      return;
    }

    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/voice_sample_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 16000, numChannels: 1),
      path: path,
    );

    setState(() {
      _isRecording = true;
      _recordingPath = path;
      _countdown = _recordSeconds;
      _errorMessage = null;
    });
    _pulseController.repeat(reverse: true);

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _countdown--);
      if (_countdown <= 0) {
        t.cancel();
        _stopAndUpload();
      }
    });
  }

  Future<void> _stopAndUpload() async {
    _countdownTimer?.cancel();
    _pulseController.stop();

    final path = await _recorder.stop();
    if (!mounted) return;

    setState(() {
      _isRecording = false;
      _isUploading = true;
      _errorMessage = null;
    });

    final filePath = path ?? _recordingPath;
    if (filePath == null || !File(filePath).existsSync()) {
      setState(() {
        _isUploading = false;
        _errorMessage = 'Recording file not found. Please try again.';
      });
      return;
    }

    try {
      final user = AuthService.instance.currentUser;
      if (user == null) throw Exception('Not signed in.');

      final api = context.read<ApiService>();
      await api.enrollVoice(
        userId: user.id,
        userName: user.userMetadata?['full_name'] as String? ?? user.email ?? user.id,
        audioPath: filePath,
      );

      // Refresh enrollment count from Supabase
      if (mounted) {
        await context.read<SettingsProvider>().setVoiceEnrolled(
          samplesCount: context.read<SettingsProvider>().voiceSamplesCount + 1,
        );
        // Refresh exact count from DB
        await context.read<SettingsProvider>().loadSettings();
      }

      if (mounted) {
        setState(() {
          _isUploading = false;
          _phraseIndex = (_phraseIndex + 1) % _phrases.length;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Voice sample saved!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      try { File(filePath).deleteSync(); } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = context.watch<SettingsProvider>();
    final enrolled = settings.voiceEnrolled;
    final samples = settings.voiceSamplesCount;

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: SafeArea(
            child: Column(
              children: [
                _buildAppBar(context, isDark),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        const SizedBox(height: 24),
                        _buildStatusCard(isDark, enrolled, samples),
                        const SizedBox(height: 32),
                        _buildPhraseCard(isDark),
                        const SizedBox(height: 40),
                        _buildMicButton(isDark),
                        const SizedBox(height: 16),
                        _buildStatusText(isDark),
                        const SizedBox(height: 16),
                        if (_errorMessage != null) _buildError(isDark),
                        const SizedBox(height: 32),
                        _buildHint(isDark),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
    );
  }

  Widget _buildAppBar(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 0),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded,
                color: isDark ? Colors.white : AppColors.slate900, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 4),
          Text(
            'Voice Enrollment',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : AppColors.slate900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(bool isDark, bool enrolled, int samples) {
    final cardBg = isDark ? AppColors.slate800 : Colors.white;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: enrolled
              ? Colors.green.withAlpha(100)
              : (isDark ? AppColors.slate700 : AppColors.slate200),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: enrolled
                  ? Colors.green.withAlpha(30)
                  : (isDark ? AppColors.slate700 : AppColors.slate100),
              shape: BoxShape.circle,
            ),
            child: Icon(
              enrolled ? Icons.verified_rounded : Icons.mic_off_rounded,
              color: enrolled ? Colors.green : AppColors.slate400,
              size: 22,
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                enrolled ? 'Voice Enrolled' : 'Not Enrolled',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : AppColors.slate900,
                ),
              ),
              if (enrolled) ...[
                const SizedBox(height: 2),
                Text(
                  '$samples sample${samples == 1 ? '' : 's'} recorded',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppColors.slate400,
                  ),
                ),
              ] else ...[
                const SizedBox(height: 2),
                Text(
                  'Record at least 1 sample to enable',
                  style: GoogleFonts.inter(fontSize: 13, color: AppColors.slate400),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPhraseCard(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.slate800.withAlpha(180) : Colors.white.withAlpha(200),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: isDark ? AppColors.slate700 : AppColors.slate200,
        ),
      ),
      child: Column(
        children: [
          Text(
            'Say this phrase:',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppColors.slate400,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _phrases[_phraseIndex],
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : AppColors.slate900,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMicButton(bool isDark) {
    if (_isUploading) {
      return Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          color: isDark ? AppColors.slate700 : AppColors.slate100,
          shape: BoxShape.circle,
        ),
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
      );
    }

    return GestureDetector(
      onTap: _isRecording ? null : _startRecording,
      child: AnimatedBuilder(
        animation: _pulseAnim,
        builder: (context, child) {
          final scale = _isRecording ? _pulseAnim.value : 1.0;
          return Transform.scale(
            scale: scale,
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: _isRecording ? Colors.red : Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (_isRecording ? Colors.red : Theme.of(context).colorScheme.primary)
                        .withAlpha(_isRecording ? 100 : 60),
                    blurRadius: _isRecording ? 24 : 12,
                    spreadRadius: _isRecording ? 4 : 0,
                  ),
                ],
              ),
              child: Icon(
                _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                color: Colors.white,
                size: 36,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusText(bool isDark) {
    final text = _isUploading
        ? 'Uploading voice sample…'
        : _isRecording
            ? 'Recording… $_countdown s remaining'
            : 'Tap the mic to record a sample';

    return Text(
      text,
      style: GoogleFonts.inter(
        fontSize: 14,
        color: _isRecording ? Colors.red : AppColors.slate400,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildError(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.red.withAlpha(20),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Colors.red.withAlpha(80)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.red, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMessage!,
              style: GoogleFonts.inter(fontSize: 13, color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHint(bool isDark) {
    return Text(
      'More samples = better accuracy. Record 3+ samples in different environments for best results.',
      textAlign: TextAlign.center,
      style: GoogleFonts.inter(
        fontSize: 12,
        color: AppColors.slate400,
        height: 1.5,
      ),
    );
  }
}
