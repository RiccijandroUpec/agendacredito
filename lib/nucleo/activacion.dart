/// Activación por equipo: la app solo funciona en las tablets que el autor
/// activó. Cada tablet muestra un "código de equipo" (derivado del
/// ANDROID_ID, que cambia con otra tablet o con un restablecimiento de
/// fábrica) y el autor le responde con un código firmado con su clave
/// privada (`dart run tool/activar.dart`). Si alguien copia el APK a otra
/// tablet, ese código no le sirve.
///
/// No depende de Flutter para que la herramienta de PC la pueda usar.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as c;
import 'package:pointycastle/export.dart';

import 'base32.dart';
import 'clave_publica.dart';

class ActivacionException implements Exception {
  final String mensaje;
  const ActivacionException(this.mensaje);
  @override
  String toString() => mensaje;
}

class Activacion {
  static const prefijo = 'AC1';
  static final _dominio = ECDomainParameters('secp256r1');
  static final _contexto = ascii.encode('AGENDA-CREDITO-ACTIVACION-1');

  /// 8 bytes que identifican a la tablet, sin revelar el ANDROID_ID.
  static Uint8List huellaEquipo(String androidId) =>
      Uint8List.fromList(c.sha256.convert(utf8.encode('AGENDA-CREDITO-EQUIPO|$androidId')).bytes.sublist(0, 8));

  /// Lo que la tablet le muestra al usuario: "ABCDE-FGHIJ-KLM".
  static String codigoEquipo(String androidId) => Base32.agrupar(Base32.codificar(huellaEquipo(androidId)));

  static Uint8List huellaDesdeCodigo(String codigoEquipo) {
    final Uint8List b;
    try {
      b = Base32.decodificar(codigoEquipo);
    } on FormatException {
      throw const ActivacionException('El código de equipo tiene letras que no corresponden.');
    }
    if (b.length != 8) throw const ActivacionException('El código de equipo debe tener 13 letras/números.');
    return b;
  }

  /// Firma la huella del equipo. Solo en el PC del autor.
  static String emitir(String codigoEquipo, Uint8List clavePrivada) {
    final huella = huellaDesdeCodigo(codigoEquipo);
    final firmador = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64))
      ..init(true, PrivateKeyParameter<ECPrivateKey>(ECPrivateKey(_entero(clavePrivada), _dominio)));
    final firma = firmador.generateSignature(_mensaje(huella)) as ECSignature;
    final b32 = Base32.codificar([..._bytes32(firma.r), ..._bytes32(firma.s)]);
    return '$prefijo-${Base32.agrupar(b32)}';
  }

  /// true si [codigo] fue emitido para esta tablet.
  static bool verificar(String codigo, String androidId, {Uint8List? clavePublica}) {
    final texto = codigo.trim().toUpperCase();
    if (!texto.startsWith(prefijo)) return false;
    final Uint8List firma;
    try {
      firma = Base32.decodificar(texto.substring(prefijo.length));
    } on FormatException {
      return false;
    }
    if (firma.length != 64) return false;
    try {
      final q = _dominio.curve.decodePoint(clavePublica ?? _hex(clavePublicaAutor));
      final verificador = ECDSASigner(SHA256Digest())..init(false, PublicKeyParameter<ECPublicKey>(ECPublicKey(q, _dominio)));
      return verificador.verifySignature(
        _mensaje(huellaEquipo(androidId)),
        ECSignature(_entero(firma.sublist(0, 32)), _entero(firma.sublist(32))),
      );
    } catch (_) {
      return false;
    }
  }

  /// Par nuevo: (privada de 32 bytes, pública sin comprimir de 65).
  static (Uint8List, Uint8List) generarClaves() {
    final semilla = Random.secure();
    final aleatorio = FortunaRandom()..seed(KeyParameter(Uint8List.fromList(List.generate(32, (_) => semilla.nextInt(256)))));
    final par = (ECKeyGenerator()..init(ParametersWithRandom(ECKeyGeneratorParameters(_dominio), aleatorio))).generateKeyPair();
    return (_bytes32(par.privateKey.d!), par.publicKey.Q!.getEncoded(false));
  }

  static Uint8List _mensaje(Uint8List huella) => Uint8List.fromList([..._contexto, ...huella]);

  static BigInt _entero(List<int> b) => b.fold(BigInt.zero, (a, x) => (a << 8) | BigInt.from(x));

  static Uint8List _bytes32(BigInt n) {
    final r = Uint8List(32);
    for (var i = 31; i >= 0; i--) {
      r[i] = (n & BigInt.from(0xFF)).toInt();
      n >>= 8;
    }
    return r;
  }

  static Uint8List _hex(String h) =>
      Uint8List.fromList([for (var i = 0; i < h.length; i += 2) int.parse(h.substring(i, i + 2), radix: 16)]);
}
