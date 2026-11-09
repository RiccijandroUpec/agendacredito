import 'dart:isolate';

import 'package:local_auth/local_auth.dart';

import '../nucleo/activacion.dart';
import '../nucleo/cifrado.dart';
import 'base.dart';
import 'nativo.dart';

/// PIN, huella, bloqueo automático y activación del equipo.
class Seguridad {
  static final _auth = LocalAuthentication();

  // ---------- Activación ----------

  static String? _androidId;
  static Future<String> androidId() async => _androidId ??= await Nativo.androidId();

  static Future<String> codigoEquipo() async => Activacion.codigoEquipo(await androidId());

  /// Apagado en 1.0.1 por pedido del usuario (instalar sin PC). Poner en true
  /// para volver a exigir el código de activación por tablet.
  static const exigirActivacion = false;

  static Future<bool> activado() async {
    if (!exigirActivacion) return true;
    final codigo = await almacen.read(key: 'activacion');
    return codigo != null && Activacion.verificar(codigo, await androidId());
  }

  static Future<bool> activar(String codigo) async {
    if (!Activacion.verificar(codigo, await androidId())) return false;
    await almacen.write(key: 'activacion', value: codigo.trim().toUpperCase());
    return true;
  }

  // ---------- PIN ----------

  static Future<bool> tienePin() async => (await almacen.read(key: 'pin')) != null;

  /// Quita el PIN (y la huella, que solo es un atajo del PIN).
  static Future<void> quitarPin() async {
    await almacen.delete(key: 'pin');
    await almacen.delete(key: 'pin_fallos');
    await almacen.delete(key: 'pin_espera');
    await usarHuella(false);
  }

  static Future<void> crearPin(String pin) async {
    final h = await Isolate.run(() => Cifrado.hashPin(pin));
    await almacen.write(key: 'pin', value: h);
    await almacen.delete(key: 'pin_fallos');
    await almacen.delete(key: 'pin_espera');
  }

  /// Segundos que faltan para poder volver a intentar, o 0.
  static Future<int> esperaRestante() async {
    final hasta = DateTime.tryParse(await almacen.read(key: 'pin_espera') ?? '');
    if (hasta == null) return 0;
    final s = hasta.difference(DateTime.now()).inSeconds;
    return s > 0 ? s : 0;
  }

  /// Verifica el PIN. Después de 5 fallos seguidos obliga a esperar
  /// (30 s, 1 min, 2 min, ... hasta 30 min).
  static Future<bool> verificarPin(String pin) async {
    if (await esperaRestante() > 0) return false;
    final guardado = await almacen.read(key: 'pin');
    if (guardado == null) return false;
    final ok = await Isolate.run(() => Cifrado.verificarPin(pin, guardado));
    if (ok) {
      await almacen.delete(key: 'pin_fallos');
      return true;
    }
    final fallos = int.parse(await almacen.read(key: 'pin_fallos') ?? '0') + 1;
    await almacen.write(key: 'pin_fallos', value: '$fallos');
    if (fallos >= 5) {
      final seg = (30 * (1 << (fallos - 5))).clamp(30, 1800);
      await almacen.write(
        key: 'pin_espera',
        value: DateTime.now().add(Duration(seconds: seg)).toIso8601String(),
      );
    }
    return false;
  }

  static Future<int> fallos() async => int.parse(await almacen.read(key: 'pin_fallos') ?? '0');

  // ---------- Huella ----------

  static Future<bool> huellaDisponible() async {
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> huellaActiva() async => (await Base.repo.ajuste('huella')) == '1';
  static Future<void> usarHuella(bool si) => Base.repo.guardarAjuste('huella', si ? '1' : null);

  static Future<bool> pedirHuella() async {
    try {
      return await _auth.authenticate(localizedReason: 'Desbloquea tu agenda de crédito', biometricOnly: true);
    } catch (_) {
      return false;
    }
  }

  // ---------- Bloqueo automático ----------

  /// Minutos fuera de la app antes de pedir el PIN otra vez (0 = siempre).
  static Future<int> minutosBloqueo() async => int.tryParse(await Base.repo.ajuste('bloqueo_min') ?? '') ?? 1;
  static Future<void> guardarMinutosBloqueo(int m) => Base.repo.guardarAjuste('bloqueo_min', '$m');
}
