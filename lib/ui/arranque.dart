import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../servicios/base.dart';
import '../servicios/recordatorios.dart';
import '../servicios/respaldo.dart';
import '../servicios/seguridad.dart';
import 'comun.dart';
import 'inicio.dart';
import 'pin.dart';

enum _Paso { cargando, activar, bloqueado, listo, error }

/// Decide qué mostrar: activación → (PIN, si el usuario lo configuró) →
/// agenda. Con PIN, vuelve a bloquear cuando la app pasa un rato en segundo plano.
class Arranque extends StatefulWidget {
  const Arranque({super.key});

  /// Para compartir, elegir un archivo o usar la huella la app sale un
  /// momento a segundo plano: con esto no se bloquea al volver.
  static bool noBloquearAlVolver = false;

  @override
  State<Arranque> createState() => _ArranqueState();
}

class _ArranqueState extends State<Arranque> with WidgetsBindingObserver {
  _Paso _paso = _Paso.cargando;
  String _error = '';
  DateTime? _salida;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _iniciar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _iniciar() async {
    try {
      await Base.abrir();
      if (!await Seguridad.activado()) return setState(() => _paso = _Paso.activar);
      if (!await Seguridad.tienePin()) return _desbloqueado();
      setState(() => _paso = _Paso.bloqueado);
    } catch (e) {
      setState(() {
        _paso = _Paso.error;
        _error = '$e';
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) async {
    if (s == AppLifecycleState.paused || s == AppLifecycleState.hidden) {
      _salida ??= DateTime.now();
      if (_paso == _Paso.listo) Respaldo.automatico();
    } else if (s == AppLifecycleState.resumed) {
      final salida = _salida;
      _salida = null;
      if (_paso != _Paso.listo) return;
      Base.avisar(); // por si la burbuja agregó clientes
      if (Arranque.noBloquearAlVolver) {
        Arranque.noBloquearAlVolver = false;
        return;
      }
      if (salida != null &&
          await Seguridad.tienePin() &&
          DateTime.now().difference(salida).inSeconds >= (await Seguridad.minutosBloqueo()) * 60) {
        if (mounted) setState(() => _paso = _Paso.bloqueado);
      }
    }
  }

  Future<void> _desbloqueado() async {
    setState(() => _paso = _Paso.listo);
    if (await Base.repo.ajuste('permiso_avisos') == null) {
      await Base.repo.guardarAjuste('permiso_avisos', '1');
      await Recordatorios.pedirPermiso();
    }
    Recordatorios.reprogramar();
    Respaldo.automatico();
  }

  @override
  Widget build(BuildContext context) => switch (_paso) {
    _Paso.cargando => const Scaffold(body: Center(child: CircularProgressIndicator())),
    _Paso.error => Scaffold(body: Vacio(Icons.error_outline, 'No se pudo abrir la agenda.\n$_error')),
    _Paso.activar => PantallaActivacion(alActivar: _iniciar),
    _Paso.bloqueado => PantallaPin(
      key: UniqueKey(),
      modo: ModoPin.verificar,
      titulo: 'Agenda de Crédito',
      permitirHuella: true,
      alTerminar: (_) => _desbloqueado(),
    ),
    _Paso.listo => Inicio(
      alBloquear: () async {
        if (await Seguridad.tienePin()) setState(() => _paso = _Paso.bloqueado);
      },
    ),
  };
}

class PantallaActivacion extends StatefulWidget {
  final VoidCallback alActivar;
  const PantallaActivacion({super.key, required this.alActivar});

  @override
  State<PantallaActivacion> createState() => _PantallaActivacionState();
}

class _PantallaActivacionState extends State<PantallaActivacion> {
  final _codigo = TextEditingController();
  String _equipo = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    Seguridad.codigoEquipo().then((c) => setState(() => _equipo = c));
  }

  Future<void> _activar() async {
    if (await Seguridad.activar(_codigo.text)) {
      widget.alActivar();
    } else {
      setState(() => _error = 'Ese código no es para esta tablet. Revisa que lo copiaste completo.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                const Icon(Icons.verified_user_outlined, size: 56, color: verdeMarca),
                const SizedBox(height: 12),
                Text('Activa esta tablet', style: t.headlineSmall, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                const Text(
                  'La Agenda de Crédito solo funciona en tablets autorizadas. '
                  'Envía este código de equipo al administrador y pega aquí el código de activación que te responda.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Text('Código de equipo'),
                        const SizedBox(height: 6),
                        SelectableText(
                          _equipo,
                          style: t.headlineMedium?.copyWith(
                            fontFamily: 'monospace',
                            letterSpacing: 2,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton.icon(
                              icon: const Icon(Icons.copy),
                              label: const Text('Copiar'),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: _equipo));
                                aviso(context, 'Código copiado');
                              },
                            ),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.share),
                              label: const Text('Enviar'),
                              onPressed: () =>
                                  SharePlus.instance.share(ShareParams(text: 'Código de equipo Agenda de Crédito: $_equipo')),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _codigo,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: 'Código de activación (AC1-...)',
                    errorText: _error,
                    suffixIcon: IconButton(
                      tooltip: 'Pegar',
                      icon: const Icon(Icons.content_paste),
                      onPressed: () async {
                        final d = await Clipboard.getData('text/plain');
                        if (d?.text != null) setState(() => _codigo.text = d!.text!.trim());
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(onPressed: _activar, icon: const Icon(Icons.check), label: const Text('Activar')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
