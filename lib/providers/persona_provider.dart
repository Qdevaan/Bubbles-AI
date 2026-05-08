import 'package:flutter/foundation.dart';

import 'package:bubbles/models/persona.dart';
import 'package:bubbles/services/persona_service.dart';

class PersonaProvider extends ChangeNotifier {
  final PersonaService service;
  Persona? _persona;
  bool _loading = true;
  String? _error;

  PersonaProvider({required this.service});

  Persona? get persona => _persona;
  bool get loading => _loading;
  String? get error => _error;
  bool get needsWizard =>
      !_loading && (_persona == null || !_persona!.isComplete);

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
      notifyListeners();
    }
  }

  Future<void> upsert(PersonaUpdate update) async {
    _persona = await service.upsertMyPersona(update);
    notifyListeners();
  }
}
