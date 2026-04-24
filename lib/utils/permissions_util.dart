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
      Permission.notification, // Added notification
      Permission.location,
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
    ];

    final deniedPermissions = <Permission>[];

    // Check standard permissions
    for (final permission in permissionsToRequest) {
      final status = await permission.status;
      if (status.isDenied || status.isRestricted || status.isLimited) {
        deniedPermissions.add(permission);
      }
    }

    // Request them
    if (deniedPermissions.isNotEmpty) {
      await deniedPermissions.request();
    }

    // Handle storage specially
    await requestStoragePermission();

    // Check for permanent denials and show dialog if needed
    // (Omitted the dialog for brevity in startup, but can be added back if critical)
  }

  /// Special helper for storage permissions across Android versions
  static Future<PermissionStatus> requestStoragePermission() async {
    // 1. Check legacy storage permission first
    PermissionStatus status = await Permission.storage.status;
    if (status.isGranted) return status;

    // 2. On Android 13+, Permission.storage (READ_EXTERNAL_STORAGE) is deprecated.
    // We should request photos/videos/audio instead for media access.
    // For non-media file access on Android 11+, apps should ideally use Scoped Storage,
    // but if the user wants "Storage" enabled, we try to get what we can.
    
    // Request legacy storage
    status = await Permission.storage.request();
    
    // If still denied and on Android 13+, try requesting media permissions as a bundle
    if (!status.isGranted) {
      final mediaResults = await [
        Permission.photos,
        Permission.videos,
        Permission.audio,
      ].request();
      
      // If any of these are granted, we consider "Storage" (media access) as partially granted
      if (mediaResults.values.any((s) => s.isGranted)) {
        return PermissionStatus.granted;
      }
    }

    return status;
  }

  /// Returns the current status for a single permission.
  static Future<PermissionStatus> checkPermission(Permission permission) async {
    if (permission == Permission.storage) {
      final status = await Permission.storage.status;
      if (status.isGranted) return status;
      
      // On Android 13+, check if any media permission is granted
      final photos = await Permission.photos.status;
      final videos = await Permission.videos.status;
      final audio = await Permission.audio.status;
      
      if (photos.isGranted || videos.isGranted || audio.isGranted) {
        return PermissionStatus.granted;
      }
      
      return status;
    }
    return permission.status;
  }

  /// Requests a single permission. Returns the resulting status.
  static Future<PermissionStatus> requestPermission(Permission permission) async {
    if (permission == Permission.storage) {
      return await requestStoragePermission();
    }
    return permission.request();
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
