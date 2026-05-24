import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../widgets/app_dialog.dart';

class PermissionsUtil {
  /// Deprecated: previously asked the user to grant every device permission at
  /// startup. Now a no-op so we only prompt at the moment a feature actually
  /// needs the permission. Kept for backwards-compat call sites.
  static Future<void> requestStartupPermissions(BuildContext context) async {
    return;
  }

  /// Ensure a single permission is granted, prompting the user only if needed.
  /// Returns true when the permission is currently granted (or limited).
  static Future<bool> ensure(Permission permission, {BuildContext? context, String? rationale}) async {
    PermissionStatus status = permission == Permission.storage
        ? await checkPermission(Permission.storage)
        : await permission.status;

    if (status.isGranted || status.isLimited) return true;

    if (status.isPermanentlyDenied) {
      if (context != null && context.mounted) {
        await _showSettingsDialog(
          context: context,
          title: 'Permission needed',
          message: rationale ?? 'Open settings to enable this permission for the feature you just tapped.',
        );
      }
      return false;
    }

    final result = await requestPermission(permission);
    return result.isGranted || result.isLimited;
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
    await AppDialog.show<void>(
      context: context,
      title: title,
      subtitle: message,
      icon: Icons.warning_amber_rounded,
      tone: AppDialogTone.warning,
      barrierDismissible: false,
      actions: [
        AppDialogAction(
          label: 'Continue Anyway',
          onTap: () => Navigator.of(context).pop(),
        ),
        AppDialogAction(
          label: 'Open Settings',
          primary: true,
          onTap: () {
            openAppSettings();
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}
