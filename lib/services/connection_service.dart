import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Compile-time production URL override.
/// Set via: flutter build apk --dart-define=SERVER_URL=http://YOUR_IP:8000
/// Falls back to saved URL in SharedPreferences, then .env, then ngrok default.
const _kServerUrl = String.fromEnvironment('SERVER_URL', defaultValue: '');
const _kDefaultUrl = 'https://4ee6-139-135-46-18.ngrok-free.app';
const _kSavedUrlKey = 'saved_server_url';

enum ConnectionStatus { disconnected, connecting, connected, error, offline }

class ConnectionService with ChangeNotifier {
  // --- Private State ---
  String _serverUrl = '';
  ConnectionStatus _status = ConnectionStatus.disconnected;
  Timer? _statusCheckTimer;
  bool _isChecking = false;

  // -- Exponential backoff for periodic checks --
  int _consecutiveFailures = 0;
  static const int _baseIntervalSec = 60;
  static const int _maxIntervalSec = 300; // cap at 5 minutes

  // -- Connectivity --
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  // --- Public Getters ---
  String get serverUrl => _serverUrl;
  // Backwards compatibility if needed, but prefer serverUrl
  String get serverIp => _serverUrl;
  ConnectionStatus get status => _status;
  bool get isConnected => _status == ConnectionStatus.connected;

  // --- Initialization ---
  ConnectionService() {
    _initConnectivity();
    _determineServerUrlAndInitialCheck();
  }

  Future<void> _initConnectivity() async {
    // Initial check
    final results = await _connectivity.checkConnectivity();
    _handleConnectivityChange(results);

    // Listen for changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _handleConnectivityChange,
    );
  }

  void _handleConnectivityChange(List<ConnectivityResult> results) {
    if (results.contains(ConnectivityResult.none)) {
      _updateStatus(ConnectionStatus.offline);
    } else {
      if (_status == ConnectionStatus.offline) {
        _updateStatus(ConnectionStatus.disconnected);
        checkConnection();
      }
    }
  }

  // --- URL Management ---
  void _determineServerUrlAndInitialCheck() {
    // Priority 1: compile-time dart-define (release builds)
    if (_kServerUrl.isNotEmpty) {
      _serverUrl = _kServerUrl;
      notifyListeners();
      checkConnection(notifyResult: false);
      _startPeriodicChecks();
      return;
    }

    // Priority 2: SharedPreferences (last user-saved URL) — async, load then connect
    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getString(_kSavedUrlKey);
      if (saved != null && saved.isNotEmpty) {
        _serverUrl = saved;
      } else {
        // Priority 3: .env file LOCAL_SERVER_URL
        final envUrl = dotenv.env['LOCAL_SERVER_URL'];
        if (envUrl != null && envUrl.trim().isNotEmpty) {
          _serverUrl = envUrl.trim();
        } else {
          // Priority 4: ngrok default
          _serverUrl = _kDefaultUrl;
        }
      }
      notifyListeners();
      checkConnection(notifyResult: false);
      _startPeriodicChecks();
    });
  }

  Future<void> saveUrl(String url) async {
    String cleanUrl = url.trim();
    if (cleanUrl.endsWith('/')) {
      cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
    }

    if (!cleanUrl.startsWith('http')) {
      cleanUrl = 'http://$cleanUrl';
      if (RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(url.trim())) {
        cleanUrl = 'http://${url.trim()}:8000';
      }
    }

    _serverUrl = cleanUrl;
    notifyListeners();

    // Persist so next launch auto-reconnects
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSavedUrlKey, cleanUrl);

    await checkConnection();
  }

  // --- Connection Testing ---
  Future<bool> checkConnection({bool notifyResult = true}) async {
    if (_status == ConnectionStatus.offline) return false;

    if (_serverUrl.isEmpty) {
      _updateStatus(ConnectionStatus.disconnected);
      return false;
    }

    if (_isChecking) return false;
    _isChecking = true;
    if (notifyResult) _updateStatus(ConnectionStatus.connecting);

    try {
      debugPrint('Pinging $_serverUrl/health ...');
      final response = await http
          .get(
            Uri.parse('$_serverUrl/health'),
            headers: {"ngrok-skip-browser-warning": "true"},
          )
          .timeout(const Duration(seconds: 5));

      debugPrint('Ping response: ${response.statusCode}');

      if (response.statusCode == 200) {
        _consecutiveFailures = 0;
        _reschedulePeriodicChecks();
        _updateStatus(ConnectionStatus.connected);
        if (notifyResult) {
          debugPrint('Connection successful! (Status: ${response.statusCode})');
        }
        return true;
      } else {
        debugPrint('Server returned error status: ${response.statusCode}');
        _onCheckFailed();
        return false;
      }
    } catch (e) {
      debugPrint('Connection check failed: $e');
      _onCheckFailed();
      return false;
    } finally {
      _isChecking = false;
    }
  }

  void _onCheckFailed() {
    _consecutiveFailures++;
    _reschedulePeriodicChecks();
    _updateStatus(ConnectionStatus.error);
  }

  void _updateStatus(ConnectionStatus newStatus) {
    if (_status != newStatus) {
      _status = newStatus;
      notifyListeners();
    }
  }

  // --- Periodic Checks with Exponential Backoff ---
  void _startPeriodicChecks() {
    _reschedulePeriodicChecks();
  }

  void _reschedulePeriodicChecks() {
    _statusCheckTimer?.cancel();
    // Exponential backoff: 60s, 120s, 240s, capped at 300s
    final intervalSec = min(
      _baseIntervalSec * pow(2, _consecutiveFailures).toInt(),
      _maxIntervalSec,
    );
    _statusCheckTimer = Timer.periodic(Duration(seconds: intervalSec), (timer) {
      if (!_isChecking && _serverUrl.isNotEmpty) {
        checkConnection(notifyResult: false);
      }
    });
  }

  @override
  void dispose() {
    _statusCheckTimer?.cancel();
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}
