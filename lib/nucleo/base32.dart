import 'dart:typed_data';

/// Base32 RFC 4648 sin relleno: solo letras A-Z y dígitos 2-7, fácil de
/// dictar y de copiar por WhatsApp.
class Base32 {
  static const _alfabeto = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  static String codificar(List<int> bytes) {
    final sb = StringBuffer();
    var buffer = 0, bits = 0;
    for (final b in bytes) {
      buffer = ((buffer << 8) | b) & 0xFFFF;
      bits += 8;
      while (bits >= 5) {
        sb.write(_alfabeto[(buffer >> (bits - 5)) & 31]);
        bits -= 5;
      }
    }
    if (bits > 0) sb.write(_alfabeto[(buffer << (5 - bits)) & 31]);
    return sb.toString();
  }

  /// Ignora guiones, espacios y minúsculas. Lanza [FormatException] si hay
  /// caracteres que no son base32.
  static Uint8List decodificar(String texto) {
    final s = texto.toUpperCase().replaceAll(RegExp(r'[\s\-]'), '');
    final out = <int>[];
    var buffer = 0, bits = 0;
    for (final c in s.split('')) {
      final v = _alfabeto.indexOf(c);
      if (v < 0) throw const FormatException('Carácter no válido');
      buffer = ((buffer << 5) | v) & 0xFFFF;
      bits += 5;
      if (bits >= 8) {
        out.add((buffer >> (bits - 8)) & 0xFF);
        bits -= 8;
      }
    }
    return Uint8List.fromList(out);
  }

  /// "ABCDEFGHIJ" → "ABCDE-FGHIJ".
  static String agrupar(String s, [int tam = 5]) =>
      [for (var i = 0; i < s.length; i += tam) s.substring(i, i + tam > s.length ? s.length : i + tam)].join('-');
}
