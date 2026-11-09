import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../servicios/seguridad.dart';

enum ModoPin { crear, verificar }

/// Teclado de PIN grande, pensado para tablet.
class PantallaPin extends StatefulWidget {
  final ModoPin modo;
  final String titulo;
  final ValueChanged<String> alTerminar;
  final bool permitirHuella;
  final VoidCallback? alCancelar;

  const PantallaPin({
    super.key,
    required this.modo,
    required this.alTerminar,
    this.titulo = 'Ingresa tu PIN',
    this.permitirHuella = false,
    this.alCancelar,
  });

  @override
  State<PantallaPin> createState() => _PantallaPinState();
}

class _PantallaPinState extends State<PantallaPin> {
  static const largo = 6;
  String _pin = '';
  String? _primero;
  String? _error;
  bool _ocupado = false;
  int _espera = 0;
  Timer? _reloj;
  bool _huella = false;

  @override
  void initState() {
    super.initState();
    if (widget.modo == ModoPin.verificar) {
      _revisarEspera();
      if (widget.permitirHuella) _probarHuella(auto: true);
    }
  }

  Future<void> _probarHuella({bool auto = false}) async {
    if (!await Seguridad.huellaActiva() || !await Seguridad.huellaDisponible()) return;
    if (!mounted) return;
    setState(() => _huella = true);
    if (auto) await Future.delayed(const Duration(milliseconds: 300));
    if (await Seguridad.pedirHuella()) widget.alTerminar('');
  }

  Future<void> _revisarEspera() async {
    final s = await Seguridad.esperaRestante();
    if (!mounted) return;
    setState(() => _espera = s);
    _reloj?.cancel();
    if (s > 0) {
      _reloj = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return t.cancel();
        setState(() => _espera--);
        if (_espera <= 0) t.cancel();
      });
    }
  }

  @override
  void dispose() {
    _reloj?.cancel();
    super.dispose();
  }

  String get _subtitulo {
    if (_espera > 0) return 'Demasiados intentos. Espera $_espera s';
    if (widget.modo == ModoPin.crear) {
      return _primero == null ? 'Crea un PIN de $largo números' : 'Escríbelo otra vez para confirmar';
    }
    return '$largo números';
  }

  void _tecla(String d) {
    if (_ocupado || _espera > 0 || _pin.length >= largo) return;
    HapticFeedback.selectionClick();
    setState(() {
      _pin += d;
      _error = null;
    });
    if (_pin.length == largo) _completo();
  }

  void _borrar() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _completo() async {
    final pin = _pin;
    if (widget.modo == ModoPin.crear) {
      if (_primero == null) {
        if (RegExp(r'^(\d)\1+$').hasMatch(pin) || '0123456789'.contains(pin) || '9876543210'.contains(pin)) {
          setState(() {
            _pin = '';
            _error = 'Muy fácil de adivinar. Usa otro.';
          });
          return;
        }
        setState(() {
          _primero = pin;
          _pin = '';
        });
      } else if (_primero == pin) {
        widget.alTerminar(pin);
      } else {
        setState(() {
          _primero = null;
          _pin = '';
          _error = 'No coinciden. Empieza otra vez.';
        });
      }
      return;
    }
    setState(() => _ocupado = true);
    final ok = await Seguridad.verificarPin(pin);
    if (!mounted) return;
    if (ok) {
      widget.alTerminar(pin);
      return;
    }
    final f = await Seguridad.fallos();
    HapticFeedback.heavyImpact();
    setState(() {
      _ocupado = false;
      _pin = '';
      _error = f >= 3 && f < 5 ? 'PIN incorrecto. Te quedan ${5 - f} intentos' : 'PIN incorrecto';
    });
    _revisarEspera();
  }

  @override
  Widget build(BuildContext context) {
    final esq = Theme.of(context).colorScheme;
    Widget boton(String t, {VoidCallback? accion, Widget? hijo}) => Padding(
      padding: const EdgeInsets.all(8),
      child: SizedBox(
        width: 84,
        height: 84,
        child: hijo == null && t.isEmpty
            ? null
            : FilledButton.tonal(
                style: FilledButton.styleFrom(shape: const CircleBorder(), padding: EdgeInsets.zero),
                onPressed: accion ?? () => _tecla(t),
                child: hijo ?? Text(t, style: const TextStyle(fontSize: 30)),
              ),
      ),
    );

    return Scaffold(
      appBar: widget.alCancelar == null ? null : AppBar(leading: CloseButton(onPressed: widget.alCancelar)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 48, color: esq.primary),
                const SizedBox(height: 12),
                Text(widget.titulo, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 6),
                Text(_subtitulo, style: TextStyle(color: esq.onSurfaceVariant)),
                const SizedBox(height: 24),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                    largo,
                    (i) => Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < _pin.length ? esq.primary : Colors.transparent,
                        border: Border.all(color: esq.primary, width: 2),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: 36,
                  child: Center(
                    child: Text(
                      _error ?? '',
                      style: TextStyle(color: esq.error, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                for (final fila in const [
                  ['1', '2', '3'],
                  ['4', '5', '6'],
                  ['7', '8', '9'],
                ])
                  Row(mainAxisSize: MainAxisSize.min, children: [for (final t in fila) boton(t)]),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _huella ? boton('', accion: () => _probarHuella(), hijo: const Icon(Icons.fingerprint, size: 36)) : boton(''),
                    boton('0'),
                    boton('', accion: _borrar, hijo: const Icon(Icons.backspace_outlined, size: 28)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pide el PIN antes de una acción delicada (exportar, borrar, restaurar).
/// Si el usuario no configuró PIN, deja pasar.
Future<bool> pedirPin(BuildContext context, {String titulo = 'Confirma con tu PIN'}) async {
  if (!await Seguridad.tienePin()) return true;
  if (!context.mounted) return false;
  final ok = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (c) => PantallaPin(
        modo: ModoPin.verificar,
        titulo: titulo,
        permitirHuella: true,
        alTerminar: (_) => Navigator.pop(c, true),
        alCancelar: () => Navigator.pop(c, false),
      ),
    ),
  );
  return ok ?? false;
}
