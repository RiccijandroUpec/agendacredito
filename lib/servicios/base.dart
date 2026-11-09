import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../datos/repositorio.dart';
import '../nucleo/cifrado.dart';

const almacen = FlutterSecureStorage();

/// La base va cifrada con SQLCipher. La clave es aleatoria y vive en el
/// almacén seguro de Android (Keystore): aunque saquen el archivo de la
/// tablet, no se puede leer.
class Base {
  static Repositorio? _repo;
  static Future<Repositorio>? _abriendo;

  /// Avisa a las pantallas que algo cambió y deben recargar.
  static final cambios = ValueNotifier<int>(0);
  static void avisar() => cambios.value++;

  static Repositorio get repo => _repo!;

  static Future<Repositorio> abrir() => _abriendo ??= _abrir();

  static Future<Repositorio> _abrir() async {
    var clave = await almacen.read(key: 'clave_base');
    if (clave == null) {
      clave = base64.encode(Cifrado.aleatorio(32));
      await almacen.write(key: 'clave_base', value: clave);
    }
    final ruta = p.join(await getDatabasesPath(), 'agenda.db');
    final db = await openDatabase(
      ruta,
      password: clave,
      version: Repositorio.version,
      onCreate: Repositorio.crear,
      // La burbuja y la app abren la base a la vez: que esperen en vez de fallar.
      onConfigure: (db) async => db.rawQuery('PRAGMA busy_timeout = 5000'),
    );
    return _repo = Repositorio(db);
  }
}
