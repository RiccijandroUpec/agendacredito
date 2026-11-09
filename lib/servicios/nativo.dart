import 'package:flutter/services.dart';

/// Puente con el código Android (MainActivity, BurbujaService, RapidoActivity).
class Nativo {
  static const _canal = MethodChannel('agenda/nativo');

  static Future<String> androidId() async => (await _canal.invokeMethod<String>('androidId')) ?? '';

  static Future<bool> permisoBurbuja() async => (await _canal.invokeMethod<bool>('permisoBurbuja')) ?? false;
  static Future<void> pedirPermisoBurbuja() => _canal.invokeMethod('pedirPermisoBurbuja');
  static Future<bool> burbujaActiva() async => (await _canal.invokeMethod<bool>('burbujaActiva')) ?? false;
  static Future<void> mostrarBurbuja() => _canal.invokeMethod('mostrarBurbuja');
  static Future<void> ocultarBurbuja() => _canal.invokeMethod('ocultarBurbuja');

  /// Abre los ajustes de la app (en Xiaomi hay que permitir "ventanas
  /// emergentes en segundo plano" para que la burbuja abra el formulario).
  static Future<void> abrirAjustesApp() => _canal.invokeMethod('abrirAjustesApp');

  /// Guarda en Descargas/AgendaCredito (Android 10+). Reemplaza si ya existe.
  static Future<bool> guardarEnDescargas(String nombre, Uint8List bytes) async =>
      (await _canal.invokeMethod<bool>('guardarEnDescargas', {'nombre': nombre, 'bytes': bytes})) ?? false;

  /// Cierra la ventana rápida de la burbuja y vuelve a la app de crédito.
  static Future<void> cerrarRapido() => _canal.invokeMethod('cerrarRapido');

  /// La ventana rápida avisa cada vez que se abre, para limpiar el formulario.
  static void alAbrirRapido(void Function() f) {
    _canal.setMethodCallHandler((llamada) async {
      if (llamada.method == 'rapidoAbierto') f();
      return null;
    });
  }
}
