// Purpose: State manager for the Performa persona — fetches, caches, and updates the user's persona via the API.
import 'package:flutter/foundation.dart';

import 'package:bubbles/models/persona.dart';
import 'package:bubbles/services/persona_service.dart';
import 'package:bubbles/services/boot_state_service.dart';

class PersonaProvider extends ChangeNotifier {
  final PersonaService service;
  Persona? _persona;
  bool _loading = true;
  String? _error;
  bool _hasResolved = false;

  PersonaProvider({required this.service});

  Persona? get persona => _persona;
  bool get loading => _loading;
  String? get error => _error;
  bool get hasResolved => _hasResolved;
  bool get needsWizard =>
      !_loading && (_persona == null || !_persona!.isComplete);

  /// Synchronous best-effort answer for AppBootstrap.
  /// Reads from the SharedPreferences mirror when the provider has not yet
  /// resolved a live persona.
  bool get isCompleteOrSkippedSync {
    if (_hasResolved) {
      return _persona?.isComplete ?? false;
    }
    return BootStateService.instance.canSkipWizard;
  }

  Future<void> refresh() async {
    _loading = true;
    notifyListeners();
    try {
      _persona = await service.fetchMyPersona();
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      _hasResolved = true;
      await _writeMirror();
      notifyListeners();
    }
  }

  Future<void> upsert(PersonaUpdate update) async {
    _persona = await service.upsertMyPersona(update);
    _hasResolved = true;
    await _writeMirror();
    notifyListeners();
  }

  /// Locally clears the persona without a network call. Used on sign-out so
  /// the next session does not inherit the previous user's persona state.
  void clearLocal() {
    _persona = null;
    _hasResolved = false;
    _loading = true;
    notifyListeners();
  }

  Future<void> _writeMirror() async {
    await BootStateService.instance
        .setPersonaComplete(_persona?.isComplete ?? false);
  }
}
