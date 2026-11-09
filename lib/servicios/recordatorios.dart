import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../datos/modelo.dart';
import 'base.dart';

/// Aviso a la mañana de cada día con visitas. El texto nunca dice nombres ni
/// cédulas: la notificación se ve en la pantalla bloqueada.
class Recordatorios {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _listo = false;

  static Future<void> _iniciar() async {
    if (_listo) return;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('America/Guayaquil'));
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    );
    _listo = true;
  }

  static Future<bool> activos() async => (await Base.repo.ajuste('avisos')) != '0';
  static Future<void> usar(bool si) async {
    await Base.repo.guardarAjuste('avisos', si ? '1' : '0');
    await reprogramar();
  }

  static Future<int> hora() async => int.tryParse(await Base.repo.ajuste('hora_aviso') ?? '') ?? 8;
  static Future<void> guardarHora(int h) async {
    await Base.repo.guardarAjuste('hora_aviso', '$h');
    await reprogramar();
  }

  static Future<void> pedirPermiso() async {
    await _iniciar();
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// Borra y vuelve a programar los avisos de los próximos 60 días.
  static Future<void> reprogramar() async {
    try {
      await _iniciar();
      await _plugin.cancelAll();
      if (!await activos()) return;
      final h = await hora();
      final ahora = tz.TZDateTime.now(tz.local);
      final porDia = <String, int>{};
      for (final c in await Base.repo.todos()) {
        if (c.fechaVisita == null || c.estado == Estado.atendido || c.estado == Estado.negado) continue;
        final k = Dia.texto(c.fechaVisita!);
        porDia[k] = (porDia[k] ?? 0) + 1;
      }
      var id = 1;
      for (final MapEntry(key: dia, value: n) in porDia.entries) {
        final d = DateTime.parse(dia);
        var cuando = tz.TZDateTime(tz.local, d.year, d.month, d.day, h);
        if (cuando.isBefore(ahora)) {
          // Si hoy ya pasó la hora, avisa en un minuto (solo para hoy).
          if (Dia.texto(ahora) != dia) continue;
          cuando = ahora.add(const Duration(minutes: 1));
        }
        if (cuando.difference(ahora).inDays > 60) continue;
        await _plugin.zonedSchedule(
          id: id++,
          scheduledDate: cuando,
          title: n == 1 ? 'Hoy puede venir 1 cliente' : 'Hoy pueden venir $n clientes',
          body: 'Abre tu agenda para verlos.',
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'visitas',
              'Visitas del día',
              channelDescription: 'Aviso a la mañana de los clientes que pueden venir',
              importance: Importance.high,
              priority: Priority.high,
              visibility: NotificationVisibility.private,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (_) {
      // Sin permiso de notificaciones: la pestaña "Hoy" igual los muestra.
    }
  }
}
