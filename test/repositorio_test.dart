import 'package:agenda_credito/datos/modelo.dart';
import 'package:agenda_credito/datos/repositorio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Repositorio repo;
  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: Repositorio.version, onCreate: Repositorio.crear),
    );
    repo = Repositorio(db);
  });
  tearDown(() => db.close());

  Cliente nuevo({String? cedula, String nombre = '', Estado estado = Estado.aprobado, double? monto}) {
    final ahora = DateTime.now();
    return Cliente(
      id: Repositorio.nuevoId(),
      cedula: cedula,
      nombre: nombre,
      estado: cedula == null ? Estado.pendienteCedula : estado,
      monto: monto,
      fechaConsulta: cedula == null ? null : Dia.hoy(),
      creadoEn: ahora,
      actualizadoEn: ahora,
    );
  }

  test('registro, consulta repetida y sellos intactos', () async {
    final c = await repo.registrar(nuevo(cedula: '1710034065', nombre: 'Ana', monto: 500));
    expect(() => repo.registrar(nuevo(cedula: '1710034065')), throwsStateError);
    await repo.registrarConsulta(c.id, estado: Estado.negado, fechaConsulta: Dia.hoy(), notaExtra: 'Volvió');
    final x = (await repo.porCedula('1710034065'))!;
    expect(x.estado, Estado.negado);
    expect(x.monto, isNull);
    expect(x.nota, 'Volvió');
    expect((await repo.eventos(c.id)).map((e) => e.tipo), ['consulta', 'registro']);
    expect(await repo.verificarSellos(), (2, null));
  });

  test('pendiente trae la cédula y se une con el registro de la burbuja', () async {
    final p = await repo.registrar(nuevo(nombre: 'Luis Pérez'));
    expect(p.pendiente, isTrue);
    // Desde la burbuja se registró la misma persona con cédula.
    final b = await repo.registrar(nuevo(cedula: '0926687856', monto: 300));
    expect(() => repo.agregarCedula(p.id, '0926687856'), throwsStateError);
    final u = await repo.unir(p.id, b.id);
    expect(u.nombre, 'Luis Pérez');
    expect(await repo.porId(p.id), isNull);
    final ev = await repo.eventos(b.id);
    expect(ev.map((e) => e.tipo), containsAll(['registro', 'unido']));
    expect(ev.where((e) => e.tipo == 'registro').length, 2); // la historia del pendiente se conserva
    expect((await repo.verificarSellos()).$2, isNull);
  });

  test('alterar la base por fuera rompe los sellos', () async {
    final c = await repo.registrar(nuevo(cedula: '1710034065'));
    await repo.marcarAtendido(c.id);
    await db.rawUpdate("UPDATE eventos SET fecha = '2020-01-01T00:00:00.000' WHERE tipo = 'registro'");
    expect((await repo.verificarSellos()).$2, 1);
  });

  test('editar no cambia la fecha de registro; exportar e importar', () async {
    final c = await repo.registrar(nuevo(cedula: '1710034065', nombre: 'Ana'));
    final e = await repo.editar(
      Cliente(
        id: c.id,
        cedula: c.cedula,
        nombre: 'Ana María',
        estado: c.estado,
        creadoEn: DateTime(2000),
        actualizadoEn: DateTime.now(),
      ),
    );
    expect(e.creadoEn, c.creadoEn);
    expect(e.nombre, 'Ana María');
    final datos = await repo.exportar();
    await repo.eliminar(c.id);
    expect(await repo.todos(), isEmpty);
    expect(await repo.importar(datos.cast<String, dynamic>()), 1);
    expect((await repo.todos()).single.nombre, 'Ana María');
    expect((await repo.verificarSellos()).$2, isNull);
  });
}
