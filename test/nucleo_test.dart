import 'dart:convert';
import 'dart:typed_data';

import 'package:agenda_credito/nucleo/activacion.dart';
import 'package:agenda_credito/nucleo/base32.dart';
import 'package:agenda_credito/nucleo/cifrado.dart';
import 'package:agenda_credito/nucleo/identificacion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Cédula', () {
    test('válidas', () {
      for (final c in [
        '1710034065',
        '0926687856',
        '0102030405'.substring(0, 9) + _dv('010203040'),
        '3050000008'.substring(0, 9) + _dv('305000000'),
      ]) {
        expect(Identificacion.cedulaValida(c), isTrue, reason: c);
      }
    });
    test('inválidas', () {
      expect(Identificacion.cedulaValida('1710034066'), isFalse); // dígito verificador
      expect(Identificacion.cedulaValida('2510034065'), isFalse); // provincia 25
      expect(Identificacion.cedulaValida('1770034065'), isFalse); // tercer dígito 7
      expect(Identificacion.cedulaValida('171003406'), isFalse);
      expect(Identificacion.errorCedula('171003406'), contains('10 dígitos'));
      expect(Identificacion.errorCedula('1710034065'), isNull);
    });
  });

  test('base32 ida y vuelta', () {
    final b = Uint8List.fromList(List.generate(64, (i) => i * 7 % 256));
    expect(Base32.decodificar(Base32.agrupar(Base32.codificar(b))), b);
  });

  group('Activación', () {
    final (privada, publica) = Activacion.generarClaves();
    const id = 'a1b2c3d4e5f60718';

    test('el código sirve solo en su tablet', () {
      final equipo = Activacion.codigoEquipo(id);
      expect(equipo.replaceAll('-', '').length, 13);
      final codigo = Activacion.emitir(equipo.toLowerCase(), privada);
      expect(codigo, startsWith('AC1-'));
      expect(Activacion.verificar(codigo, id, clavePublica: publica), isTrue);
      expect(Activacion.verificar(' ${codigo.toLowerCase()}\n', id, clavePublica: publica), isTrue);
      expect(Activacion.verificar(codigo, 'otra-tablet', clavePublica: publica), isFalse);
      final roto = codigo.substring(0, codigo.length - 2) + (codigo.endsWith('AA') ? 'BB' : 'AA');
      expect(Activacion.verificar(roto, id, clavePublica: publica), isFalse);
    });

    test('código firmado con otra clave no sirve', () {
      final (otra, _) = Activacion.generarClaves();
      final codigo = Activacion.emitir(Activacion.codigoEquipo(id), otra);
      expect(Activacion.verificar(codigo, id, clavePublica: publica), isFalse);
    });
  });

  group('Cifrado', () {
    test('respaldo ida y vuelta y clave incorrecta', () {
      final datos = Uint8List.fromList(utf8.encode('{"clientes":[]}'));
      final c = Cifrado.cifrar(datos, 'clave segura');
      expect(Cifrado.descifrar(c, 'clave segura'), datos);
      expect(() => Cifrado.descifrar(c, 'otra'), throwsFormatException);
      expect(
        () => Cifrado.descifrar(Uint8List.fromList(utf8.encode('hola mundo hola mundo hola mundo hola mundo hola')), 'x'),
        throwsFormatException,
      );
    });
    test('PIN', () {
      final h = Cifrado.hashPin('482915');
      expect(Cifrado.verificarPin('482915', h), isTrue);
      expect(Cifrado.verificarPin('482916', h), isFalse);
    });
  });
}

/// Dígito verificador para armar cédulas de prueba.
String _dv(String nueve) {
  var s = 0;
  for (var i = 0; i < 9; i++) {
    var v = int.parse(nueve[i]) * (i.isEven ? 2 : 1);
    if (v > 9) v -= 9;
    s += v;
  }
  return '${(10 - s % 10) % 10}';
}
