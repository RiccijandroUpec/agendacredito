import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Nombre de la persona según el catastro público del SRI.
///
/// Ojo: el SRI solo conoce a quien tiene RUC (cédula + 001). Si la persona no
/// tiene RUC devuelve null y el nombre se escribe a mano. Falla en silencio
/// sin internet: nunca detiene el registro.
class Sri {
  static const _url =
      'https://srienlinea.sri.gob.ec/sri-catastro-sujeto-servicio-internet/rest/ConsolidadoContribuyente/obtenerPorNumerosRuc';

  static Future<String?> nombre(String cedula, {http.Client? cliente}) async {
    final c = cliente ?? http.Client();
    try {
      final r = await c
          .get(
            Uri.parse('$_url?ruc=${cedula}001'),
            headers: {'User-Agent': 'AgendaCredito/1.0 (Android)', 'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200 || r.bodyBytes.isEmpty) return null;
      final datos = jsonDecode(utf8.decode(r.bodyBytes));
      if (datos is! List || datos.isEmpty) return null;
      final razon = ((datos.first as Map)['razonSocial'] as String?)?.trim();
      return razon == null || razon.isEmpty ? null : razon;
    } catch (_) {
      return null;
    } finally {
      if (cliente == null) c.close();
    }
  }
}
