// Activación de tablets. Se corre en el PC del autor, desde la raíz del
// proyecto:
//
//   dart run tool/activar.dart claves                     crea el par de claves (una sola vez)
//   dart run tool/activar.dart <CODIGO-EQUIPO> [nota]     emite el código de activación
//   dart run tool/activar.dart lista                      tablets activadas
//
// La clave privada y el registro quedan en ~/.agenda-credito-licencias, fuera
// del repositorio. Si se pierde la clave privada no se pueden activar más
// tablets con esta versión de la app: respáldala.
import 'dart:io';
import 'dart:typed_data';

import 'package:agenda_credito/nucleo/activacion.dart';

final _sep = Platform.pathSeparator;
final _carpeta = Directory(
    '${Platform.environment['USERPROFILE'] ?? Platform.environment['HOME']}$_sep.agenda-credito-licencias');
File get _privada => File('${_carpeta.path}${_sep}clave_privada.txt');
File get _registro => File('${_carpeta.path}${_sep}registro.csv');

void main(List<String> args) {
  try {
    switch (args) {
      case ['claves']:
        _claves();
      case ['lista']:
        stdout.write(_registro.existsSync() ? _registro.readAsStringSync() : 'Todavía no hay tablets activadas.\n');
      case [final equipo, ...final nota] when !equipo.startsWith('-'):
        _emitir(equipo, nota.join(' '));
      default:
        stderr.writeln('Uso: dart run tool/activar.dart claves | <CODIGO-EQUIPO> [nota] | lista');
        exitCode = 64;
    }
  } on ActivacionException catch (e) {
    stderr.writeln(e.mensaje);
    exitCode = 1;
  }
}

void _claves() {
  if (_privada.existsSync()) {
    stderr.writeln('Ya existe ${_privada.path}. No se reemplaza: dejaría sin activación a todas las tablets.');
    exitCode = 1;
    return;
  }
  final (privada, publica) = Activacion.generarClaves();
  _carpeta.createSync(recursive: true);
  _privada.writeAsStringSync(_hex(privada));
  File('lib/nucleo/clave_publica.dart').writeAsStringSync('''
// Generado por `dart run tool/activar.dart claves`. Es la clave pública: se
// puede publicar. La privada vive solo en el PC del autor.
const clavePublicaAutor = '${_hex(publica)}';
''');
  stdout.writeln('Clave privada guardada en ${_privada.path} (respáldala y no la compartas).');
  stdout.writeln('Clave pública escrita en lib/nucleo/clave_publica.dart.');
}

void _emitir(String equipo, String nota) {
  if (!_privada.existsSync()) throw const ActivacionException('Primero crea las claves: dart run tool/activar.dart claves');
  final clave = _privada.readAsStringSync().trim();
  final codigo = Activacion.emitir(
      equipo, Uint8List.fromList([for (var i = 0; i < clave.length; i += 2) int.parse(clave.substring(i, i + 2), radix: 16)]));
  if (!_registro.existsSync()) _registro.writeAsStringSync('fecha,equipo,nota,codigo\n');
  final limpio = equipo.trim().toUpperCase();
  _registro.writeAsStringSync(
      '${DateTime.now().toIso8601String().substring(0, 10)},$limpio,"${nota.replaceAll('"', "'")}",$codigo\n',
      mode: FileMode.append);
  stdout.writeln('Equipo $limpio\n\nCódigo de activación (cópialo completo y pégalo en la tablet):\n\n$codigo');
}

String _hex(Uint8List b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
