import 'package:bubbles/models/persona.dart';
import 'package:bubbles/services/api_service.dart';

class PersonaService {
  final ApiService _api;
  PersonaService(this._api);

  Future<Persona?> fetchMyPersona() async {
    final raw = await _api.getMyPersona();
    if (raw == null) return null;
    return Persona.fromJson(raw);
  }

  Future<Persona> upsertMyPersona(PersonaUpdate update) async {
    final raw = await _api.upsertMyPersona(update);
    return Persona.fromJson(raw);
  }

  Future<void> setSessionContext(
    String sessionId, {
    required String scenario,
    String roleMode = 'default',
    String? notes,
  }) =>
      _api.setSessionContext(
        sessionId,
        scenario: scenario,
        roleMode: roleMode,
        notes: notes,
      );
}
