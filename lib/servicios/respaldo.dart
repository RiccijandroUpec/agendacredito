import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../datos/modelo.dart';
import '../nucleo/cifrado.dart';
import 'base.dart';
import 'nativo.dart';

/// Respaldo cifrado (archivo .agenda) y exportación a Excel.
///
/// El respaldo se cifra con una "clave de respaldo" que elige el usuario: así
/// se puede restaurar en otra tablet si esta se pierde o se daña.
class Respaldo {
  static const extension = 'agenda';

  static Future<bool> tieneClave() async => (await almacen.read(key: 'clave_respaldo')) != null;
  static Future<void> guardarClave(String clave) => almacen.write(key: 'clave_respaldo', value: clave);

  static Future<DateTime?> ultimo() async => DateTime.tryParse(await Base.repo.ajuste('ultimo_respaldo') ?? '');
  static Future<DateTime?> ultimoEnviado() async => DateTime.tryParse(await Base.repo.ajuste('ultimo_envio') ?? '');

  static Future<bool> automaticoActivo() async => (await Base.repo.ajuste('respaldo_auto')) != '0';
  static Future<void> usarAutomatico(bool si) => Base.repo.guardarAjuste('respaldo_auto', si ? '1' : '0');

  static Future<Uint8List> _generar() async {
    final clave = await almacen.read(key: 'clave_respaldo');
    if (clave == null) throw StateError('Primero crea la clave de respaldo en Ajustes');
    final json = utf8.encode(jsonEncode(await Base.repo.exportar()));
    return Isolate.run(() => Cifrado.cifrar(Uint8List.fromList(gzip.encode(json)), clave));
  }

  static String _nombre() => 'agenda-credito-${Dia.texto(DateTime.now())}.$extension';

  /// Copia diaria en Descargas/AgendaCredito (sobrevive a desinstalar la app).
  /// No hace nada si ya se respaldó hoy o no hay clave.
  static Future<void> automatico() async {
    try {
      if (!await tieneClave() || !await automaticoActivo()) return;
      final u = await ultimo();
      final hoy = Dia.hoy();
      if (u != null && !u.isBefore(hoy) && (await Base.repo.ajuste('cambios_sin_respaldo')) != '1') return;
      if (await Nativo.guardarEnDescargas(_nombre(), await _generar())) {
        await Base.repo.guardarAjuste('ultimo_respaldo', DateTime.now().toIso8601String());
        await Base.repo.guardarAjuste('cambios_sin_respaldo', null);
      }
    } catch (_) {
      // El automático nunca molesta: el aviso de "sin respaldo" lo recuerda.
    }
  }

  /// Marca que hay datos nuevos, para que el automático de hoy los incluya.
  static Future<void> hayCambios() => Base.repo.guardarAjuste('cambios_sin_respaldo', '1');

  /// Genera el respaldo y abre "Compartir" (Drive, WhatsApp, correo...).
  static Future<void> enviar() async {
    final bytes = await _generar();
    final archivo = File(p.join((await getTemporaryDirectory()).path, _nombre()));
    await archivo.writeAsBytes(bytes, flush: true);
    await Nativo.guardarEnDescargas(_nombre(), bytes);
    final r = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(archivo.path, mimeType: 'application/octet-stream')],
        subject: 'Respaldo Agenda de Crédito ${Dia.texto(DateTime.now())}',
        text: 'Respaldo cifrado de la Agenda de Crédito. Para abrirlo hace falta la clave de respaldo.',
      ),
    );
    final ahora = DateTime.now().toIso8601String();
    await Base.repo.guardarAjuste('ultimo_respaldo', ahora);
    if (r.status != ShareResultStatus.dismissed) await Base.repo.guardarAjuste('ultimo_envio', ahora);
  }

  /// Lanza [FormatException] con un mensaje para el usuario si falla.
  static Future<int> restaurar(Uint8List archivo, String clave) async {
    final datos = await Isolate.run(() {
      final plano = Cifrado.descifrar(archivo, clave);
      return jsonDecode(utf8.decode(gzip.decode(plano))) as Map<String, dynamic>;
    });
    final n = await Base.repo.importar(datos);
    await guardarClave(clave);
    Base.avisar();
    return n;
  }

  /// CSV para Excel (separador ; y BOM, como lo abre Excel en español).
  static Future<void> exportarExcel() async {
    final clientes = await Base.repo.todos();
    String c(Object? v) {
      final s = '${v ?? ''}'.replaceAll('"', '""');
      return s.contains(RegExp(r'[;"\n]')) ? '"$s"' : s;
    }

    final sb = StringBuffer(
      '﻿Cédula;Nombre;Teléfono;Ciudad;Trajo documento;Estado;Cupo aprobado;Fecha consulta;Puede venir;Registrado;Nota\r\n',
    );
    for (final x in clientes) {
      sb.write(
        [
          // ="..." para que Excel no le quite el 0 inicial a la cédula.
          x.cedula == null ? '' : '="${x.cedula}"',
          c(x.nombre),
          c(x.telefono),
          c(x.ciudad),
          x.cedula != null && x.documento ? 'Sí' : 'No',
          c(x.estado.etiqueta),
          x.monto?.toStringAsFixed(2).replaceAll('.', ',') ?? '',
          x.fechaConsulta == null ? '' : Dia.texto(x.fechaConsulta!),
          x.fechaVisita == null ? '' : Dia.texto(x.fechaVisita!),
          x.creadoEn.toIso8601String().substring(0, 16).replaceAll('T', ' '),
          c(x.nota),
        ].join(';'),
      );
      sb.write('\r\n');
    }
    final archivo = File(p.join((await getTemporaryDirectory()).path, 'clientes-${Dia.texto(DateTime.now())}.csv'));
    await archivo.writeAsString(sb.toString(), flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(archivo.path, mimeType: 'text/csv')],
        subject: 'Clientes',
      ),
    );
  }
}
