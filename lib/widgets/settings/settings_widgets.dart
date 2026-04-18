import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/design_tokens.dart';
import '../../services/auth_service.dart';
import '../../services/api_service.dart';

// --- Component Widgets ---

class SectionLabel extends StatelessWidget {
  final String label;
  const SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.manrope(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: isDark ? AppColors.slate400 : AppColors.slate500,
        ),
      ),
    );
  }
}

class GroupedContainer extends StatelessWidget {
  final bool isDark;
  final List<Widget> children;
  const GroupedContainer({required this.isDark, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.glassWhite : Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        border: Border.all(
          color: isDark ? AppColors.glassBorder : Colors.grey.shade200,
        ),
      ),
      child: Column(children: children),
    );
  }
}

class TileDivider extends StatelessWidget {
  final bool isDark;
  const TileDivider({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      indent: 60,
      color: isDark ? Colors.white.withAlpha(13) : Colors.grey.shade100,
    );
  }
}

class ProfileTile extends StatefulWidget {
  final bool isDark;
  const ProfileTile({required this.isDark});

  @override
  State<ProfileTile> createState() => ProfileTileState();
}

class ProfileTileState extends State<ProfileTile> {
  Map<String, dynamic>? _profile;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final profile = await AuthService.instance.getProfile();
    if (mounted) {
      setState(() {
        _profile = profile;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;
    final name =
        _profile?['full_name'] ?? user?.userMetadata?['full_name'] ?? 'User';
    final email = user?.email ?? '';
    final avatarUrl =
        _profile?['avatar_url'] ?? user?.userMetadata?['avatar_url'];

    return GestureDetector(
      onTap: () async {
        await context.push('/profile-completion');
        _loadProfile();
      },
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.primary.withAlpha(51),
              ),
              child: ClipOval(
                child: avatarUrl != null
                    ? CachedNetworkImage(
                        imageUrl: avatarUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        errorWidget: (_, __, ___) => Icon(
                          Icons.person,
                          color: widget.isDark ? Colors.white54 : Colors.grey,
                        ),
                      )
                    : Center(
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: GoogleFonts.manrope(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: GoogleFonts.manrope(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: widget.isDark
                          ? Colors.white
                          : AppColors.slate900,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    email,
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      color: AppColors.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: widget.isDark
                  ? AppColors.slate500
                  : Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsTile extends StatelessWidget {
  final bool isDark;
  final Color iconBg;
  final Color iconColor;
  final IconData icon;
  final String title;
  final Widget? trailing;
  final VoidCallback onTap;

  const SettingsTile({
    required this.isDark,
    required this.iconBg,
    required this.iconColor,
    required this.icon,
    required this.title,
    this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.manrope(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white : AppColors.slate900,
                ),
              ),
            ),
            if (trailing != null) ...[trailing!, const SizedBox(width: 6)],
            Icon(
              Icons.chevron_right,
              size: 20,
              color: isDark ? AppColors.slate500 : Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }
}

class ToggleTile extends StatelessWidget {
  final bool isDark;
  final Color iconBg;
  final Color iconColor;
  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  const ToggleTile({
    required this.isDark,
    required this.iconBg,
    required this.iconColor,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.manrope(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : AppColors.slate900,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Theme.of(context).colorScheme.primary,
          ),
        ],
      ),
    );
  }
}

// Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
// Voice Enrollment Section
// Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

enum EnrollState { idle, checking, recording, uploading, success, error }

class VoiceEnrollmentSection extends StatefulWidget {
  final bool isDark;
  const VoiceEnrollmentSection({required this.isDark});

  @override
  State<VoiceEnrollmentSection> createState() => VoiceEnrollmentSectionState();
}

class VoiceEnrollmentSectionState extends State<VoiceEnrollmentSection> {
  EnrollState _state = EnrollState.checking;
  String? _enrolledAt;
  String? _errorMessage;
  int _countdown = 7;
  Timer? _countdownTimer;
  AudioRecorder? _recorder;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _recorder?.dispose();
    super.dispose();
  }

  Future<void> _checkStatus() async {
    setState(() => _state = EnrollState.checking);
    final user = AuthService.instance.currentUser;
    if (user == null) {
      setState(() => _state = EnrollState.idle);
      return;
    }

    try {
      final res = await Supabase.instance.client
          .from('voice_enrollments')
          .select('updated_at')
          .eq('user_id', user.id)
          .maybeSingle();
      setState(() {
        _enrolledAt = res?['updated_at'] as String?;
        _state = EnrollState.idle;
      });
    } catch (_) {
      setState(() {
        _enrolledAt = null;
        _state = EnrollState.idle;
      });
    }
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return '';
    }
  }

  Future<void> _startEnrollment() async {
    final user = AuthService.instance.currentUser;
    if (user == null) return;

    // Check connection
    final api = Provider.of<ApiService>(context, listen: false);
    if (!api.isConnected) {
      setState(() {
        _state = EnrollState.error;
        _errorMessage =
            'Not connected to server. Set URL in Connections first.';
      });
      return;
    }

    // Request mic permission
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      setState(() {
        _state = EnrollState.error;
        _errorMessage = 'Microphone permission denied.';
      });
      return;
    }

    // Get temp file path
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/enrollment_${user.id}.m4a';

    _recorder = AudioRecorder();
    setState(() {
      _state = EnrollState.recording;
      _countdown = 7;
    });

    await _recorder!.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: path,
    );

    // Countdown timer
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _countdown--);
      if (_countdown <= 0) {
        t.cancel();
        await _finishRecording(
          path,
          user.id,
          user.userMetadata?['full_name'] ?? user.email ?? 'User',
        );
      }
    });
  }

  Future<void> _finishRecording(
    String path,
    String userId,
    String userName,
  ) async {
    await _recorder?.stop();
    _recorder?.dispose();
    _recorder = null;

    if (!mounted) return;
    setState(() => _state = EnrollState.uploading);

    final api = Provider.of<ApiService>(context, listen: false);
    try {
      final enrolledAt = await api.enrollVoice(
        userId: userId,
        userName: userName,
        audioPath: path,
      );
      if (mounted) {
        setState(() {
          _enrolledAt = enrolledAt;
          _state = EnrollState.success;
        });
        // Reset to idle after 2 seconds so the tile shows the updated status
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _state = EnrollState.idle);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = EnrollState.error;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  void _cancelRecording() {
    _countdownTimer?.cancel();
    _recorder?.stop();
    _recorder?.dispose();
    _recorder = null;
    setState(() {
      _state = EnrollState.idle;
    });
  }

  @override
  Widget build(BuildContext context) {
    final color = const Color(0xFFF472B6); // pink accent for voice
    final bg = color.withAlpha(38);

    switch (_state) {
      case EnrollState.checking:
        return const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
            ],
          ),
        );

      case EnrollState.recording:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.error.withAlpha(38),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.mic,
                      color: AppColors.error,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Recording...',
                          style: GoogleFonts.manrope(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: widget.isDark
                                ? Colors.white
                                : AppColors.slate900,
                          ),
                        ),
                        Text(
                          'Speak naturally for $_countdown more seconds',
                          style: GoogleFonts.manrope(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _cancelRecording,
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.manrope(
                        color: AppColors.textMuted,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: (7 - _countdown) / 7,
                backgroundColor: AppColors.error.withAlpha(26),
                color: AppColors.error,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          ),
        );

      case EnrollState.uploading:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.upload, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Uploading & verifying enrollment...',
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
              const SizedBox(
                width: 8,
                height: 8,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ),
        );

      case EnrollState.success:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.success.withAlpha(38),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.check_circle_outline,
                  color: AppColors.success,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Voice enrolled successfully!',
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.success,
                  ),
                ),
              ),
            ],
          ),
        );

      case EnrollState.error:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.error.withAlpha(26),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.error_outline,
                      color: AppColors.error,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Enrollment failed',
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.error,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _state = EnrollState.idle),
                    child: Text(
                      'Retry',
                      style: GoogleFonts.manrope(
                        color: AppColors.error,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(left: 54, top: 4),
                  child: Text(
                    _errorMessage!,
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        );

      case EnrollState.idle:
      default:
        final isEnrolled = _enrolledAt != null;
        return GestureDetector(
          onTap: _startEnrollment,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.fingerprint, color: color, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Voice Enrollment',
                        style: GoogleFonts.manrope(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: widget.isDark
                              ? Colors.white
                              : AppColors.slate900,
                        ),
                      ),
                      Text(
                        isEnrolled
                            ? 'Enrolled on ${_formatDate(_enrolledAt)}'
                            : 'Not enrolled Ã¢â‚¬â€ tap to record',
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          color: isEnrolled
                              ? AppColors.success
                              : AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isEnrolled)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.success.withAlpha(31),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Active',
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.success,
                      ),
                    ),
                  )
                else
                  Text(
                    'Enroll',
                    style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: color,
                    ),
                  ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: widget.isDark
                      ? AppColors.slate500
                      : Colors.grey.shade400,
                ),
              ],
            ),
          ),
        );
    }
  }
}

// Ã¢â€â‚¬Ã¢â€â‚¬ Contact row used in the contact bottom sheet Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
class ContactRow extends StatelessWidget {
  final bool isDark;
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  const ContactRow({
    required this.isDark,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.slate900 : AppColors.slate50,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: iconColor.withAlpha(31),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppColors.slate500
                      : AppColors.slate400,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : AppColors.slate900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
