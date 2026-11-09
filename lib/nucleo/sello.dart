import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Cadena de sellos: cada evento guarda el hash del anterior. Si alguien
/// cambia una fecha de registro o borra un evento a mano en la base, la
/// verificación lo detecta. Sirve de prueba de "quién registró primero".
class Sello {
  static const inicial = 'AGENDA-CREDITO';

  static String calcular({
    required String anterior,
    required String clienteId,
    required String tipo,
    required String fecha,
    required String detalle,
  }) => sha256.convert(utf8.encode('$anterior|$clienteId|$tipo|$fecha|$detalle')).toString();

  /// Primeros 8 caracteres, para mostrar.
  static String corto(String hash) => hash.length >= 8 ? hash.substring(0, 8).toUpperCase() : hash;
}
