import 'dart:convert';
import 'package:crypto/crypto.dart';

class PayloadCodec {
  static String serialize(dynamic payload) {
    return jsonEncode(payload);
  }

  static dynamic deserialize(String json) {
    return jsonDecode(json);
  }

  static String computeHash(dynamic payload) {
    final bytes = utf8.encode(serialize(payload));
    return sha256.convert(bytes).toString();
  }
}
