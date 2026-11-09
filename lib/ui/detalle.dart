import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../datos/modelo.dart';
import '../nucleo/identificacion.dart';
import '../nucleo/sello.dart';
import '../servicios/base.dart';
import '../servicios/recordatorios.dart';
import '../servicios/respaldo.dart';
import '../servicios/sri.dart';
import 'arranque.dart';
import 'comun.dart';
import 'formulario.dart';
import 'pin.dart';

class PantallaDetalle extends StatefulWidget {
  final String clienteId;
  const PantallaDetalle({super.key, required this.clienteId});

  @override
  State<PantallaDetalle> createState() => _PantallaDetalleState();
}

class _PantallaDetalleState extends State<PantallaDetalle> {
  late String _id = widget.clienteId;
  Cliente? _c;
  List<Evento> _eventos = [];
  Evento? _primero;
  bool _borrado = false;

  @override
  void initState() {
    super.initState();
    Base.cambios.addListener(_cargar);
    _cargar();
  }

  @override
  void dispose() {
    Base.cambios.removeListener(_cargar);
    super.dispose();
  }

  Future<void> _cargar() async {
    final c = await Base.repo.porId(_id);
    final ev = c == null ? <Evento>[] : await Base.repo.eventos(_id);
    final primero = c == null ? null : await Base.repo.primerRegistro(_id);
    if (!mounted) return;
    setState(() {
      _c = c;
      _eventos = ev;
      _primero = primero;
      _borrado = c == null;
    });
  }

  Future<void> _cambio() async {
    await Respaldo.hayCambios();
    Base.avisar();
    Recordatorios.reprogramar();
  }

  Future<void> _agregarCedula() async {
    final c = _c!;
    final r = await showDialog<(String, String?)>(
      context: context,
      builder: (_) => _DialogoCedula(nombreActual: c.nombre),
    );
    if (r == null || !mounted) return;
    final (cedula, nombreSri) = r;
    final otro = await Base.repo.porCedula(cedula);
    if (!mounted) return;
    if (otro != null && otro.id != c.id) {
      final unir = await confirmar(
        context,
        'Esa cédula ya está registrada',
        'La cédula $cedula ya es de "${otro.nombreVisible}" (registrado el ${Dia.corto(otro.creadoEn)}).\n\n'
            '¿Es la misma persona? Se unen los dos registros en uno solo y se conserva toda la historia.',
        si: 'Unir',
      );
      if (!unir) return;
      final u = await Base.repo.unir(c.id, otro.id);
      _id = u.id;
    } else {
      await Base.repo.agregarCedula(
        c.id,
        cedula,
        nombre: c.nombre.trim().isEmpty ? nombreSri : null,
        nombreSri: nombreSri != null,
      );
    }
    await _cambio();
    if (!mounted) return;
    aviso(context, 'Cédula agregada. Ahora registra la consulta del crédito.');
    _nuevaConsulta();
  }

  void _nuevaConsulta() {
    final c = _c;
    if (c?.cedula == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PantallaNuevo(cedula: c!.cedula, abrirFicha: (ctx, _) => Navigator.pop(ctx)),
      ),
    );
  }

  Future<void> _vino() async {
    if (!await confirmar(context, 'Ya vino', '¿${_c!.nombreVisible} ya vino a usar su crédito?')) return;
    await Base.repo.marcarAtendido(_id);
    await _cambio();
  }

  Future<void> _editar() async {
    final nuevo = await Navigator.of(context).push<Cliente>(MaterialPageRoute(builder: (_) => _PantallaEditar(_c!)));
    if (nuevo == null) return;
    try {
      await Base.repo.editar(nuevo);
      await _cambio();
    } on StateError catch (e) {
      if (mounted) aviso(context, e.message, error: true);
    }
  }

  Future<void> _eliminar() async {
    if (!await confirmar(
      context,
      'Eliminar cliente',
      'Se borrará ${_c!.nombreVisible} de tu agenda. Queda constancia en el historial de sellos.',
      si: 'Eliminar',
      peligro: true,
    )) {
      return;
    }
    if (!mounted) return;
    Arranque.noBloquearAlVolver = true;
    if (!await pedirPin(context)) return;
    await Base.repo.eliminar(_id);
    await _cambio();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _whatsapp() async {
    final c = _c!;
    final opciones = mensajesWhatsapp(c);
    final elegido = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('Enviar por WhatsApp', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (final (t, m) in opciones)
              ListTile(
                leading: const Icon(Icons.chat_outlined),
                title: Text(t),
                subtitle: Text(m, maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.pop(ctx, m),
              ),
          ],
        ),
      ),
    );
    if (elegido == null) return;
    Arranque.noBloquearAlVolver = true;
    if (!await whatsapp(c.telefono, elegido) && mounted)
      aviso(context, 'El teléfono no parece un celular de Ecuador', error: true);
  }

  @override
  Widget build(BuildContext context) {
    if (_borrado) return Scaffold(appBar: AppBar(), body: const Vacio(Icons.person_off, 'Este cliente ya no está en la agenda.'));
    final c = _c;
    if (c == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final t = Theme.of(context).textTheme;
    final esq = Theme.of(context).colorScheme;
    final hora = DateFormat("d MMM yyyy, HH:mm", 'es');

    Widget dato(IconData i, String titulo, String valor, {VoidCallback? copiar}) => ListTile(
      leading: Icon(i),
      title: Text(titulo, style: TextStyle(color: esq.onSurfaceVariant, fontSize: 13)),
      subtitle: Text(valor, style: t.titleMedium),
      trailing: copiar == null ? null : IconButton(icon: const Icon(Icons.copy, size: 20), onPressed: copiar),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ficha del cliente'),
        actions: [
          IconButton(tooltip: 'Editar', icon: const Icon(Icons.edit_outlined), onPressed: _editar),
          PopupMenuButton<String>(
            onSelected: (v) => v == 'eliminar' ? _eliminar() : null,
            itemBuilder: (_) => const [PopupMenuItem(value: 'eliminar', child: Text('Eliminar'))],
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: colorEstado(c.estado).withValues(alpha: .15),
                    foregroundColor: colorEstado(c.estado),
                    child: Text(iniciales(c.nombre), style: const TextStyle(fontSize: 22)),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.nombreVisible, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                        if (c.nombreSri) Text('Nombre según el SRI', style: TextStyle(color: esq.onSurfaceVariant, fontSize: 12)),
                        const SizedBox(height: 6),
                        ChipEstado(c.estado),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (c.pendiente)
                    FilledButton.icon(
                      onPressed: _agregarCedula,
                      icon: const Icon(Icons.badge),
                      label: const Text('Ya trajo la cédula'),
                    ),
                  if (c.cedula != null)
                    FilledButton.tonalIcon(
                      onPressed: _nuevaConsulta,
                      icon: const Icon(Icons.manage_search),
                      label: const Text('Nueva consulta'),
                    ),
                  if (c.estado == Estado.aprobado)
                    FilledButton.tonalIcon(onPressed: _vino, icon: const Icon(Icons.how_to_reg), label: const Text('Ya vino')),
                  if (c.telefono.isNotEmpty) ...[
                    OutlinedButton.icon(
                      onPressed: () {
                        Arranque.noBloquearAlVolver = true;
                        llamar(c.telefono);
                      },
                      icon: const Icon(Icons.call),
                      label: const Text('Llamar'),
                    ),
                    OutlinedButton.icon(onPressed: _whatsapp, icon: const Icon(Icons.chat), label: const Text('WhatsApp')),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    if (c.cedula != null)
                      dato(
                        Icons.badge_outlined,
                        'Cédula',
                        Identificacion.formatear(c.cedula!),
                        copiar: () {
                          Clipboard.setData(ClipboardData(text: c.cedula!));
                          aviso(context, 'Cédula copiada');
                        },
                      )
                    else
                      dato(Icons.hourglass_top, 'Cédula', 'Todavía no la trae'),
                    if (c.estado == Estado.aprobado || c.estado == Estado.atendido)
                      dato(
                        Icons.payments_outlined,
                        'Cupo aprobado',
                        c.monto == null ? 'Sin monto anotado' : dinero.format(c.monto),
                      ),
                    if (c.fechaConsulta != null) dato(Icons.event_available, 'Fecha de consulta', Dia.corto(c.fechaConsulta!)),
                    if (c.fechaVisita != null)
                      dato(
                        Icons.event,
                        c.pendiente ? 'Trae la cédula' : 'Puede venir',
                        '${Dia.relativo(c.fechaVisita!)} (${Dia.corto(c.fechaVisita!)})',
                      ),
                    if (c.telefono.isNotEmpty) dato(Icons.phone_outlined, 'Teléfono', c.telefono),
                    if (c.nota.isNotEmpty) dato(Icons.notes, 'Nota', c.nota),
                  ],
                ),
              ),
              if (_primero != null)
                Card(
                  color: esq.surfaceContainerHighest,
                  child: ListTile(
                    leading: const Icon(Icons.verified_outlined),
                    title: Text('Registrado por primera vez el ${hora.format(_primero!.fecha)}'),
                    subtitle: Text('Sello ${Sello.corto(_primero!.hash)} · la fecha de registro no se puede cambiar'),
                  ),
                ),
              const SizedBox(height: 16),
              Text('Historial', style: t.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              for (final e in _eventos)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.circle, size: 10),
                  title: Text(e.descripcion),
                  subtitle: Text('${hora.format(e.fecha)} · sello ${Sello.corto(e.hash)}'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogoCedula extends StatefulWidget {
  final String nombreActual;
  const _DialogoCedula({required this.nombreActual});

  @override
  State<_DialogoCedula> createState() => _DialogoCedulaState();
}

class _DialogoCedulaState extends State<_DialogoCedula> {
  final _c = TextEditingController();
  String? _error;
  bool _buscando = false;

  Future<void> _aceptar() async {
    final ced = _c.text.trim();
    final e = Identificacion.errorCedula(ced);
    if (e != null) return setState(() => _error = e);
    String? nombre;
    if (widget.nombreActual.trim().isEmpty) {
      setState(() => _buscando = true);
      nombre = await Sri.nombre(ced);
    }
    if (mounted) Navigator.pop(context, (ced, nombre));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Cédula del cliente'),
    content: TextField(
      controller: _c,
      autofocus: true,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
      style: const TextStyle(fontSize: 24, letterSpacing: 2),
      decoration: InputDecoration(labelText: 'Cédula', errorText: _error),
      onSubmitted: (_) => _aceptar(),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
      FilledButton(
        onPressed: _buscando ? null : _aceptar,
        child: _buscando
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Text('Guardar'),
      ),
    ],
  );
}

class _PantallaEditar extends StatefulWidget {
  final Cliente c;
  const _PantallaEditar(this.c);

  @override
  State<_PantallaEditar> createState() => _PantallaEditarState();
}

class _PantallaEditarState extends State<_PantallaEditar> {
  late final _nombre = TextEditingController(text: widget.c.nombre);
  late final _telefono = TextEditingController(text: widget.c.telefono);
  late final _nota = TextEditingController(text: widget.c.nota);
  late final _cedula = TextEditingController(text: widget.c.cedula ?? '');
  late final _monto = TextEditingController(text: widget.c.monto?.toStringAsFixed(2) ?? '');
  late Estado _estado = widget.c.estado;
  late DateTime? _visita = widget.c.fechaVisita;
  String? _errorCedula;

  void _guardar() {
    final ced = _cedula.text.trim();
    if (ced.isNotEmpty) {
      final e = Identificacion.errorCedula(ced);
      if (e != null) return setState(() => _errorCedula = e);
    }
    final m = double.tryParse(_monto.text.trim().replaceAll(',', '.'));
    Navigator.pop(
      context,
      Cliente(
        id: widget.c.id,
        cedula: ced.isEmpty ? null : ced,
        nombre: _nombre.text,
        telefono: _telefono.text,
        nota: _nota.text,
        estado: _estado,
        monto: _estado == Estado.negado ? null : m,
        fechaConsulta: widget.c.fechaConsulta,
        fechaVisita: _visita,
        creadoEn: widget.c.creadoEn,
        actualizadoEn: DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const e = SizedBox(height: 16);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar cliente'),
        actions: [TextButton(onPressed: _guardar, child: const Text('Guardar'))],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              TextField(
                controller: _nombre,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              e,
              TextField(
                controller: _cedula,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
                decoration: InputDecoration(
                  labelText: 'Cédula',
                  errorText: _errorCedula,
                  helperText: 'Vacía = pendiente de cédula',
                ),
              ),
              e,
              TextField(
                controller: _telefono,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Teléfono'),
              ),
              e,
              if (_cedula.text.trim().isNotEmpty && widget.c.cedula != null) ...[
                DropdownButtonFormField<Estado>(
                  initialValue: _estado == Estado.pendienteCedula ? Estado.aprobado : _estado,
                  decoration: const InputDecoration(labelText: 'Estado'),
                  items: [
                    for (final s in Estado.values.where((s) => s != Estado.pendienteCedula))
                      DropdownMenuItem(value: s, child: Text(s.etiqueta)),
                  ],
                  onChanged: (s) => setState(() => _estado = s!),
                ),
                e,
                if (_estado != Estado.negado) ...[
                  TextField(
                    controller: _monto,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Cupo aprobado', prefixText: '\$ '),
                  ),
                  e,
                ],
              ],
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: const Text('Puede venir'),
                subtitle: Text(_visita == null ? 'Sin fecha' : Dia.corto(_visita!)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_visita != null)
                      IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _visita = null)),
                    const Icon(Icons.edit_calendar),
                  ],
                ),
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _visita ?? Dia.hoy(),
                    firstDate: DateTime(2020),
                    lastDate: Dia.hoy().add(const Duration(days: 365)),
                  );
                  if (d != null) setState(() => _visita = d);
                },
              ),
              e,
              TextField(
                controller: _nota,
                minLines: 2,
                maxLines: 6,
                decoration: const InputDecoration(labelText: 'Nota'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
