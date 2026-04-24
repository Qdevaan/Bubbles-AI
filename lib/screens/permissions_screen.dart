import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../theme/design_tokens.dart';
import '../utils/permissions_util.dart';
import '../widgets/animated_background.dart';
import '../providers/settings_provider.dart';

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  static const _permissionDefs = [
    (
      Permission.microphone,
      'Microphone',
      Icons.mic_none_rounded,
      'Required for live sessions and voice commands.'
    ),
    (
      Permission.camera,
      'Camera',
      Icons.videocam_outlined,
      'Used for profile photos and video features.'
    ),
    (
      Permission.notification,
      'Notifications',
      Icons.notifications_none_rounded,
      'Allows Bubbles to send reminders and digests.'
    ),
    (
      Permission.storage,
      'Storage',
      Icons.folder_open_rounded,
      'Needed to save and export session recordings.'
    ),
  ];

  Map<Permission, PermissionStatus> _statuses = {};
  bool _loading = true;
  bool _notificationsExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadStatuses(isInitial: true);
  }

  Future<void> _loadStatuses({bool isInitial = false}) async {
    final results = <Permission, PermissionStatus>{};
    for (final (perm, _, _, _) in _permissionDefs) {
      results[perm] = await PermissionsUtil.checkPermission(perm);
    }
    if (mounted) {
      setState(() {
        _statuses = results;
        _loading = false;
      });
    }
  }

  Future<void> _handleToggle(Permission perm, PermissionStatus status) async {
    if (status.isPermanentlyDenied) {
      await openAppSettings();
    } else if (status.isGranted) {
      await openAppSettings();
    } else {
      final result = await PermissionsUtil.requestPermission(perm);
      if (mounted) {
        setState(() {
          _statuses[perm] = result;
        });
      }
    }
    _loadStatuses();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedAmbientBackground(isDark: isDark),
          ),

          SafeArea(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 20,
                            color: isDark ? Colors.white : AppColors.slate900,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Permissions',
                                style: GoogleFonts.manrope(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: isDark ? Colors.white : AppColors.slate900,
                                ),
                              ),
                              Text(
                                'Manage how Bubbles interacts with your device.',
                                style: GoogleFonts.manrope(
                                  fontSize: 13,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 32)),

                if (_loading)
                  const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final (perm, label, icon, desc) = _permissionDefs[index];
                          final status = _statuses[perm] ?? PermissionStatus.denied;
                          final isNotification = perm == Permission.notification;
                          
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: _PermissionTile(
                              label: label,
                              description: desc,
                              icon: icon,
                              status: status,
                              isDark: isDark,
                              onToggle: () => _handleToggle(perm, status),
                              isExpanded: isNotification && _notificationsExpanded,
                              onExpandToggle: isNotification && status.isGranted 
                                ? () => setState(() => _notificationsExpanded = !_notificationsExpanded)
                                : null,
                              expansionContent: isNotification && status.isGranted
                                ? const _NotificationSubSettings()
                                : null,
                            ),
                          )
                          .animate()
                          .fadeIn(delay: (100 * index).ms, duration: 400.ms)
                          .slideX(begin: 0.1, end: 0, curve: Curves.easeOutCubic);
                        },
                        childCount: _permissionDefs.length,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  final String label;
  final String description;
  final IconData icon;
  final PermissionStatus status;
  final bool isDark;
  final VoidCallback onToggle;
  final bool isExpanded;
  final VoidCallback? onExpandToggle;
  final Widget? expansionContent;

  const _PermissionTile({
    required this.label,
    required this.description,
    required this.icon,
    required this.status,
    required this.isDark,
    required this.onToggle,
    this.isExpanded = false,
    this.onExpandToggle,
    this.expansionContent,
  });

  @override
  Widget build(BuildContext context) {
    final isGranted = status.isGranted;
    final isPermanentlyDenied = status.isPermanentlyDenied;
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.glassWhite : Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(
          color: isDark ? AppColors.glassBorder : Colors.grey.shade200,
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withAlpha(8),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onExpandToggle,
              borderRadius: BorderRadius.vertical(
                top: const Radius.circular(AppRadius.xl),
                bottom: Radius.circular(isExpanded ? 0 : AppRadius.xl),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isGranted
                            ? primary.withAlpha(30)
                            : (isDark ? AppColors.slate800 : AppColors.slate100),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        icon,
                        color: isGranted ? primary : AppColors.textMuted,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: GoogleFonts.manrope(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : AppColors.slate900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isPermanentlyDenied 
                              ? 'Permanently disabled in settings.' 
                              : description,
                            style: GoogleFonts.manrope(
                              fontSize: 12,
                              color: isPermanentlyDenied ? AppColors.error : AppColors.textMuted,
                            ),
                          ),
                          if (onExpandToggle != null && isGranted) ...[
                            const SizedBox(height: 4),
                            Text(
                              isExpanded ? 'Tap to collapse' : 'Tap to further customize',
                              style: GoogleFonts.manrope(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: primary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (isPermanentlyDenied)
                      Icon(
                        Icons.settings_outlined,
                        color: AppColors.error.withAlpha(150),
                        size: 20,
                      )
                    else
                      SizedBox(
                        width: 48,
                        child: Switch.adaptive(
                          value: isGranted,
                          onChanged: (_) => onToggle(),
                          activeColor: primary,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (isExpanded && expansionContent != null) ...[
            Divider(height: 1, color: isDark ? AppColors.glassBorder : Colors.grey.shade100),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: expansionContent,
            ),
          ],
        ],
      ),
    );
  }
}

class _NotificationSubSettings extends StatelessWidget {
  const _NotificationSubSettings();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Consumer<SettingsProvider>(
      builder: (context, sp, _) {
        return Column(
          children: [
             _subToggle(
              context: context,
              title: 'Events & Deadlines',
              icon: Icons.event_rounded,
              value: sp.pushEvents,
              onChanged: (val) => sp.setPushEvents(val),
              isDark: isDark,
              color: Colors.orange,
            ),
            const SizedBox(height: 12),
            _subToggle(
              context: context,
              title: 'Insights & Highlights',
              icon: Icons.lightbulb_outline_rounded,
              value: sp.pushHighlights,
              onChanged: (val) => sp.setPushHighlights(val),
              isDark: isDark,
              color: Colors.blue,
            ),
            const SizedBox(height: 12),
            _subToggle(
              context: context,
              title: 'Feature Announcements',
              icon: Icons.campaign_outlined,
              value: sp.pushAnnouncements,
              onChanged: (val) => sp.setPushAnnouncements(val),
              isDark: isDark,
              color: Colors.purple,
            ),
            const SizedBox(height: 12),
            _subToggle(
              context: context,
              title: 'Gamification Reminders',
              icon: Icons.check_circle_outline,
              value: sp.pushReminders,
              onChanged: (val) => sp.setPushReminders(val),
              isDark: isDark,
              color: Colors.teal,
            ),
          ],
        );
      },
    );
  }

  Widget _subToggle({
    required BuildContext context,
    required String title,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
    required bool isDark,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withAlpha(20),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.manrope(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.slate300 : AppColors.slate700,
            ),
          ),
        ),
        SizedBox(
          width: 48,
          child: Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    );
  }
}
