import 'dart:async';
import 'dart:math';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

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
    // Check .env for a hardcoded URL first (e.g., for physical devices)
    final customUrl = dotenv.env['LOCAL_SERVER_URL'];
    
    if (customUrl != null && customUrl.trim().isNotEmpty) {
      _serverUrl = customUrl.trim();
    } else {
      // Default to simulator/emulator defaults based on platform
      if (kIsWeb) {
        _serverUrl = 'http://localhost:8000';
      } else if (Platform.isAndroid) {
        _serverUrl = 'http://10.0.2.2:8000';
      } else {
        // iOS Simulator, macOS, Windows, Linux
        _serverUrl = 'http://127.0.0.1:8000';
      }
    }
    
    notifyListeners();

    if (_serverUrl.isNotEmpty) {
      checkConnection(notifyResult: false);
    }
    _startPeriodicChecks();
  }

  // Allow setting a new custom URL manually, although not required anymore
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

    // Test immediately
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
