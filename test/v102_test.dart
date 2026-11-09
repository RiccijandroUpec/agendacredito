import 'package:agenda_credito/datos/modelo.dart';
import 'package:agenda_credito/datos/repositorio.dart';
import 'package:agenda_credito/servicios/sri.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('migra una base 1.0.x: agrega ciudad y documento sin perder clientes', () async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute('''CREATE TABLE clientes(id TEXT PRIMARY KEY, cedula TEXT UNIQUE, nombre TEXT NOT NULL DEFAULT '',
            nombre_sri INTEGER NOT NULL DEFAULT 0, telefono TEXT NOT NULL DEFAULT '', nota TEXT NOT NULL DEFAULT '',
            estado TEXT NOT NULL, monto REAL, fecha_consulta TEXT, fecha_visita TEXT, creado_en TEXT NOT NULL,
            actualizado_en TEXT NOT NULL)''');
          final t = DateTime.now().toIso8601String();
          await db.insert('clientes', {'id': 'a', 'cedula': '1710034065', 'estado': 'aprobado', 'creado_en': t, 'actualizado_en': t});
          await db.insert('clientes', {'id': 'b', 'nombre': 'Luis', 'estado': 'pendiente_cedula', 'creado_en': t, 'actualizado_en': t});
        },
      ),
    );
    await Repositorio.migrar(db, 1, 2);
    final repo = Repositorio(db);
    final a = (await repo.porId('a'))!, b = (await repo.porId('b'))!;
    expect(a.documento, isTrue);
    expect(a.pendiente, isFalse);
    expect(b.documento, isFalse);
    expect(b.pendiente, isTrue);
    await db.close();
  });

  test('cédula sin documento queda pendiente y sale al traerlo', () async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: Repositorio.version, onCreate: Repositorio.crear),
    );
    final repo = Repositorio(db);
    final ahora = DateTime.now();
    final c = await repo.registrar(
      Cliente(
        id: Repositorio.nuevoId(),
        cedula: '0926687856',
        ciudad: 'Ibarra',
        documento: false,
        estado: Estado.porConsultar,
        creadoEn: ahora,
        actualizadoEn: ahora,
      ),
    );
    expect(c.pendiente, isTrue);
    expect((await repo.ciudades()), ['Ibarra']);
    final d = await repo.marcarDocumento(c.id);
    expect(d.pendiente, isFalse);
    expect((await repo.eventos(c.id)).first.tipo, 'documento');
    expect((await repo.verificarSellos()).$2, isNull);
    await db.close();
  });

  test('SRI: nombre y ciudad desde la dirección; sin RUC devuelve null', () async {
    final cliente = MockClient((r) async {
      if (!r.url.toString().contains('0450022686001')) return http.Response('', 200);
      if (r.url.path.contains('ConsolidadoContribuyente')) {
        return http.Response('[{"razonSocial":"RODRIGUEZ VILLARREAL RICHARD","actividadEconomicaPrincipal":"VENTA"}]', 200);
      }
      return http.Response('[{"matriz":"SI","direccionCompleta":"IMBABURA / IBARRA / CARANQUI / CALLE"}]', 200);
    });
    final d = (await Sri.consultar('0450022686', cliente: cliente))!;
    expect(d.nombre, 'RODRIGUEZ VILLARREAL RICHARD');
    expect(d.ciudad, 'Ibarra');
    expect(d.provincia, 'Imbabura');
    expect(await Sri.consultar('1710034065', cliente: cliente), isNull);
    expect(Sri.titulo('SANTO DOMINGO DE LOS TSACHILAS'), 'Santo Domingo de los Tsachilas');
  });
}
