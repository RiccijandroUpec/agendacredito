import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../nucleo/cifrado.dart';
import '../nucleo/sello.dart';
import 'modelo.dart';

class Repositorio {
  final Database db;
  Repositorio(this.db);

  static const version = 2;

  static Future<void> crear(Database db, int _) async {
    await db.execute('''
      CREATE TABLE clientes(
        id TEXT PRIMARY KEY,
        cedula TEXT UNIQUE,
        nombre TEXT NOT NULL DEFAULT '',
        nombre_sri INTEGER NOT NULL DEFAULT 0,
        telefono TEXT NOT NULL DEFAULT '',
        nota TEXT NOT NULL DEFAULT '',
        ciudad TEXT NOT NULL DEFAULT '',
        documento INTEGER NOT NULL DEFAULT 1,
        estado TEXT NOT NULL,
        monto REAL,
        fecha_consulta TEXT,
        fecha_visita TEXT,
        creado_en TEXT NOT NULL,
        actualizado_en TEXT NOT NULL)''');
    await db.execute('''
      CREATE TABLE eventos(
        n INTEGER PRIMARY KEY AUTOINCREMENT,
        cliente_id TEXT NOT NULL,
        tipo TEXT NOT NULL,
        fecha TEXT NOT NULL,
        detalle TEXT NOT NULL,
        hash TEXT NOT NULL)''');
    await db.execute('CREATE INDEX eventos_cliente ON eventos(cliente_id)');
    await db.execute('CREATE TABLE ajustes(clave TEXT PRIMARY KEY, valor TEXT)');
  }

  /// 1.0.x → 1.0.2: ciudad y "trajo el documento".
  static Future<void> migrar(Database db, int antes, int ahora) async {
    if (antes < 2) {
      await db.execute("ALTER TABLE clientes ADD COLUMN ciudad TEXT NOT NULL DEFAULT ''");
      await db.execute('ALTER TABLE clientes ADD COLUMN documento INTEGER NOT NULL DEFAULT 1');
      await db.execute("UPDATE clientes SET documento = 0 WHERE estado = 'pendiente_cedula' OR cedula IS NULL");
    }
  }

  /// Ciudades ya usadas, para sugerirlas primero.
  Future<List<String>> ciudades() async => [
    for (final f in await db.rawQuery(
      "SELECT ciudad, COUNT(*) n FROM clientes WHERE ciudad <> '' GROUP BY ciudad COLLATE NOCASE ORDER BY n DESC",
    ))
      f['ciudad'] as String,
  ];

  static String nuevoId() => Cifrado.aleatorio(12).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  // ---------- Lectura ----------

  Future<List<Cliente>> todos() async =>
      (await db.query('clientes', orderBy: 'actualizado_en DESC')).map(Cliente.deFila).toList();

  Future<Cliente?> porId(String id) async {
    final f = await db.query('clientes', where: 'id = ?', whereArgs: [id]);
    return f.isEmpty ? null : Cliente.deFila(f.first);
  }

  Future<Cliente?> porCedula(String cedula) async {
    final f = await db.query('clientes', where: 'cedula = ?', whereArgs: [cedula]);
    return f.isEmpty ? null : Cliente.deFila(f.first);
  }

  /// Historia del cliente, incluida la de los registros que se le unieron.
  Future<List<Evento>> eventos(String clienteId) async {
    final ids = <String>{clienteId};
    var nuevos = [clienteId];
    while (nuevos.isNotEmpty) {
      final unidos = await db.query(
        'eventos',
        where: "tipo = 'unido' AND cliente_id IN (${List.filled(nuevos.length, '?').join(',')})",
        whereArgs: nuevos,
      );
      nuevos = [
        for (final u in unidos)
          if ((jsonDecode(u['detalle'] as String) as Map)['origen'] case final String o when ids.add(o)) o,
      ];
    }
    return (await db.query(
      'eventos',
      where: 'cliente_id IN (${List.filled(ids.length, '?').join(',')})',
      whereArgs: ids.toList(),
      orderBy: 'n DESC',
    )).map(_evento).toList();
  }

  Evento _evento(Map<String, Object?> f) => Evento(
    f['n'] as int,
    f['cliente_id'] as String,
    f['tipo'] as String,
    DateTime.parse(f['fecha'] as String),
    jsonDecode(f['detalle'] as String),
    f['hash'] as String,
  );

  /// Sello del primer registro del cliente (prueba de quién llegó primero).
  Future<Evento?> primerRegistro(String clienteId) async {
    final f = await db.query(
      'eventos',
      where: "cliente_id = ? AND tipo = 'registro'",
      whereArgs: [clienteId],
      orderBy: 'n',
      limit: 1,
    );
    return f.isEmpty ? null : _evento(f.first);
  }

  // ---------- Escritura ----------

  Future<void> _sellar(Transaction tx, String clienteId, String tipo, Map<String, Object?> detalle, DateTime fecha) async {
    final ult = await tx.rawQuery('SELECT hash FROM eventos ORDER BY n DESC LIMIT 1');
    final anterior = ult.isEmpty ? Sello.inicial : ult.first['hash'] as String;
    final d = jsonEncode(detalle);
    final f = fecha.toIso8601String();
    await tx.insert('eventos', {
      'cliente_id': clienteId,
      'tipo': tipo,
      'fecha': f,
      'detalle': d,
      'hash': Sello.calcular(anterior: anterior, clienteId: clienteId, tipo: tipo, fecha: f, detalle: d),
    });
  }

  Map<String, Object?> _detalleConsulta(Cliente c) => {
    'estado': c.estado.clave,
    'monto': c.monto,
    'fecha_consulta': c.fechaConsulta == null ? null : Dia.texto(c.fechaConsulta!),
    'fecha_visita': c.fechaVisita == null ? null : Dia.texto(c.fechaVisita!),
  };

  /// Cliente nuevo. Si trae cédula y ya existe, lanza [StateError].
  Future<Cliente> registrar(Cliente c) async {
    await db.transaction((tx) async {
      if (c.cedula != null) {
        final existe = await tx.query('clientes', where: 'cedula = ?', whereArgs: [c.cedula]);
        if (existe.isNotEmpty) throw StateError('La cédula ${c.cedula} ya está registrada');
      }
      await tx.insert('clientes', c.aFila());
      await _sellar(tx, c.id, 'registro', {
        'cedula': c.cedula,
        'nombre': c.nombre,
        'ciudad': c.ciudad,
        'documento': c.documento,
        ..._detalleConsulta(c),
      }, c.creadoEn);
    });
    return c;
  }

  /// Nueva consulta de crédito de un cliente que ya existe.
  Future<Cliente> registrarConsulta(
    String id, {
    required Estado estado,
    double? monto,
    required DateTime fechaConsulta,
    DateTime? fechaVisita,
    String? nombre,
    bool? nombreSri,
    String? telefono,
    String? notaExtra,
    String? ciudad,
    bool? documento,
  }) async {
    late Cliente nuevo;
    await db.transaction((tx) async {
      final f = await tx.query('clientes', where: 'id = ?', whereArgs: [id]);
      if (f.isEmpty) throw StateError('El cliente ya no existe');
      final c = Cliente.deFila(f.first);
      final ahora = DateTime.now();
      nuevo = c.copiar(
        estado: estado,
        monto: () => estado == Estado.aprobado ? monto : null,
        fechaConsulta: () => fechaConsulta,
        fechaVisita: () => fechaVisita,
        nombre: (nombre != null && nombre.trim().isNotEmpty && c.nombre.trim().isEmpty) ? nombre.trim() : null,
        nombreSri: (nombre != null && c.nombre.trim().isEmpty) ? nombreSri : null,
        telefono: (telefono != null && telefono.trim().isNotEmpty) ? telefono.trim() : null,
        nota: _sumarNota(c.nota, notaExtra),
        ciudad: (ciudad != null && ciudad.trim().isNotEmpty) ? ciudad.trim() : null,
        documento: documento,
        actualizadoEn: ahora,
      );
      await tx.update('clientes', nuevo.aFila(), where: 'id = ?', whereArgs: [id]);
      await _sellar(tx, id, 'consulta', _detalleConsulta(nuevo), ahora);
    });
    return nuevo;
  }

  static String? _sumarNota(String actual, String? extra) {
    final e = extra?.trim() ?? '';
    if (e.isEmpty || actual.contains(e)) return null;
    return actual.trim().isEmpty ? e : '${actual.trim()}\n$e';
  }

  /// Un pendiente trajo la cédula. Si esa cédula ya existe en otro
  /// registro, lanza [StateError] (usar [unir]).
  Future<Cliente> agregarCedula(String id, String cedula, {String? nombre, bool nombreSri = false}) async {
    late Cliente nuevo;
    await db.transaction((tx) async {
      final otro = await tx.query('clientes', where: 'cedula = ? AND id <> ?', whereArgs: [cedula, id]);
      if (otro.isNotEmpty) throw StateError('Esa cédula ya está en otro registro');
      final c = Cliente.deFila((await tx.query('clientes', where: 'id = ?', whereArgs: [id])).first);
      final ahora = DateTime.now();
      nuevo = c.copiar(
        cedula: cedula,
        nombre: (nombre != null && nombre.trim().isNotEmpty) ? nombre.trim() : null,
        nombreSri: nombre != null && nombre.trim().isNotEmpty ? nombreSri : null,
        estado: c.estado == Estado.pendienteCedula ? Estado.porConsultar : null,
        actualizadoEn: ahora,
      );
      await tx.update('clientes', nuevo.aFila(), where: 'id = ?', whereArgs: [id]);
      await _sellar(tx, id, 'cedula', {'cedula': cedula}, ahora);
    });
    return nuevo;
  }

  /// Une el registro [origenId] (normalmente un pendiente sin cédula) dentro
  /// de [destinoId]: suma teléfono y nota y borra el origen. La historia del
  /// origen se conserva en la cadena de sellos.
  Future<Cliente> unir(String origenId, String destinoId) async {
    late Cliente nuevo;
    await db.transaction((tx) async {
      final o = Cliente.deFila((await tx.query('clientes', where: 'id = ?', whereArgs: [origenId])).first);
      final d = Cliente.deFila((await tx.query('clientes', where: 'id = ?', whereArgs: [destinoId])).first);
      final ahora = DateTime.now();
      nuevo = d.copiar(
        nombre: d.nombre.trim().isEmpty ? o.nombre : null,
        telefono: d.telefono.trim().isEmpty ? o.telefono : null,
        nota: _sumarNota(d.nota, o.nota),
        actualizadoEn: ahora,
      );
      await tx.update('clientes', nuevo.aFila(), where: 'id = ?', whereArgs: [destinoId]);
      await tx.delete('clientes', where: 'id = ?', whereArgs: [origenId]);
      await _sellar(tx, destinoId, 'unido', {
        'origen': origenId,
        'nombre': o.nombre,
        'origen_creado': o.creadoEn.toIso8601String(),
      }, ahora);
    });
    return nuevo;
  }

  /// Trajo la cédula física: sale de Pendientes.
  Future<Cliente> marcarDocumento(String id) async {
    late Cliente nuevo;
    await db.transaction((tx) async {
      final c = Cliente.deFila((await tx.query('clientes', where: 'id = ?', whereArgs: [id])).first);
      final ahora = DateTime.now();
      nuevo = c.copiar(documento: true, actualizadoEn: ahora);
      await tx.update('clientes', nuevo.aFila(), where: 'id = ?', whereArgs: [id]);
      await _sellar(tx, id, 'documento', {'cedula': c.cedula}, ahora);
    });
    return nuevo;
  }

  Future<Cliente> marcarAtendido(String id) async {
    late Cliente nuevo;
    await db.transaction((tx) async {
      final c = Cliente.deFila((await tx.query('clientes', where: 'id = ?', whereArgs: [id])).first);
      final ahora = DateTime.now();
      nuevo = c.copiar(estado: Estado.atendido, actualizadoEn: ahora);
      await tx.update('clientes', nuevo.aFila(), where: 'id = ?', whereArgs: [id]);
      await _sellar(tx, id, 'atendido', {'monto': c.monto}, ahora);
    });
    return nuevo;
  }

  /// Guarda cambios de datos (no de la consulta). La fecha de registro no
  /// se puede cambiar.
  Future<Cliente> editar(Cliente c) async {
    late Cliente nuevo;
    await db.transaction((tx) async {
      final antes = Cliente.deFila((await tx.query('clientes', where: 'id = ?', whereArgs: [c.id])).first);
      if (c.cedula != null && c.cedula != antes.cedula) {
        final otro = await tx.query('clientes', where: 'cedula = ? AND id <> ?', whereArgs: [c.cedula, c.id]);
        if (otro.isNotEmpty) throw StateError('Esa cédula ya está en otro registro');
      }
      final ahora = DateTime.now();
      nuevo = Cliente(
        id: antes.id,
        cedula: c.cedula,
        nombre: c.nombre.trim(),
        nombreSri: c.nombre.trim() == antes.nombre ? antes.nombreSri : false,
        telefono: c.telefono.trim(),
        nota: c.nota.trim(),
        ciudad: c.ciudad.trim(),
        documento: c.documento,
        estado: c.cedula == null ? Estado.pendienteCedula : (c.estado == Estado.pendienteCedula ? Estado.porConsultar : c.estado),
        monto: c.monto,
        fechaConsulta: c.fechaConsulta,
        fechaVisita: c.fechaVisita,
        creadoEn: antes.creadoEn,
        actualizadoEn: ahora,
      );
      final a = antes.aFila(), n = nuevo.aFila();
      final campos = [
        for (final k in [
          'cedula',
          'nombre',
          'telefono',
          'ciudad',
          'documento',
          'nota',
          'estado',
          'monto',
          'fecha_consulta',
          'fecha_visita',
        ])
          if (a[k] != n[k]) k,
      ];
      if (campos.isEmpty) {
        nuevo = antes;
        return;
      }
      await tx.update('clientes', n, where: 'id = ?', whereArgs: [c.id]);
      await _sellar(tx, c.id, 'edicion', {'campos': campos, for (final k in campos) k: n[k]}, ahora);
    });
    return nuevo;
  }

  Future<void> eliminar(String id) async {
    await db.transaction((tx) async {
      final f = await tx.query('clientes', where: 'id = ?', whereArgs: [id]);
      if (f.isEmpty) return;
      final c = Cliente.deFila(f.first);
      await tx.delete('clientes', where: 'id = ?', whereArgs: [id]);
      await _sellar(tx, id, 'eliminado', {'cedula': c.cedula, 'nombre': c.nombre}, DateTime.now());
    });
  }

  // ---------- Sellos ----------

  /// Recalcula la cadena. Devuelve (total de eventos, número del primer
  /// evento alterado o null si todo está bien).
  Future<(int, int?)> verificarSellos() async {
    final filas = await db.query('eventos', orderBy: 'n');
    var anterior = Sello.inicial;
    for (final f in filas) {
      final esperado = Sello.calcular(
        anterior: anterior,
        clienteId: f['cliente_id'] as String,
        tipo: f['tipo'] as String,
        fecha: f['fecha'] as String,
        detalle: f['detalle'] as String,
      );
      if (esperado != f['hash']) return (filas.length, f['n'] as int);
      anterior = f['hash'] as String;
    }
    return (filas.length, null);
  }

  // ---------- Ajustes ----------

  Future<String?> ajuste(String clave) async {
    final f = await db.query('ajustes', where: 'clave = ?', whereArgs: [clave]);
    return f.isEmpty ? null : f.first['valor'] as String?;
  }

  Future<void> guardarAjuste(String clave, String? valor) async {
    if (valor == null) {
      await db.delete('ajustes', where: 'clave = ?', whereArgs: [clave]);
    } else {
      await db.insert('ajustes', {'clave': clave, 'valor': valor}, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  // ---------- Respaldo ----------

  Future<Map<String, Object?>> exportar() async => {
    'app': 'agenda_credito',
    'version': version,
    'generado': DateTime.now().toIso8601String(),
    'clientes': await db.query('clientes'),
    'eventos': await db.query('eventos', orderBy: 'n'),
  };

  /// Reemplaza todo por el contenido del respaldo.
  Future<int> importar(Map<String, dynamic> datos) async {
    if (datos['app'] != 'agenda_credito') throw const FormatException('El archivo no es de Agenda de Crédito');
    final clientes = (datos['clientes'] as List).cast<Map<String, dynamic>>();
    final eventos = (datos['eventos'] as List).cast<Map<String, dynamic>>();
    await db.transaction((tx) async {
      await tx.delete('clientes');
      await tx.delete('eventos');
      final b = tx.batch();
      for (final c in clientes) {
        b.insert('clientes', c);
      }
      for (final e in eventos) {
        b.insert('eventos', e);
      }
      await b.commit(noResult: true);
    });
    return clientes.length;
  }
}
