import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

import '../theme/design_tokens.dart';
import '../utils/permissions_util.dart';
import '../widgets/glass_morphism.dart';

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  static const _permissionDefs = [
    (Permission.microphone,   'Microphone',    Icons.mic_rounded,           'Required for live sessions and voice commands.'),
    (Permission.camera,       'Camera',        Icons.camera_alt_rounded,    'Used for profile photos.'),
    (Permission.notification, 'Notifications', Icons.notifications_rounded, 'Allows Bubbles to send reminders and digests.'),
    (Permission.storage,      'Storage',       Icons.folder_rounded,        'Needed to save and export session recordings.'),
  ];

  Map<Permission, PermissionStatus> _statuses = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStatuses();
  }

  Future<void> _loadStatuses() async {
    final results = <Permission, PermissionStatus>{};
    for (final (perm, _, _, _) in _permissionDefs) {
      results[perm] = await PermissionsUtil.checkPermission(perm);
    }
    if (mounted) setState(() { _statuses = results; _loading = false; });
  }

  Future<void> _handleTap(Permission perm, PermissionStatus status) async {
    if (status.isPermanentlyDenied) {
      await openAppSettings();
    } else if (!status.isGranted) {
      final result = await PermissionsUtil.requestPermission(perm);
      if (mounted) setState(() => _statuses[perm] = result);
    }
  }

  String _statusLabel(PermissionStatus s) {
    if (s.isGranted) return 'Granted';
    if (s.isPermanentlyDenied) return 'Permanently Denied';
    return 'Denied';
  }

  Color _statusColor(PermissionStatus s, BuildContext ctx) {
    if (s.isGranted) return Colors.green;
    if (s.isPermanentlyDenied) return AppColors.error;
    return AppColors.slate400;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onHorizontalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) > 300) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor:
            isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Icon(Icons.arrow_back_ios_new_rounded,
                          color: isDark ? Colors.white : AppColors.slate900,
                          size: 20),
                    ),
                    const SizedBox(width: 16),
                    Text('Permissions',
                        style: GoogleFonts.manrope(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : AppColors.slate900)),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (_loading)
                const Expanded(child: Center(child: CircularProgressIndicator()))
              else
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: _permissionDefs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final (perm, label, icon, desc) = _permissionDefs[i];
                      final status = _statuses[perm] ?? PermissionStatus.denied;
                      final isGranted = status.isGranted;
                      return GlassCard(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withAlpha(26),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(icon,
                                    color: Theme.of(context).colorScheme.primary,
                                    size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(label,
                                        style: GoogleFonts.manrope(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 15,
                                            color: isDark
                                                ? Colors.white
                                                : AppColors.slate900)),
                                    const SizedBox(height: 2),
                                    Text(desc,
                                        style: GoogleFonts.manrope(
                                            fontSize: 12,
                                            color: AppColors.slate400)),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: _statusColor(status, context)
                                                .withAlpha(26),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            _statusLabel(status),
                                            style: GoogleFonts.manrope(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: _statusColor(status, context),
                                            ),
                                          ),
                                        ),
                                        if (!isGranted)
                                          GestureDetector(
                                            onTap: () =>
                                                _handleTap(perm, status),
                                            child: Text(
                                              status.isPermanentlyDenied
                                                  ? 'Open Settings'
                                                  : 'Request',
                                              style: GoogleFonts.manrope(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
