import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/design_tokens.dart';
import '../widgets/glass_morphism.dart';

class PermissionsUtil {
  static Future<void> requestStartupPermissions(BuildContext context) async {
    final permissionsToRequest = <Permission>[
      Permission.microphone,
      Permission.camera,
      Permission.storage,
      Permission.photos,
      Permission.videos,
      Permission.location,
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
    ];

    final deniedPermissions = <Permission>[];

    for (final permission in permissionsToRequest) {
      final status = await permission.status;
      if (status.isDenied || status.isRestricted || status.isLimited) {
        deniedPermissions.add(permission);
      }
    }

    if (deniedPermissions.isNotEmpty) {
      final result = await deniedPermissions.request();
      final hasPermanentlyDenied = result.values.any(
        (status) => status.isPermanentlyDenied,
      );

      if (hasPermanentlyDenied && context.mounted) {
        await _showSettingsDialog(
          context: context,
          title: 'Permissions Required',
          message:
              'Some required permissions are permanently denied. Please allow Camera, Microphone, Storage, Location, and Bluetooth in app settings.',
        );
      }
    }
  }

  static Future<void> _showSettingsDialog({
    required BuildContext context,
    required String title,
    required String message,
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => GlassDialog(
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
                    border: Border.all(color: AppColors.error.withAlpha(51)),
                  ),
                  child: const Icon(Icons.warning_amber_rounded,
                      color: AppColors.error, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: isDark ? Colors.white : AppColors.slate900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: isDark ? Colors.white70 : AppColors.slate600,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: () {
                  openAppSettings();
                  Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Open Settings',
                    style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 48,
              child: TextButton(
                onPressed: () => Navigator.pop(ctx),
                style: TextButton.styleFrom(
                  foregroundColor:
                      isDark ? Colors.white70 : AppColors.slate600,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Continue Anyway',
                    style: GoogleFonts.manrope(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
