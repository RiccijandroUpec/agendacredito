/// Cifrado de respaldos y hash del PIN. Puro Dart (sin Flutter) para poder
/// probarlo y correrlo en un isolate.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

class Cifrado {
  static const _magia = 'AGCR1';
  static const iteracionesRespaldo = 150000;
  static const iteracionesPin = 60000;

  static Uint8List aleatorio(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
  }

  static Uint8List derivar(String clave, Uint8List sal, int iteraciones) {
    final kdf = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))..init(Pbkdf2Parameters(sal, iteraciones, 32));
    return kdf.process(Uint8List.fromList(utf8.encode(clave)));
  }

  /// AES-256-GCM: `AGCR1 | sal(16) | nonce(12) | cifrado+etiqueta`.
  static Uint8List cifrar(Uint8List datos, String clave) {
    final sal = aleatorio(16), nonce = aleatorio(12);
    final gcm = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(derivar(clave, sal, iteracionesRespaldo)), 128, nonce, ascii.encode(_magia)));
    return Uint8List.fromList([...ascii.encode(_magia), ...sal, ...nonce, ...gcm.process(datos)]);
  }

  /// Lanza [FormatException] si no es un respaldo o la clave es incorrecta.
  static Uint8List descifrar(Uint8List archivo, String clave) {
    if (archivo.length < 5 + 16 + 12 + 16 || ascii.decode(archivo.sublist(0, 5), allowInvalid: true) != _magia) {
      throw const FormatException('Ese archivo no es un respaldo de Agenda de Crédito.');
    }
    final sal = archivo.sublist(5, 21), nonce = archivo.sublist(21, 33);
    final gcm = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(derivar(clave, sal, iteracionesRespaldo)), 128, nonce, ascii.encode(_magia)));
    try {
      return gcm.process(archivo.sublist(33));
    } on InvalidCipherTextException {
      throw const FormatException('Clave de respaldo incorrecta.');
    }
  }

  /// "sal:hash" en base64.
  static String hashPin(String pin, [Uint8List? sal]) {
    final s = sal ?? aleatorio(16);
    return '${base64.encode(s)}:${base64.encode(derivar(pin, s, iteracionesPin))}';
  }

  static bool verificarPin(String pin, String guardado) {
    final partes = guardado.split(':');
    if (partes.length != 2) return false;
    final esperado = base64.decode(partes[1]);
    final calculado = derivar(pin, base64.decode(partes[0]), iteracionesPin);
    if (esperado.length != calculado.length) return false;
    var dif = 0;
    for (var i = 0; i < esperado.length; i++) {
      dif |= esperado[i] ^ calculado[i];
    }
    return dif == 0;
  }
}
