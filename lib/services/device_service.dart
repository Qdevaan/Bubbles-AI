import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_service.dart';

/// Registers and keeps the current device up-to-date in the `user_devices`
/// table. Call [registerDevice] once after the user authenticates.
class DeviceService {
  // ── Singleton ──
  DeviceService._internal();
  static final DeviceService instance = DeviceService._internal();

  final SupabaseClient _client = Supabase.instance.client;

  String? _currentDeviceDbId; // UUID row id in user_devices
  String? get currentDeviceDbId => _currentDeviceDbId;

  /// Upserts the current device into `user_devices`.
  /// Returns the row UUID on success, null on failure.
  Future<String?> registerDevice() async {
    final user = AuthService.instance.currentUser;
    if (user == null) return null;

    try {
      final deviceInfo = DeviceInfoPlugin();
      String deviceId = 'unknown';
      String deviceModel = 'unknown';
      String osVersion = 'unknown';

      if (Platform.isAndroid) {
        final android = await deviceInfo.androidInfo;
        deviceId = android.id; // unique build ID
        deviceModel = '${android.manufacturer} ${android.model}';
        osVersion = 'Android ${android.version.release}';
      } else if (Platform.isIOS) {
        final ios = await deviceInfo.iosInfo;
        deviceId = ios.identifierForVendor ?? 'unknown';
        deviceModel = ios.utsname.machine;
        osVersion = '${ios.systemName} ${ios.systemVersion}';
      } else if (Platform.isWindows) {
        final win = await deviceInfo.windowsInfo;
        deviceId = win.deviceId;
        deviceModel = win.productName;
        osVersion = 'Windows ${win.majorVersion}.${win.minorVersion}';
      }

      final packageInfo = await PackageInfo.fromPlatform();
      final appVersion = packageInfo.version;

      final row = {
        'user_id': user.id,
        'device_id': deviceId,
        'device_model': deviceModel,
        'os_version': osVersion,
        'app_version': appVersion,
        'is_active': true,
        'last_active_at': DateTime.now().toUtc().toIso8601String(),
      };

      // Upsert on conflict (user_id, device_id)
      final res = await _client
          .from('user_devices')
          .upsert(row, onConflict: 'user_id,device_id')
          .select('id')
          .single();

      _currentDeviceDbId = res['id'] as String?;
      return _currentDeviceDbId;
    } catch (e) {
      debugPrint('DeviceService.registerDevice error: $e');
      return null;
    }
  }

  /// Update `last_active_at` for the current device.
  Future<void> heartbeat() async {
    if (_currentDeviceDbId == null) return;
    try {
      await _client.from('user_devices').update({
        'last_active_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', _currentDeviceDbId!);
    } catch (e) {
      debugPrint('DeviceService.heartbeat error: $e');
    }
  }
}
