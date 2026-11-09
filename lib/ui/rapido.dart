import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../servicios/base.dart';
import '../servicios/nativo.dart';
import '../servicios/seguridad.dart';
import 'comun.dart';
import 'formulario.dart';

/// Ventana que abre la burbuja encima de la app de crédito. Corre en su
/// propio motor de Flutter (precalentado por BurbujaService) y no pide PIN
/// aunque esté configurado: solo deja anotar, nunca muestra clientes guardados.
class AppRapida extends StatelessWidget {
  const AppRapida({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: tema(),
    color: Colors.transparent,
    locale: const Locale('es'),
    supportedLocales: const [Locale('es')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: const _Rapido(),
  );
}

class _Rapido extends StatefulWidget {
  const _Rapido();

  @override
  State<_Rapido> createState() => _RapidoState();
}

class _RapidoState extends State<_Rapido> {
  int _vez = 0;
  bool? _listo;
  bool _guardado = false;

  @override
  void initState() {
    super.initState();
    Nativo.alAbrirRapido(() {
      if (!mounted) return;
      setState(() {
        _vez++;
        _guardado = false;
      });
      _revisar();
    });
    _revisar();
  }

  Future<void> _revisar() async {
    try {
      await Base.abrir();
      final ok = await Seguridad.activado();
      if (mounted) setState(() => _listo = ok);
    } catch (_) {
      if (mounted) setState(() => _listo = false);
    }
  }

  void _cerrar() {
    FocusManager.instance.primaryFocus?.unfocus();
    Nativo.cerrarRapido();
  }

  @override
  Widget build(BuildContext context) {
    final contenido = switch (_listo) {
      null => const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      ),
      false => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 48),
            const SizedBox(height: 12),
            const Text('Abre primero la Agenda de Crédito para activarla.', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: _cerrar, child: const Text('Cerrar')),
          ],
        ),
      ),
      true when _guardado => const Padding(
        padding: EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 72, color: Color(0xFF1B8A3C)),
            SizedBox(height: 12),
            Text('Guardado en tu agenda', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      true => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: FormularioCliente(
          key: ValueKey(_vez),
          rapido: true,
          alCancelar: _cerrar,
          alGuardar: (_) async {
            setState(() => _guardado = true);
            await Future.delayed(const Duration(milliseconds: 900));
            _cerrar();
          },
        ),
      ),
    };

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, _) => _cerrar(),
      child: Scaffold(
        backgroundColor: Colors.black54,
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(onTap: _cerrar, behavior: HitTestBehavior.opaque),
              ),
              Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 620, maxHeight: MediaQuery.sizeOf(context).height * .94),
                  child: Material(
                    elevation: 12,
                    borderRadius: BorderRadius.circular(24),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: verdeMarca,
                            foregroundColor: Colors.white,
                            child: Icon(Icons.edit_note),
                          ),
                          title: const Text('Anotar cliente', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                          subtitle: const Text('Agenda de Crédito'),
                          trailing: IconButton(icon: const Icon(Icons.close), onPressed: _cerrar),
                        ),
                        Flexible(child: contenido),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
