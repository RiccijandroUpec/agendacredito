import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'ui/arranque.dart';
import 'ui/comun.dart';
import 'ui/rapido.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es');
  runApp(const AgendaApp());
}

/// Punto de entrada de la ventana rápida de la burbuja (RapidoActivity).
@pragma('vm:entry-point')
Future<void> rapidoMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es');
  runApp(const AppRapida());
}

class AgendaApp extends StatelessWidget {
  const AgendaApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Agenda de Crédito',
    debugShowCheckedModeBanner: false,
    theme: tema(),
    locale: const Locale('es'),
    supportedLocales: const [Locale('es')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: const Arranque(),
  );
}
