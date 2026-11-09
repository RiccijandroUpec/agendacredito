import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../servicios/base.dart';
import '../servicios/nativo.dart';
import '../servicios/recordatorios.dart';
import '../servicios/respaldo.dart';
import '../servicios/seguridad.dart';
import 'arranque.dart';
import 'comun.dart';
import 'pin.dart';

const versionApp = '1.0.1';

class PantallaAjustes extends StatefulWidget {
  const PantallaAjustes({super.key});

  @override
  State<PantallaAjustes> createState() => _PantallaAjustesState();
}

class _PantallaAjustesState extends State<PantallaAjustes> with WidgetsBindingObserver {
  bool _huellaDisp = false, _huella = false, _conPin = false;
  int _bloqueo = 1;
  bool _permisoBurbuja = false, _burbuja = false;
  bool _avisos = true;
  int _hora = 8;
  bool _claveRespaldo = false, _auto = true;
  DateTime? _ultimo, _enviado;
  String _equipo = '';
  bool _trabajando = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cargar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    // Al volver de dar el permiso de "mostrar sobre otras apps".
    if (s == AppLifecycleState.resumed) _cargar();
  }

  Future<void> _cargar() async {
    final v = (
      await Seguridad.huellaDisponible(),
      await Seguridad.huellaActiva(),
      await Seguridad.minutosBloqueo(),
      await Nativo.permisoBurbuja(),
      await Nativo.burbujaActiva(),
      await Recordatorios.activos(),
      await Recordatorios.hora(),
      await Respaldo.tieneClave(),
      await Respaldo.automaticoActivo(),
      await Respaldo.ultimo(),
      await Respaldo.ultimoEnviado(),
      await Seguridad.codigoEquipo(),
      await Seguridad.tienePin(),
    );
    if (!mounted) return;
    setState(() {
      _huellaDisp = v.$1;
      _huella = v.$2;
      _bloqueo = v.$3;
      _permisoBurbuja = v.$4;
      _burbuja = v.$5;
      _avisos = v.$6;
      _hora = v.$7;
      _claveRespaldo = v.$8;
      _auto = v.$9;
      _ultimo = v.$10;
      _enviado = v.$11;
      _equipo = v.$12;
      _conPin = v.$13;
    });
  }

  Future<void> _tarea(Future<void> Function() f, {String? ok}) async {
    setState(() => _trabajando = true);
    try {
      await f();
      if (ok != null && mounted) aviso(context, ok);
    } on FormatException catch (e) {
      if (mounted) aviso(context, e.message, error: true);
    } catch (e) {
      if (mounted) aviso(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _trabajando = false);
      _cargar();
    }
  }

  // ---------- Seguridad ----------

  Future<void> _cambiarPin() async {
    if (_conPin && !await pedirPin(context, titulo: 'PIN actual')) return;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (c) => PantallaPin(
          modo: ModoPin.crear,
          titulo: _conPin ? 'PIN nuevo' : 'Crea tu PIN',
          alCancelar: () => Navigator.pop(c),
          alTerminar: (pin) async {
            await Seguridad.crearPin(pin);
            if (c.mounted) Navigator.pop(c);
            if (mounted) aviso(context, _conPin ? 'PIN cambiado' : 'PIN activado: la app lo pedirá al abrir');
          },
        ),
      ),
    );
    _cargar();
  }

  Future<void> _quitarPin() async {
    if (!await confirmar(
      context,
      'Quitar PIN',
      'La app abrirá sin pedir PIN. Cualquiera que tome la tablet podrá ver tus clientes.',
      si: 'Quitar',
      peligro: true,
    )) {
      return;
    }
    if (!mounted || !await pedirPin(context, titulo: 'PIN actual')) return;
    await Seguridad.quitarPin();
    if (mounted) aviso(context, 'PIN quitado');
    _cargar();
  }

  Future<void> _usarHuella(bool si) async {
    if (si) {
      Arranque.noBloquearAlVolver = true;
      if (!await Seguridad.pedirHuella()) return;
    }
    await Seguridad.usarHuella(si);
    _cargar();
  }

  // ---------- Burbuja ----------

  Future<void> _usarBurbuja(bool si) async {
    if (si && !_permisoBurbuja) {
      final ok = await confirmar(
        context,
        'Permiso para la burbuja',
        'Para que la burbuja aparezca encima de la app de crédito, Android pide permitir "Mostrar sobre otras apps". '
            'En la siguiente pantalla busca "Agenda de Crédito" y actívalo.',
        si: 'Ir a permitir',
      );
      if (!ok) return;
      Arranque.noBloquearAlVolver = true;
      await Nativo.pedirPermisoBurbuja();
      return;
    }
    await (si ? Nativo.mostrarBurbuja() : Nativo.ocultarBurbuja());
    await Future.delayed(const Duration(milliseconds: 300));
    _cargar();
  }

  // ---------- Respaldo ----------

  Future<void> _claveDeRespaldo() async {
    if (_claveRespaldo && !await pedirPin(context)) return;
    if (!mounted) return;
    final clave = await showDialog<String>(context: context, builder: (_) => const _DialogoClave());
    if (clave == null) return;
    await Respaldo.guardarClave(clave);
    await Base.repo.guardarAjuste('cambios_sin_respaldo', '1');
    await Respaldo.automatico();
    if (mounted) aviso(context, 'Clave de respaldo guardada. Anótala en un lugar seguro: sin ella no se puede restaurar.');
    _cargar();
  }

  Future<void> _enviar() async {
    Arranque.noBloquearAlVolver = true;
    await _tarea(Respaldo.enviar);
  }

  Future<void> _restaurar() async {
    final ok = await confirmar(
      context,
      'Restaurar respaldo',
      'Se reemplazarán TODOS los clientes de esta tablet por los del respaldo. ¿Continuar?',
      si: 'Elegir archivo',
      peligro: true,
    );
    if (!ok || !mounted) return;
    if (!await pedirPin(context)) return;
    Arranque.noBloquearAlVolver = true;
    final archivo = await openFile();
    if (archivo == null || !mounted) return;
    final bytes = await archivo.readAsBytes();
    if (!mounted) return;
    final clave = await showDialog<String>(context: context, builder: (_) => const _DialogoClave(soloPedir: true));
    if (clave == null) return;
    await _tarea(() async {
      final n = await Respaldo.restaurar(bytes, clave);
      await Recordatorios.reprogramar();
      if (mounted) aviso(context, 'Listo: se restauraron $n clientes');
    });
  }

  Future<void> _excel() async {
    if (!await pedirPin(context, titulo: 'PIN para exportar')) return;
    Arranque.noBloquearAlVolver = true;
    await _tarea(Respaldo.exportarExcel);
  }

  Future<void> _verificar() async {
    final (total, malo) = await Base.repo.verificarSellos();
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        icon: Icon(malo == null ? Icons.verified : Icons.gpp_bad, color: malo == null ? Colors.green : Colors.red, size: 40),
        title: Text(malo == null ? 'Historial intacto' : 'Historial alterado'),
        content: Text(
          malo == null
              ? 'Se revisaron $total registros. Ninguna fecha ni dato del historial fue modificado por fuera de la app.'
              : 'El registro #$malo del historial no coincide con su sello: alguien modificó la base por fuera de la app.',
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Cerrar'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String fecha(DateTime? d) => d == null
        ? 'Nunca'
        : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    Widget seccion(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
      child: Text(
        t,
        style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajustes'),
        bottom: _trabajando ? const PreferredSize(preferredSize: Size.fromHeight(4), child: LinearProgressIndicator()) : null,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              seccion('Burbuja'),
              SwitchListTile(
                secondary: const Icon(Icons.bubble_chart_outlined),
                title: const Text('Mostrar burbuja sobre otras apps'),
                subtitle: Text(
                  _permisoBurbuja
                      ? 'Mientras revisas un crédito, toca la burbuja para anotar al cliente sin salir de la app de crédito.'
                      : 'Falta el permiso "Mostrar sobre otras apps".',
                ),
                value: _burbuja,
                onChanged: _usarBurbuja,
              ),
              ListTile(
                leading: const Icon(Icons.phone_android),
                title: const Text('¿La burbuja no abre el formulario?'),
                subtitle: const Text(
                  'En Xiaomi/Redmi: Ajustes de la app → Otros permisos → activa "Mostrar ventanas emergentes '
                  'mientras se ejecuta en segundo plano". En otras marcas, desactiva el ahorro de batería para esta app.',
                ),
                trailing: const Icon(Icons.open_in_new),
                onTap: () {
                  Arranque.noBloquearAlVolver = true;
                  Nativo.abrirAjustesApp();
                },
              ),
              seccion('Respaldo (para no perder tus clientes)'),
              ListTile(
                leading: const Icon(Icons.key),
                title: Text(_claveRespaldo ? 'Cambiar clave de respaldo' : 'Crear clave de respaldo'),
                subtitle: const Text('Los respaldos van cifrados con esta clave. Sin ella nadie puede abrirlos, ni tú.'),
                onTap: _claveDeRespaldo,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.download_for_offline_outlined),
                title: const Text('Respaldo automático diario'),
                subtitle: Text('Guarda una copia cifrada en Descargas/AgendaCredito. Último: ${fecha(_ultimo)}'),
                value: _auto && _claveRespaldo,
                onChanged: _claveRespaldo ? (v) => Respaldo.usarAutomatico(v).then((_) => _cargar()) : null,
              ),
              ListTile(
                leading: const Icon(Icons.cloud_upload_outlined),
                title: const Text('Enviar respaldo a Drive, correo o WhatsApp'),
                subtitle: Text('Así lo tienes aunque se pierda la tablet. Último envío: ${fecha(_enviado)}'),
                enabled: _claveRespaldo && !_trabajando,
                onTap: _enviar,
              ),
              ListTile(
                leading: const Icon(Icons.restore),
                title: const Text('Restaurar desde un respaldo'),
                subtitle: const Text('En una tablet nueva o después de reinstalar.'),
                enabled: !_trabajando,
                onTap: _restaurar,
              ),
              ListTile(
                leading: const Icon(Icons.table_view_outlined),
                title: const Text('Exportar a Excel'),
                subtitle: const Text('Lista de clientes en .csv. Ojo: este archivo NO va cifrado.'),
                enabled: !_trabajando,
                onTap: _excel,
              ),
              seccion('Seguridad'),
              if (!_conPin)
                ListTile(
                  leading: const Icon(Icons.pin_outlined),
                  title: const Text('Proteger con PIN'),
                  subtitle: const Text(
                    'Sin PIN, cualquiera que tome la tablet ve tus clientes. Con PIN: bloqueo, huella y '
                    'confirmación para exportar o borrar.',
                  ),
                  onTap: _cambiarPin,
                )
              else ...[
                ListTile(leading: const Icon(Icons.pin_outlined), title: const Text('Cambiar PIN'), onTap: _cambiarPin),
                ListTile(leading: const Icon(Icons.no_encryption_outlined), title: const Text('Quitar PIN'), onTap: _quitarPin),
              ],
              if (_conPin && _huellaDisp)
                SwitchListTile(
                  secondary: const Icon(Icons.fingerprint),
                  title: const Text('Desbloquear con huella'),
                  value: _huella,
                  onChanged: _usarHuella,
                ),
              if (_conPin)
                ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: const Text('Bloquear al salir de la app'),
                  trailing: DropdownButton<int>(
                    value: _bloqueo,
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('De inmediato')),
                      DropdownMenuItem(value: 1, child: Text('Después de 1 min')),
                      DropdownMenuItem(value: 5, child: Text('Después de 5 min')),
                      DropdownMenuItem(value: 15, child: Text('Después de 15 min')),
                    ],
                    onChanged: (v) => Seguridad.guardarMinutosBloqueo(v!).then((_) => _cargar()),
                  ),
                ),
              ListTile(
                leading: const Icon(Icons.verified_outlined),
                title: const Text('Verificar historial y sellos'),
                subtitle: const Text('Comprueba que nadie cambió fechas de registro por fuera de la app.'),
                onTap: _verificar,
              ),
              seccion('Recordatorios'),
              SwitchListTile(
                secondary: const Icon(Icons.notifications_outlined),
                title: const Text('Avisarme los días que vienen clientes'),
                subtitle: const Text('El aviso no muestra nombres ni cédulas.'),
                value: _avisos,
                onChanged: (v) async {
                  if (v) await Recordatorios.pedirPermiso();
                  await Recordatorios.usar(v);
                  _cargar();
                },
              ),
              ListTile(
                leading: const Icon(Icons.schedule),
                title: const Text('Hora del aviso'),
                enabled: _avisos,
                trailing: DropdownButton<int>(
                  value: _hora,
                  items: [
                    for (var h = 6; h <= 12; h++) DropdownMenuItem(value: h, child: Text('${h.toString().padLeft(2, '0')}:00')),
                  ],
                  onChanged: _avisos ? (v) => Recordatorios.guardarHora(v!).then((_) => _cargar()) : null,
                ),
              ),
              seccion('Acerca de'),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Agenda de Crédito $versionApp'),
                subtitle: Text('Equipo $_equipo\n© Riccijandro. Todos los derechos reservados.'),
                isThreeLine: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogoClave extends StatefulWidget {
  final bool soloPedir;
  const _DialogoClave({this.soloPedir = false});

  @override
  State<_DialogoClave> createState() => _DialogoClaveState();
}

class _DialogoClaveState extends State<_DialogoClave> {
  final _a = TextEditingController(), _b = TextEditingController();
  String? _error;
  bool _ver = false;

  void _aceptar() {
    if (widget.soloPedir) {
      if (_a.text.isEmpty) return;
      Navigator.pop(context, _a.text);
      return;
    }
    if (_a.text.length < 8) return setState(() => _error = 'Mínimo 8 caracteres');
    if (_a.text != _b.text) return setState(() => _error = 'No coinciden');
    Navigator.pop(context, _a.text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.soloPedir ? 'Clave del respaldo' : 'Clave de respaldo'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!widget.soloPedir)
          const Text('Elige una clave que recuerdes y anótala fuera de la tablet. La necesitarás para restaurar en otra tablet.'),
        const SizedBox(height: 12),
        TextField(
          controller: _a,
          obscureText: !_ver,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Clave',
            errorText: widget.soloPedir ? null : _error,
            suffixIcon: IconButton(
              icon: Icon(_ver ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _ver = !_ver),
            ),
          ),
        ),
        if (!widget.soloPedir) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _b,
            obscureText: !_ver,
            decoration: const InputDecoration(labelText: 'Repite la clave'),
          ),
        ],
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
      FilledButton(onPressed: _aceptar, child: const Text('Aceptar')),
    ],
  );
}
