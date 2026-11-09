import 'package:flutter/material.dart';

import '../datos/modelo.dart';
import '../servicios/base.dart';
import '../servicios/respaldo.dart';
import '../servicios/seguridad.dart';
import 'ajustes.dart';
import 'comun.dart';
import 'detalle.dart';
import 'formulario.dart';

void abrirFicha(BuildContext context, Cliente c) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PantallaDetalle(clienteId: c.id)));

void abrirNuevo(BuildContext context, {String? cedula}) => Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => PantallaNuevo(
      cedula: cedula,
      abrirFicha: (ctx, c) {
        Navigator.pop(ctx);
        abrirFicha(context, c);
      },
    ),
  ),
);

class Inicio extends StatefulWidget {
  final VoidCallback alBloquear;
  const Inicio({super.key, required this.alBloquear});

  @override
  State<Inicio> createState() => _InicioState();
}

class _InicioState extends State<Inicio> {
  int _pestana = 0;
  List<Cliente> _clientes = [];
  bool _cargado = false;
  String? _avisoRespaldo;
  bool _conPin = false;

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
    final l = await Base.repo.todos();
    String? avisoR;
    if (l.isNotEmpty) {
      if (!await Respaldo.tieneClave()) {
        avisoR = 'Configura el respaldo para no perder tus clientes si la tablet se daña.';
      } else {
        final e = await Respaldo.ultimoEnviado();
        if (e == null || DateTime.now().difference(e).inDays >= 7) {
          avisoR = e == null
              ? 'Todavía no envías un respaldo fuera de la tablet (Drive, correo o WhatsApp).'
              : 'Hace ${DateTime.now().difference(e).inDays} días que no envías un respaldo fuera de la tablet.';
        }
      }
    }
    final conPin = await Seguridad.tienePin();
    if (!mounted) return;
    setState(() {
      _conPin = conPin;
      _clientes = l;
      _cargado = true;
      _avisoRespaldo = avisoR;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pendientes = _clientes.where((c) => c.pendiente).length;
    final hoy = _clientes.where((c) => c.porVenir && !c.fechaVisita!.isAfter(Dia.hoy())).length;
    final destinos = [
      (Icons.today_outlined, Icons.today, 'Hoy', hoy),
      (Icons.hourglass_empty, Icons.hourglass_top, 'Pendientes', pendientes),
      (Icons.people_outline, Icons.people, 'Clientes', 0),
      (Icons.bar_chart_outlined, Icons.bar_chart, 'Resumen', 0),
    ];
    Widget insignia(IconData i, int n) => n == 0 ? Icon(i) : Badge(label: Text('$n'), child: Icon(i));

    final cuerpo = !_cargado
        ? const Center(child: CircularProgressIndicator())
        : switch (_pestana) {
            0 => _PestanaHoy(_clientes),
            1 => _PestanaPendientes(_clientes),
            2 => _PestanaClientes(_clientes),
            _ => _PestanaResumen(_clientes),
          };

    final ancho = MediaQuery.sizeOf(context).width >= 720;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agenda de Crédito'),
        actions: [
          if (_conPin) IconButton(tooltip: 'Bloquear', icon: const Icon(Icons.lock_outline), onPressed: widget.alBloquear),
          IconButton(
            tooltip: 'Ajustes',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PantallaAjustes())).then((_) => _cargar()),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => abrirNuevo(context),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Nuevo cliente'),
      ),
      bottomNavigationBar: ancho
          ? null
          : NavigationBar(
              selectedIndex: _pestana,
              onDestinationSelected: (i) => setState(() => _pestana = i),
              destinations: [
                for (final (i, s, t, n) in destinos)
                  NavigationDestination(icon: insignia(i, n), selectedIcon: insignia(s, n), label: t),
              ],
            ),
      body: Row(
        children: [
          if (ancho)
            NavigationRail(
              selectedIndex: _pestana,
              onDestinationSelected: (i) => setState(() => _pestana = i),
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final (i, s, t, n) in destinos)
                  NavigationRailDestination(icon: insignia(i, n), selectedIcon: insignia(s, n), label: Text(t)),
              ],
            ),
          Expanded(
            child: Column(
              children: [
                if (_avisoRespaldo != null)
                  MaterialBanner(
                    leading: const Icon(Icons.cloud_upload_outlined, color: Color(0xFFE08A00)),
                    content: Text(_avisoRespaldo!),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(
                          context,
                        ).push(MaterialPageRoute(builder: (_) => const PantallaAjustes())).then((_) => _cargar()),
                        child: const Text('Respaldar'),
                      ),
                    ],
                  ),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900), child: cuerpo),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _titulo(BuildContext context, String t, {Color? color}) => Padding(
  padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
  child: Text(
    t,
    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: color),
  ),
);

class _PestanaHoy extends StatelessWidget {
  final List<Cliente> clientes;
  const _PestanaHoy(this.clientes);

  @override
  Widget build(BuildContext context) {
    final hoy = Dia.hoy();
    final porVenir = clientes.where((c) => c.porVenir).toList()..sort((a, b) => a.fechaVisita!.compareTo(b.fechaVisita!));
    final atrasados = porVenir.where((c) => c.fechaVisita!.isBefore(hoy)).toList();
    final deHoy = porVenir.where((c) => c.fechaVisita == hoy).toList();
    final proximos = porVenir.where((c) => c.fechaVisita!.isAfter(hoy) && c.fechaVisita!.difference(hoy).inDays <= 7).toList();
    final consultadosHoy = clientes.where((c) => c.fechaConsulta == hoy).length;
    if (porVenir.isEmpty && atrasados.isEmpty) {
      return Vacio(
        Icons.event_available,
        clientes.isEmpty ? 'Toca "Nuevo cliente" para registrar el primero.' : 'No hay visitas para hoy ni los próximos días.',
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Text(
            '${DateFormatoLargo.hoy()} · consultaste $consultadosHoy hoy',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        if (deHoy.isNotEmpty) ...[
          _titulo(context, 'Hoy pueden venir (${deHoy.length})'),
          for (final c in deHoy) FilaCliente(c, onTap: () => abrirFicha(context, c)),
        ],
        if (atrasados.isNotEmpty) ...[
          _titulo(context, 'Quedaron en venir y no vinieron (${atrasados.length})', color: Colors.red.shade700),
          for (final c in atrasados) FilaCliente(c, onTap: () => abrirFicha(context, c)),
        ],
        if (proximos.isNotEmpty) ...[
          _titulo(context, 'Próximos 7 días (${proximos.length})'),
          for (final c in proximos) FilaCliente(c, onTap: () => abrirFicha(context, c)),
        ],
      ],
    );
  }
}

class DateFormatoLargo {
  static String hoy() {
    final s = Dia.corto(DateTime.now());
    const dias = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
    final d = dias[DateTime.now().weekday - 1];
    return '${d[0].toUpperCase()}${d.substring(1)} $s';
  }
}

class _PestanaPendientes extends StatelessWidget {
  final List<Cliente> clientes;
  const _PestanaPendientes(this.clientes);

  @override
  Widget build(BuildContext context) {
    final l = clientes.where((c) => c.pendiente).toList()..sort((a, b) => a.creadoEn.compareTo(b.creadoEn));
    if (l.isEmpty) return const Vacio(Icons.task_alt, 'No tienes clientes que deban traer el documento.');
    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        _titulo(context, 'Les falta traer el documento (${l.length})'),
        for (final c in l)
          FilaCliente(
            c,
            onTap: () => abrirFicha(context, c),
            extra: Text(
              _espera(c.creadoEn),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
            ),
          ),
      ],
    );
  }

  static String _espera(DateTime desde) {
    final d = Dia.hoy().difference(DateTime(desde.year, desde.month, desde.day)).inDays;
    return d == 0
        ? 'Anotado hoy'
        : d == 1
        ? 'Esperando desde ayer'
        : 'Esperando hace $d días';
  }
}

class _PestanaClientes extends StatefulWidget {
  final List<Cliente> clientes;
  const _PestanaClientes(this.clientes);

  @override
  State<_PestanaClientes> createState() => _PestanaClientesState();
}

class _PestanaClientesState extends State<_PestanaClientes> {
  final _busqueda = TextEditingController();
  Estado? _filtro;
  bool _soloSinDocumento = false;

  @override
  Widget build(BuildContext context) {
    final q = normalizar(_busqueda.text.trim());
    final palabras = q.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    final l = widget.clientes
        .where((c) => _filtro == null || c.estado == _filtro)
        .where((c) => !_soloSinDocumento || c.pendiente)
        .where((c) => palabras.every(c.textoBusqueda.contains))
        .toList();
    final solo10 = RegExp(r'^\d{10}$').hasMatch(_busqueda.text.trim());
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _busqueda,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Buscar por cédula, nombre o teléfono',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _busqueda.text.isEmpty
                  ? null
                  : IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(_busqueda.clear)),
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              FilterChip(
                label: Text('Todos (${widget.clientes.length})'),
                selected: _filtro == null && !_soloSinDocumento,
                onSelected: (_) => setState(() {
                  _filtro = null;
                  _soloSinDocumento = false;
                }),
              ),
              const SizedBox(width: 8),
              FilterChip(
                avatar: const Icon(Icons.hourglass_top, size: 18, color: Color(0xFFE08A00)),
                label: Text('Falta documento (${widget.clientes.where((c) => c.pendiente).length})'),
                selected: _soloSinDocumento,
                onSelected: (v) => setState(() => _soloSinDocumento = v),
              ),
              for (final e in Estado.values.where(
                (e) => e != Estado.pendienteCedula || widget.clientes.any((c) => c.estado == e),
              )) ...[
                const SizedBox(width: 8),
                FilterChip(
                  avatar: Icon(iconoEstado(e), size: 18, color: colorEstado(e)),
                  label: Text('${e.etiqueta} (${widget.clientes.where((c) => c.estado == e).length})'),
                  selected: _filtro == e,
                  onSelected: (s) => setState(() => _filtro = s ? e : null),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: l.isEmpty
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Vacio(Icons.search_off, 'No hay clientes que coincidan.'),
                    if (solo10)
                      FilledButton.icon(
                        onPressed: () => abrirNuevo(context, cedula: _busqueda.text.trim()),
                        icon: const Icon(Icons.person_add),
                        label: const Text('Registrar esta cédula'),
                      ),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: l.length,
                  itemBuilder: (_, i) => FilaCliente(l[i], onTap: () => abrirFicha(context, l[i])),
                ),
        ),
      ],
    );
  }
}

class _PestanaResumen extends StatefulWidget {
  final List<Cliente> clientes;
  const _PestanaResumen(this.clientes);

  @override
  State<_PestanaResumen> createState() => _PestanaResumenState();
}

class _PestanaResumenState extends State<_PestanaResumen> {
  DateTime _mes = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  Widget build(BuildContext context) {
    bool enMes(DateTime? d) => d != null && d.year == _mes.year && d.month == _mes.month;
    final l = widget.clientes;
    final registrados = l.where((c) => enMes(c.creadoEn)).length;
    final consultados = l
        .where(
          (c) =>
              c.cedula != null && c.estado != Estado.porConsultar && c.estado != Estado.pendienteCedula && enMes(c.fechaConsulta),
        )
        .toList();
    final aprobados = consultados.where((c) => c.estado == Estado.aprobado || c.estado == Estado.atendido).toList();
    final negados = consultados.where((c) => c.estado == Estado.negado).length;
    final vinieron = l.where((c) => c.estado == Estado.atendido && enMes(c.actualizadoEn)).toList();
    final cupo = aprobados.fold<double>(0, (s, c) => s + (c.monto ?? 0));
    final cupoUsado = vinieron.fold<double>(0, (s, c) => s + (c.monto ?? 0));
    final tasa = consultados.isEmpty ? null : (aprobados.length * 100 / consultados.length).round();
    final pendientes = l.where((c) => c.pendiente).length;
    const meses = [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ];
    final esActual = _mes.year == DateTime.now().year && _mes.month == DateTime.now().month;

    Widget tarjeta(String t, String v, IconData i, Color c) => SizedBox(
      width: 200,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(i, color: c),
              const SizedBox(height: 8),
              Text(v, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              Text(t, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => setState(() => _mes = DateTime(_mes.year, _mes.month - 1)),
            ),
            Text(
              '${meses[_mes.month - 1][0].toUpperCase()}${meses[_mes.month - 1].substring(1)} ${_mes.year}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: esActual ? null : () => setState(() => _mes = DateTime(_mes.year, _mes.month + 1)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            tarjeta('Clientes nuevos', '$registrados', Icons.person_add_alt, verdeMarca),
            tarjeta('Créditos consultados', '${consultados.length}', Icons.manage_search, Colors.blueGrey),
            tarjeta('Aprobados', '${aprobados.length}', Icons.check_circle, colorEstado(Estado.aprobado)),
            tarjeta('Negados', '$negados', Icons.cancel, colorEstado(Estado.negado)),
            tarjeta('Tasa de aprobación', tasa == null ? '—' : '$tasa %', Icons.percent, Colors.indigo),
            tarjeta('Cupo aprobado', dinero.format(cupo), Icons.payments, colorEstado(Estado.aprobado)),
            tarjeta('Vinieron a usarlo', '${vinieron.length}', Icons.how_to_reg, colorEstado(Estado.atendido)),
            tarjeta(
              'Cupo de los que vinieron',
              dinero.format(cupoUsado),
              Icons.shopping_bag_outlined,
              colorEstado(Estado.atendido),
            ),
            if (esActual) tarjeta('Falta documento', '$pendientes', Icons.hourglass_top, colorEstado(Estado.pendienteCedula)),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Cuenta la última consulta de cada cliente. Total en la agenda: ${l.length} clientes.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
