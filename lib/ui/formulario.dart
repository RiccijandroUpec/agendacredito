import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../datos/modelo.dart';
import '../datos/repositorio.dart';
import '../nucleo/identificacion.dart';
import '../servicios/base.dart';
import '../servicios/recordatorios.dart';
import '../servicios/respaldo.dart';
import '../servicios/sri.dart';
import 'comun.dart';

/// Registro de un cliente o de una nueva consulta.
///
/// En modo [rapido] (la ventana de la burbuja, que se abre sin PIN) no se
/// muestran datos de clientes ya guardados: solo se avisa que la cédula ya
/// existe y la consulta se suma a su historia.
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
  final _focoCedula = FocusNode();

  bool _trajo = true;
  Estado _resultado = Estado.aprobado;
  DateTime _fechaConsulta = Dia.hoy();
  DateTime? _fechaVisita;
  Cliente? _existente;
  String? _cedulaRevisada;
  bool _buscandoSri = false;
  String? _infoSri;
  bool _nombreSri = false;
  bool _guardando = false;
  String? _errorCedula, _errorNombre, _errorMonto;

  @override
  void initState() {
    super.initState();
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

  Future<void> _revisarCedula() async {
    final c = _cedula.text.trim();
    if (c == _cedulaRevisada) return;
    _cedulaRevisada = c;
    setState(() {
      _errorCedula = null;
      _existente = null;
      _infoSri = null;
    });
    if (c.length < 10) return;
    final error = Identificacion.errorCedula(c);
    if (error != null) return setState(() => _errorCedula = error);
    final existe = await Base.repo.porCedula(c);
    if (!mounted || _cedula.text.trim() != c) return;
    setState(() => _existente = existe);
    if (existe != null && existe.nombre.trim().isNotEmpty) return;
    if (_nombre.text.trim().isNotEmpty) return;
    setState(() => _buscandoSri = true);
    final nombre = await Sri.nombre(c);
    if (!mounted || _cedula.text.trim() != c) return;
    setState(() {
      _buscandoSri = false;
      if (nombre != null && _nombre.text.trim().isEmpty) {
        _nombre.text = nombre;
        _nombreSri = true;
        _infoSri = 'Nombre traído del SRI';
      } else if (nombre == null) {
        _infoSri = 'No aparece en el SRI (no tiene RUC o no hay internet): escribe el nombre';
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
    setState(() => _errorCedula = _errorNombre = _errorMonto = null);
    double? monto;
    if (_trajo) {
      final e = Identificacion.errorCedula(cedula);
      if (e != null) {
        setState(() => _errorCedula = e);
        _focoCedula.requestFocus();
        return;
      }
      if (_resultado == Estado.aprobado) {
        monto = _leerMonto();
        if (_monto.text.trim().isNotEmpty && (monto == null || monto < 0)) {
          return setState(() => _errorMonto = 'Monto no válido');
        }
      }
    } else if (nombre.isEmpty && telefono.isEmpty) {
      return setState(() => _errorNombre = 'Escribe al menos el nombre o el teléfono');
    }

    setState(() => _guardando = true);
    try {
      final repo = Base.repo;
      final ahora = DateTime.now();
      Cliente guardado;
      final existe = _trajo ? await repo.porCedula(cedula) : null;
      if (existe != null) {
        guardado = await repo.registrarConsulta(
          existe.id,
          estado: _resultado,
          monto: monto,
          fechaConsulta: _fechaConsulta,
          fechaVisita: _fechaVisita,
          nombre: nombre,
          nombreSri: _nombreSri,
          telefono: telefono,
          notaExtra: _nota.text,
        );
      } else {
        guardado = await repo.registrar(
          Cliente(
            id: Repositorio.nuevoId(),
            cedula: _trajo ? cedula : null,
            nombre: nombre,
            nombreSri: _trajo && _nombreSri && nombre.isNotEmpty,
            telefono: telefono,
            nota: _nota.text.trim(),
            estado: _trajo ? _resultado : Estado.pendienteCedula,
            monto: _trajo && _resultado == Estado.aprobado ? monto : null,
            fechaConsulta: _trajo ? _fechaConsulta : null,
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

  @override
  Widget build(BuildContext context) {
    final esq = Theme.of(context).colorScheme;
    const espacio = SizedBox(height: 16);
    final existe = _existente;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, icon: Icon(Icons.badge_outlined), label: Text('Trajo la cédula')),
            ButtonSegment(value: false, icon: Icon(Icons.hourglass_top), label: Text('La va a traer')),
          ],
          selected: {_trajo},
          onSelectionChanged: (s) => setState(() => _trajo = s.first),
        ),
        espacio,
        if (_trajo) ...[
          TextField(
            controller: _cedula,
            focusNode: _focoCedula,
            autofocus: widget.rapido && widget.cedulaInicial == null,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
            style: const TextStyle(fontSize: 24, letterSpacing: 2, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              labelText: 'Cédula',
              prefixIcon: const Icon(Icons.badge_outlined),
              errorText: _errorCedula,
              helperText: _cedula.text.length == 10 && _errorCedula == null ? 'Cédula válida ✓' : null,
              helperStyle: const TextStyle(color: Color(0xFF1B8A3C), fontWeight: FontWeight.w600),
              suffixIcon: _buscandoSri
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : null,
            ),
          ),
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
          espacio,
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_available),
            title: const Text('Fecha de la consulta'),
            subtitle: Text(
              Dia.relativo(_fechaConsulta) == 'Hoy' ? 'Hoy, ${Dia.corto(_fechaConsulta)}' : Dia.corto(_fechaConsulta),
            ),
            trailing: const Icon(Icons.edit_calendar),
            onTap: () => _elegirFecha(false),
          ),
        ],
        Text(_trajo ? '¿Cuándo puede venir?' : '¿Cuándo trae la cédula?', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        _chipsVisita(),
        espacio,
        TextField(
          controller: _nombre,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => _nombreSri = false,
          decoration: InputDecoration(
            labelText: _trajo ? 'Nombre' : 'Nombre del cliente',
            prefixIcon: const Icon(Icons.person_outline),
            errorText: _errorNombre,
            helperText: _infoSri,
            helperMaxLines: 2,
          ),
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
            hintText: _trajo ? 'Ej.: quiere una refrigeradora' : 'Ej.: viene el viernes con la cédula',
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
