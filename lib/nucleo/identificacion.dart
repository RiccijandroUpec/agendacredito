/// Validación de cédulas ecuatorianas (módulo 10 del Registro Civil).
class Identificacion {
  static bool cedulaValida(String c) {
    if (!RegExp(r'^\d{10}$').hasMatch(c)) return false;
    final provincia = int.parse(c.substring(0, 2));
    if (!((provincia >= 1 && provincia <= 24) || provincia == 30)) return false;
    if (int.parse(c[2]) >= 6) return false;
    var suma = 0;
    for (var i = 0; i < 9; i++) {
      var v = int.parse(c[i]) * (i.isEven ? 2 : 1);
      if (v > 9) v -= 9;
      suma += v;
    }
    return (10 - suma % 10) % 10 == int.parse(c[9]);
  }

  /// Mensaje para el formulario, o null si la cédula está bien.
  static String? errorCedula(String c) {
    final n = c.trim();
    if (n.isEmpty) return 'Escribe la cédula';
    if (!RegExp(r'^\d+$').hasMatch(n)) return 'Solo números';
    if (n.length != 10) return 'La cédula tiene 10 dígitos (van ${n.length})';
    final provincia = int.parse(n.substring(0, 2));
    if (!((provincia >= 1 && provincia <= 24) || provincia == 30)) return 'Los 2 primeros dígitos no son de una provincia';
    if (!cedulaValida(n)) return 'Cédula no válida: revisa los números';
    return null;
  }

  /// "1712345678" → "171234567-8", como viene impresa.
  static String formatear(String c) => c.length == 10 ? '${c.substring(0, 9)}-${c[9]}' : c;
}
