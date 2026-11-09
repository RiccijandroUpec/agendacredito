import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class DatosSri {
  final String nombre;
  final String? provincia;
  final String? ciudad;
  final String? actividad;
  const DatosSri(this.nombre, {this.provincia, this.ciudad, this.actividad});
}

/// Datos públicos del catastro del SRI.
///
/// Ojo: el SRI solo conoce a quien tiene RUC (cédula + 001). Con una cédula
/// sin RUC el servicio no responde, así que se corta a los 12 s y devuelve
/// null. Falla en silencio sin internet: nunca detiene el registro.
class Sri {
  static const _base = 'https://srienlinea.sri.gob.ec/sri-catastro-sujeto-servicio-internet/rest';
  static const _cabeceras = {'User-Agent': 'AgendaCredito/1.0 (Android)', 'Accept': 'application/json'};

  static Future<dynamic> _json(http.Client c, String url) async {
    try {
      final r = await c.get(Uri.parse(url), headers: _cabeceras).timeout(const Duration(seconds: 12));
      if (r.statusCode != 200 || r.bodyBytes.isEmpty) return null;
      return jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {
      return null;
    }
  }

  static Future<DatosSri?> consultar(String cedula, {http.Client? cliente}) async {
    final c = cliente ?? http.Client();
    try {
      final ruc = '${cedula}001';
      final datos = await _json(c, '$_base/ConsolidadoContribuyente/obtenerPorNumerosRuc?ruc=$ruc');
      if (datos is! List || datos.isEmpty) return null;
      final p = datos.first as Map;
      final nombre = (p['razonSocial'] as String?)?.trim();
      if (nombre == null || nombre.isEmpty) return null;
      // Dirección: "IMBABURA / IBARRA / CARANQUI / CALLE ..."
      String? provincia, ciudad;
      final est = await _json(c, '$_base/Establecimiento/consultarPorNumeroRuc?numeroRuc=$ruc');
      if (est is List && est.isNotEmpty) {
        final lista = est.cast<Map>();
        final e = lista.where((x) => x['matriz'] == 'SI').firstOrNull ?? lista.first;
        final partes = '${e['direccionCompleta'] ?? ''}'.split('/').map((s) => s.trim()).toList();
        if (partes.length >= 2) {
          provincia = titulo(partes[0]);
          ciudad = titulo(partes[1]);
        }
      }
      return DatosSri(
        nombre,
        provincia: provincia,
        ciudad: ciudad,
        actividad: (p['actividadEconomicaPrincipal'] as String?)?.trim(),
      );
    } finally {
      if (cliente == null) c.close();
    }
  }

  /// "SANTO DOMINGO" → "Santo Domingo".
  static String titulo(String s) => s
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .map((p) => const {'de', 'del', 'la', 'las', 'los', 'y'}.contains(p) ? p : '${p[0].toUpperCase()}${p.substring(1)}')
      .join(' ');
}
