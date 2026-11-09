import 'package:intl/intl.dart';

enum Estado {
  /// Solo registros viejos (1.0.x) guardados sin número de cédula.
  pendienteCedula('pendiente_cedula', 'Sin cédula'),
  aprobado('aprobado', 'Aprobado'),
  porConsultar('por_consultar', 'Por consultar'),
  negado('negado', 'Negado'),
  atendido('atendido', 'Ya vino');

  final String clave;
  final String etiqueta;
  const Estado(this.clave, this.etiqueta);

  static Estado desde(String c) => values.firstWhere((e) => e.clave == c, orElse: () => pendienteCedula);
}

/// Fechas sin hora como 'AAAA-MM-DD'.
class Dia {
  static String texto(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  static DateTime? leer(String? s) => s == null || s.isEmpty ? null : DateTime.tryParse(s);
  static DateTime hoy() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static String corto(DateTime d) => DateFormat('d MMM yyyy', 'es').format(d);

  /// "Hoy", "Mañana", "Ayer", "En 3 días", "Hace 5 días" o la fecha.
  static String relativo(DateTime d) {
    final dias = DateTime(d.year, d.month, d.day).difference(hoy()).inDays;
    return switch (dias) {
      0 => 'Hoy',
      1 => 'Mañana',
      -1 => 'Ayer',
      > 1 && <= 6 => 'En $dias días',
      < -1 && >= -30 => 'Hace ${-dias} días',
      _ => corto(d),
    };
  }
}

final dinero = NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 2);

class Cliente {
  final String id;
  final String? cedula;
  final String nombre;
  final bool nombreSri;
  final String telefono;
  final String nota;
  final String ciudad;

  /// false = dio el número pero no trajo la cédula física: queda en Pendientes.
  final bool documento;
  final Estado estado;

  /// Cupo de crédito aprobado por la empresa.
  final double? monto;
  final DateTime? fechaConsulta;

  /// Cuándo puede venir (a usar el crédito o a traer la cédula).
  final DateTime? fechaVisita;
  final DateTime creadoEn;
  final DateTime actualizadoEn;

  const Cliente({
    required this.id,
    this.cedula,
    this.nombre = '',
    this.nombreSri = false,
    this.telefono = '',
    this.nota = '',
    this.ciudad = '',
    this.documento = true,
    required this.estado,
    this.monto,
    this.fechaConsulta,
    this.fechaVisita,
    required this.creadoEn,
    required this.actualizadoEn,
  });

  String get nombreVisible => nombre.trim().isNotEmpty
      ? nombre.trim()
      : cedula != null
      ? 'Cédula $cedula'
      : telefono.isNotEmpty
      ? 'Tel. $telefono'
      : 'Sin nombre';

  /// Le falta traer la cédula física (o, en registros viejos, el número).
  bool get pendiente => cedula == null || !documento;
  bool get porVenir => estado != Estado.atendido && estado != Estado.negado && fechaVisita != null;

  Map<String, Object?> aFila() => {
    'id': id,
    'cedula': cedula,
    'nombre': nombre,
    'nombre_sri': nombreSri ? 1 : 0,
    'telefono': telefono,
    'nota': nota,
    'ciudad': ciudad,
    'documento': documento ? 1 : 0,
    'estado': estado.clave,
    'monto': monto,
    'fecha_consulta': fechaConsulta == null ? null : Dia.texto(fechaConsulta!),
    'fecha_visita': fechaVisita == null ? null : Dia.texto(fechaVisita!),
    'creado_en': creadoEn.toIso8601String(),
    'actualizado_en': actualizadoEn.toIso8601String(),
  };

  factory Cliente.deFila(Map<String, Object?> f) => Cliente(
    id: f['id'] as String,
    cedula: f['cedula'] as String?,
    nombre: (f['nombre'] as String?) ?? '',
    nombreSri: f['nombre_sri'] == 1,
    telefono: (f['telefono'] as String?) ?? '',
    nota: (f['nota'] as String?) ?? '',
    ciudad: (f['ciudad'] as String?) ?? '',
    documento: f['documento'] != 0,
    estado: Estado.desde(f['estado'] as String),
    monto: (f['monto'] as num?)?.toDouble(),
    fechaConsulta: Dia.leer(f['fecha_consulta'] as String?),
    fechaVisita: Dia.leer(f['fecha_visita'] as String?),
    creadoEn: DateTime.parse(f['creado_en'] as String),
    actualizadoEn: DateTime.parse(f['actualizado_en'] as String),
  );

  Cliente copiar({
    String? cedula,
    String? nombre,
    bool? nombreSri,
    String? telefono,
    String? nota,
    String? ciudad,
    bool? documento,
    Estado? estado,
    double? Function()? monto,
    DateTime? Function()? fechaConsulta,
    DateTime? Function()? fechaVisita,
    DateTime? actualizadoEn,
  }) => Cliente(
    id: id,
    cedula: cedula ?? this.cedula,
    nombre: nombre ?? this.nombre,
    nombreSri: nombreSri ?? this.nombreSri,
    telefono: telefono ?? this.telefono,
    nota: nota ?? this.nota,
    ciudad: ciudad ?? this.ciudad,
    documento: documento ?? this.documento,
    estado: estado ?? this.estado,
    monto: monto != null ? monto() : this.monto,
    fechaConsulta: fechaConsulta != null ? fechaConsulta() : this.fechaConsulta,
    fechaVisita: fechaVisita != null ? fechaVisita() : this.fechaVisita,
    creadoEn: creadoEn,
    actualizadoEn: actualizadoEn ?? this.actualizadoEn,
  );

  /// Texto sin tildes y en minúsculas para buscar.
  String get textoBusqueda => normalizar('$nombre ${cedula ?? ''} $telefono $ciudad $nota');
}

String normalizar(String s) {
  const de = 'áéíóúüñàèìòù', a = 'aeiouunaeiou';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = de.indexOf(ch);
    b.write(i >= 0 ? a[i] : ch);
  }
  return b.toString();
}

class Evento {
  final int n;
  final String clienteId;
  final String tipo;
  final DateTime fecha;
  final Map<String, dynamic> detalle;
  final String hash;

  const Evento(this.n, this.clienteId, this.tipo, this.fecha, this.detalle, this.hash);

  String get descripcion {
    final d = detalle;
    String? m() => d['monto'] == null ? null : dinero.format(d['monto']);
    String? v() => d['fecha_visita'] == null ? null : 'puede venir ${Dia.corto(DateTime.parse(d['fecha_visita']))}';
    return switch (tipo) {
      'registro' => [
        'Registrado',
        if (d['cedula'] != null) 'con cédula ${d['cedula']}' else 'sin cédula',
        if (d['documento'] == false) 'falta el documento',
        ?v(),
      ].join(' · '),
      'consulta' => ['Consulta: ${Estado.desde(d['estado'] ?? '').etiqueta}', ?m(), ?v()].join(' · '),
      'cedula' => 'Se anotó la cédula ${d['cedula']}',
      'documento' => 'Trajo el documento (cédula física)',
      'atendido' => 'Vino a usar el crédito',
      'edicion' => 'Datos editados (${(d['campos'] as List?)?.join(', ') ?? ''})',
      'unido' => 'Se unió con otro registro de ${d['nombre'] ?? 'este cliente'}',
      'eliminado' => 'Eliminado',
      _ => tipo,
    };
  }
}
