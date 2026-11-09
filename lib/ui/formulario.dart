import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../datos/modelo.dart';
import '../datos/repositorio.dart';
import '../nucleo/ecuador.dart';
import '../nucleo/identificacion.dart';
import '../servicios/base.dart';
import '../servicios/recordatorios.dart';
import '../servicios/respaldo.dart';
import '../servicios/sri.dart';
import 'comun.dart';

enum _EstadoSri { nada, buscando, encontrado, sinDatos }

/// Registro de un cliente o de una nueva consulta.
///
/// La cédula (el número) siempre es obligatoria. "Trajo el documento" dice si
/// trajo la cédula física: si no, el cliente queda en Pendientes.
///
/// En modo [rapido] (la ventana de la burbuja) no se muestran datos de
/// clientes ya guardados: solo se avisa que la cédula ya existe y la consulta
/// se suma a su historia.
class FormularioCliente extends StatefulWidget {
  final bool rapido;
  final String? cedulaInicial;
  final ValueChanged<Cliente>? alGuardar;
  final VoidCallback? alCancelar;
  final void Function(Cliente)? verExistente;

  const FormularioCliente({
    super.key,
    this.rapido = false,
    this.cedulaInicial,
    this.alGuardar,
    this.alCancelar,
    this.verExistente,
  });

  @override
  State<FormularioCliente> createState() => _FormularioClienteState();
}

class _FormularioClienteState extends State<FormularioCliente> {
  final _cedula = TextEditingController();
  final _nombre = TextEditingController();
  final _telefono = TextEditingController();
  final _monto = TextEditingController();
  final _nota = TextEditingController();
  TextEditingController? _ciudad;
  String _ciudadInicial = '';
  final _focoCedula = FocusNode();

  bool _documento = true;
  Estado _resultado = Estado.aprobado;
  DateTime _fechaConsulta = Dia.hoy();
  DateTime? _fechaVisita;
  Cliente? _existente;
  String? _cedulaRevisada;
  _EstadoSri _sri = _EstadoSri.nada;
  DatosSri? _datosSri;
  bool _nombreSri = false;
  bool _guardando = false;
  String? _errorCedula, _errorMonto;
  List<String> _ciudades = ciudadesEcuador;

  @override
  void initState() {
    super.initState();
    Base.abrir().then((r) => r.ciudades()).then((usadas) {
      if (!mounted) return;
      final vistas = {for (final c in usadas) normalizar(c)};
      setState(() => _ciudades = [...usadas, ...ciudadesEcuador.where((c) => !vistas.contains(normalizar(c)))]);
    });
    if (widget.cedulaInicial != null) {
      _cedula.text = widget.cedulaInicial!;
      _revisarCedula();
    }
    _cedula.addListener(_revisarCedula);
  }

  @override
  void dispose() {
    for (final c in [_cedula, _nombre, _telefono, _monto, _nota]) {
      c.dispose();
    }
    _focoCedula.dispose();
    super.dispose();
  }

  String get _textoCiudad => (_ciudad?.text ?? _ciudadInicial).trim();

  void _ponerCiudad(String c) {
    if (_ciudad != null) {
      _ciudad!.text = c;
    } else {
      _ciudadInicial = c;
    }
  }

  Future<void> _revisarCedula() async {
    final c = _cedula.text.trim();
    if (c == _cedulaRevisada) return;
    _cedulaRevisada = c;
    setState(() {
      _errorCedula = null;
      _existente = null;
      _sri = _EstadoSri.nada;
      _datosSri = null;
    });
    if (c.length < 10) return;
    final error = Identificacion.errorCedula(c);
    if (error != null) return setState(() => _errorCedula = error);
    final existe = await Base.repo.porCedula(c);
    if (!mounted || _cedula.text.trim() != c) return;
    setState(() => _existente = existe);
    if (existe != null && !widget.rapido) {
      if (_telefono.text.isEmpty) _telefono.text = existe.telefono;
      if (_textoCiudad.isEmpty) _ponerCiudad(existe.ciudad);
    }
    if (existe != null && existe.nombre.trim().isNotEmpty) return;
    await _buscarSri(c);
  }

  Future<void> _buscarSri(String c) async {
    setState(() => _sri = _EstadoSri.buscando);
    final d = await Sri.consultar(c);
    if (!mounted || _cedula.text.trim() != c) return;
    setState(() {
      _datosSri = d;
      _sri = d == null ? _EstadoSri.sinDatos : _EstadoSri.encontrado;
      if (d != null) {
        if (_nombre.text.trim().isEmpty) {
          _nombre.text = d.nombre;
          _nombreSri = true;
        }
        if (_textoCiudad.isEmpty && d.ciudad != null) _ponerCiudad(d.ciudad!);
      }
    });
  }

  double? _leerMonto() {
    final t = _monto.text.trim().replaceAll('\$', '').replaceAll(' ', '');
    if (t.isEmpty) return null;
    // Acepta 1.250,50 · 1,250.50 · 1250,5 · 1250.5
    var n = t;
    if (n.contains(',') && n.contains('.')) {
      n = n.lastIndexOf(',') > n.lastIndexOf('.') ? n.replaceAll('.', '').replaceAll(',', '.') : n.replaceAll(',', '');
    } else {
      n = n.replaceAll(',', '.');
    }
    return double.tryParse(n);
  }

  Future<void> _guardar() async {
    final cedula = _cedula.text.trim();
    final nombre = _nombre.text.trim();
    final telefono = _telefono.text.trim();
    final ciudad = _textoCiudad;
    setState(() => _errorCedula = _errorMonto = null);
    final e = Identificacion.errorCedula(cedula);
    if (e != null) {
      setState(() => _errorCedula = e);
      _focoCedula.requestFocus();
      return;
    }
    double? monto;
    if (_resultado == Estado.aprobado) {
      monto = _leerMonto();
      if (_monto.text.trim().isNotEmpty && (monto == null || monto < 0)) {
        return setState(() => _errorMonto = 'Monto no válido');
      }
    }
    final consultado = _resultado != Estado.porConsultar;

    setState(() => _guardando = true);
    try {
      final repo = Base.repo;
      final ahora = DateTime.now();
      Cliente guardado;
      final existe = await repo.porCedula(cedula);
      if (existe != null) {
        guardado = await repo.registrarConsulta(
          existe.id,
          estado: _resultado,
          monto: monto,
          fechaConsulta: consultado ? _fechaConsulta : (existe.fechaConsulta ?? _fechaConsulta),
          fechaVisita: _fechaVisita,
          nombre: nombre,
          nombreSri: _nombreSri,
          telefono: telefono,
          notaExtra: _nota.text,
          ciudad: ciudad,
          documento: _documento || existe.documento,
        );
      } else {
        guardado = await repo.registrar(
          Cliente(
            id: Repositorio.nuevoId(),
            cedula: cedula,
            nombre: nombre,
            nombreSri: _nombreSri && nombre.isNotEmpty,
            telefono: telefono,
            nota: _nota.text.trim(),
            ciudad: ciudad,
            documento: _documento,
            estado: _resultado,
            monto: _resultado == Estado.aprobado ? monto : null,
            fechaConsulta: consultado ? _fechaConsulta : null,
            fechaVisita: _fechaVisita,
            creadoEn: ahora,
            actualizadoEn: ahora,
          ),
        );
      }
      await Respaldo.hayCambios();
      Base.avisar();
      Recordatorios.reprogramar();
      HapticFeedback.mediumImpact();
      widget.alGuardar?.call(guardado);
    } catch (e) {
      if (mounted) aviso(context, 'No se pudo guardar: $e', error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _elegirFecha(bool visita) async {
    final hoy = Dia.hoy();
    final d = await showDatePicker(
      context: context,
      initialDate: visita ? (_fechaVisita ?? hoy) : _fechaConsulta,
      firstDate: visita ? hoy.subtract(const Duration(days: 30)) : DateTime(2020),
      lastDate: visita ? hoy.add(const Duration(days: 365)) : hoy,
      locale: const Locale('es'),
    );
    if (d == null) return;
    setState(() => visita ? _fechaVisita = d : _fechaConsulta = d);
  }

  Widget _chipsVisita() {
    final hoy = Dia.hoy();
    final opciones = <(String, DateTime?)>[
      ('Sin fecha', null),
      ('Hoy', hoy),
      ('Mañana', hoy.add(const Duration(days: 1))),
      ('Pasado mañana', hoy.add(const Duration(days: 2))),
      ('En 1 semana', hoy.add(const Duration(days: 7))),
    ];
    final elegidaEsOpcion = opciones.any((o) => o.$2 == _fechaVisita);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (t, d) in opciones)
          ChoiceChip(label: Text(t), selected: _fechaVisita == d, onSelected: (_) => setState(() => _fechaVisita = d)),
        ChoiceChip(
          avatar: const Icon(Icons.calendar_month, size: 18),
          label: Text(!elegidaEsOpcion && _fechaVisita != null ? Dia.corto(_fechaVisita!) : 'Elegir fecha'),
          selected: !elegidaEsOpcion && _fechaVisita != null,
          onSelected: (_) => _elegirFecha(true),
        ),
      ],
    );
  }

  Widget _avisoSri(ColorScheme esq) {
    final cedula = _cedula.text.trim();
    switch (_sri) {
      case _EstadoSri.nada:
        return const SizedBox.shrink();
      case _EstadoSri.buscando:
        return const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Row(
            children: [
              SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 10),
              Expanded(child: Text('Buscando datos en el SRI… (puede tardar hasta 15 segundos)')),
            ],
          ),
        );
      case _EstadoSri.encontrado:
        final d = _datosSri!;
        return Card(
          margin: const EdgeInsets.only(top: 8),
          color: const Color(0xFFE6F4EA),
          child: ListTile(
            leading: const Icon(Icons.verified, color: Color(0xFF1B8A3C)),
            title: Text(d.nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              [
                'Datos del SRI',
                if (d.ciudad != null) '${d.ciudad}${d.provincia != null ? ', ${d.provincia}' : ''}',
                if (d.actividad != null && d.actividad!.isNotEmpty) d.actividad!,
              ].join(' · '),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      case _EstadoSri.sinDatos:
        return Card(
          margin: const EdgeInsets.only(top: 8),
          color: esq.surfaceContainerHighest,
          child: ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('El SRI no tiene datos de esta cédula'),
            subtitle: const Text('El SRI solo tiene a las personas con RUC (o no hay internet). Escribe el nombre a mano.'),
            trailing: TextButton(onPressed: () => _buscarSri(cedula), child: const Text('Reintentar')),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final esq = Theme.of(context).colorScheme;
    const espacio = SizedBox(height: 16);
    final existe = _existente;
    final cedula = _cedula.text.trim();
    final provincia = cedula.length == 10 && _errorCedula == null ? provinciaDeCedula(cedula) : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _cedula,
          focusNode: _focoCedula,
          autofocus: widget.rapido && widget.cedulaInicial == null,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
          style: const TextStyle(fontSize: 24, letterSpacing: 2, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            labelText: 'Número de cédula *',
            prefixIcon: const Icon(Icons.badge_outlined),
            errorText: _errorCedula,
            helperText: provincia == null ? null : 'Cédula válida ✓ · emitida en $provincia',
            helperStyle: const TextStyle(color: Color(0xFF1B8A3C), fontWeight: FontWeight.w600),
          ),
        ),
        _avisoSri(esq),
        if (existe != null) ...[
          const SizedBox(height: 8),
          Card(
            color: esq.secondaryContainer,
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(
                widget.rapido
                    ? 'Ya está en tu agenda desde el ${Dia.corto(existe.creadoEn)}'
                    : '${existe.nombreVisible} ya está en tu agenda (desde el ${Dia.corto(existe.creadoEn)})',
              ),
              subtitle: const Text('Se guardará como una nueva consulta en su historia.'),
              trailing: widget.rapido || widget.verExistente == null
                  ? null
                  : TextButton(onPressed: () => widget.verExistente!(existe), child: const Text('Ver ficha')),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Card(
          color: _documento ? null : const Color(0xFFFFF3E0),
          child: SwitchListTile(
            secondary: Icon(
              _documento ? Icons.check_box : Icons.hourglass_top,
              color: _documento ? const Color(0xFF1B8A3C) : const Color(0xFFE08A00),
            ),
            title: const Text('Trajo el documento (cédula física)', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(_documento ? 'Sí lo trajo' : 'No lo trajo: quedará en Pendientes hasta que lo traiga'),
            value: _documento,
            onChanged: (v) => setState(() => _documento = v),
          ),
        ),
        espacio,
        Text('Resultado de la consulta', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<Estado>(
          segments: [
            ButtonSegment(
              value: Estado.aprobado,
              icon: Icon(Icons.check_circle, color: colorEstado(Estado.aprobado)),
              label: const Text('Aprobado'),
            ),
            ButtonSegment(
              value: Estado.negado,
              icon: Icon(Icons.cancel, color: colorEstado(Estado.negado)),
              label: const Text('Negado'),
            ),
            ButtonSegment(
              value: Estado.porConsultar,
              icon: Icon(Icons.schedule, color: colorEstado(Estado.porConsultar)),
              label: const Text('Por consultar'),
            ),
          ],
          selected: {_resultado},
          onSelectionChanged: (s) => setState(() => _resultado = s.first),
        ),
        if (_resultado == Estado.aprobado) ...[
          espacio,
          TextField(
            controller: _monto,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              labelText: 'Cupo de crédito aprobado',
              prefixText: '\$ ',
              prefixIcon: const Icon(Icons.payments_outlined),
              errorText: _errorMonto,
            ),
          ),
        ],
        if (_resultado != Estado.porConsultar)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_available),
            title: const Text('Fecha de la consulta'),
            subtitle: Text(
              Dia.relativo(_fechaConsulta) == 'Hoy' ? 'Hoy, ${Dia.corto(_fechaConsulta)}' : Dia.corto(_fechaConsulta),
            ),
            trailing: const Icon(Icons.edit_calendar),
            onTap: () => _elegirFecha(false),
          )
        else
          espacio,
        Text(_documento ? '¿Cuándo puede venir?' : '¿Cuándo trae el documento?', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        _chipsVisita(),
        espacio,
        TextField(
          controller: _nombre,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => _nombreSri = false,
          decoration: const InputDecoration(labelText: 'Nombre', prefixIcon: Icon(Icons.person_outline)),
        ),
        espacio,
        Autocomplete<String>(
          initialValue: TextEditingValue(text: _ciudadInicial),
          optionsBuilder: (v) {
            final q = normalizar(v.text.trim());
            if (q.isEmpty) return const [];
            return _ciudades.where((c) => normalizar(c).startsWith(q)).take(8);
          },
          fieldViewBuilder: (context, controlador, foco, alEnviar) {
            if (_ciudad != controlador) {
              _ciudad = controlador;
              if (controlador.text.isEmpty && _ciudadInicial.isNotEmpty) controlador.text = _ciudadInicial;
            }
            return TextField(
              controller: controlador,
              focusNode: foco,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Ciudad donde vive', prefixIcon: Icon(Icons.location_city_outlined)),
              onSubmitted: (_) => alEnviar(),
            );
          },
        ),
        espacio,
        TextField(
          controller: _telefono,
          keyboardType: TextInputType.phone,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d +]')), LengthLimitingTextInputFormatter(15)],
          decoration: const InputDecoration(labelText: 'Teléfono (opcional)', prefixIcon: Icon(Icons.phone_outlined)),
        ),
        espacio,
        TextField(
          controller: _nota,
          minLines: 1,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: 'Nota (opcional)',
            hintText: _documento ? 'Ej.: quiere una refrigeradora' : 'Ej.: viene el viernes con la cédula',
            prefixIcon: const Icon(Icons.notes),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            if (widget.alCancelar != null) ...[
              Expanded(
                child: OutlinedButton(onPressed: _guardando ? null : widget.alCancelar, child: const Text('Cancelar')),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: _guardando ? null : _guardar,
                icon: _guardando
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save),
                label: Text(existe != null ? 'Guardar consulta' : 'Guardar'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Pantalla completa con el formulario (desde la app).
class PantallaNuevo extends StatelessWidget {
  final String? cedula;
  final void Function(BuildContext, Cliente) abrirFicha;
  const PantallaNuevo({super.key, this.cedula, required this.abrirFicha});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(cedula == null ? 'Nuevo cliente' : 'Nueva consulta')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: FormularioCliente(
            cedulaInicial: cedula,
            alCancelar: () => Navigator.pop(context),
            verExistente: (c) => abrirFicha(context, c),
            alGuardar: (c) {
              final m = ScaffoldMessenger.of(context);
              Navigator.pop(context);
              m.showSnackBar(SnackBar(content: Text('Guardado: ${c.nombreVisible}'), behavior: SnackBarBehavior.floating));
            },
          ),
        ),
      ),
    ),
  );
}
