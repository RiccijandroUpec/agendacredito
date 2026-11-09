import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../datos/modelo.dart';

const verdeMarca = Color(0xFF0E7C66);

ThemeData tema() {
  final esquema = ColorScheme.fromSeed(seedColor: verdeMarca);
  return ThemeData(
    colorScheme: esquema,
    useMaterial3: true,
    visualDensity: VisualDensity.standard,
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(64, 52), textStyle: const TextStyle(fontSize: 16)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: const Size(64, 52))),
  );
}

Color colorEstado(Estado e) => switch (e) {
  Estado.pendienteCedula => const Color(0xFFE08A00),
  Estado.aprobado => const Color(0xFF1B8A3C),
  Estado.negado => const Color(0xFFC62828),
  Estado.porConsultar => const Color(0xFF1565C0),
  Estado.atendido => const Color(0xFF455A64),
};

IconData iconoEstado(Estado e) => switch (e) {
  Estado.pendienteCedula => Icons.hourglass_top,
  Estado.aprobado => Icons.check_circle,
  Estado.negado => Icons.cancel,
  Estado.porConsultar => Icons.schedule,
  Estado.atendido => Icons.how_to_reg,
};

class ChipFaltaDocumento extends StatelessWidget {
  const ChipFaltaDocumento({super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: const Color(0x1FE08A00), borderRadius: BorderRadius.circular(20)),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.hourglass_top, size: 16, color: Color(0xFFE08A00)),
        SizedBox(width: 4),
        Text(
          'Falta documento',
          style: TextStyle(color: Color(0xFFE08A00), fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ],
    ),
  );
}

class ChipEstado extends StatelessWidget {
  final Estado estado;
  const ChipEstado(this.estado, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = colorEstado(estado);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconoEstado(estado), size: 16, color: c),
          const SizedBox(width: 4),
          Text(
            estado.etiqueta,
            style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

String iniciales(String nombre) {
  final p = nombre
      .trim()
      .split(RegExp(r'\s+'))
      .where((s) => s.isNotEmpty && RegExp(r'[A-Za-zÁÉÍÓÚÑáéíóúñ]').hasMatch(s[0]))
      .toList();
  if (p.isEmpty) return '#';
  return (p.length == 1 ? p[0][0] : '${p[0][0]}${p[1][0]}').toUpperCase();
}

class FilaCliente extends StatelessWidget {
  final Cliente cliente;
  final VoidCallback onTap;
  final Widget? extra;
  const FilaCliente(this.cliente, {super.key, required this.onTap, this.extra});

  @override
  Widget build(BuildContext context) {
    final c = cliente;
    final partes = <String>[
      if (c.cedula != null) c.cedula!,
      if (c.ciudad.isNotEmpty) c.ciudad,
      if (c.monto != null && c.estado != Estado.negado) 'Cupo ${dinero.format(c.monto)}',
      if (c.telefono.isNotEmpty) c.telefono,
    ];
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: colorEstado(c.estado).withValues(alpha: .15),
          foregroundColor: colorEstado(c.estado),
          child: Text(iniciales(c.nombre)),
        ),
        title: Text(
          c.nombreVisible,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [if (partes.isNotEmpty) Text(partes.join(' · ')), ?extra],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            ChipEstado(c.estado),
            if (c.cedula != null && !c.documento) ...[const SizedBox(height: 4), const ChipFaltaDocumento()],
            if (c.fechaVisita != null && c.estado != Estado.atendido && c.estado != Estado.negado) ...[
              const SizedBox(height: 4),
              Text(
                'Viene: ${Dia.relativo(c.fechaVisita!)}',
                style: TextStyle(
                  fontSize: 12,
                  color: c.fechaVisita!.isBefore(Dia.hoy())
                      ? Colors.red.shade700
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class Vacio extends StatelessWidget {
  final IconData icono;
  final String texto;
  const Vacio(this.icono, this.texto, {super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(
            texto,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 16),
          ),
        ],
      ),
    ),
  );
}

void aviso(BuildContext context, String texto, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(texto), backgroundColor: error ? Colors.red.shade700 : null, behavior: SnackBarBehavior.floating),
  );
}

Future<bool> confirmar(BuildContext context, String titulo, String texto, {String si = 'Sí', bool peligro = false}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(titulo),
        content: Text(texto),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(
            style: peligro ? FilledButton.styleFrom(backgroundColor: Colors.red.shade700) : null,
            onPressed: () => Navigator.pop(c, true),
            child: Text(si),
          ),
        ],
      ),
    ) ??
    false;

// ---------- Contacto ----------

/// 0991234567 → 593991234567.
String? telefonoInternacional(String t) {
  final d = t.replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('593') && d.length >= 11) return d;
  if (d.startsWith('0') && d.length == 10) return '593${d.substring(1)}';
  if (d.length == 9 && d.startsWith('9')) return '593$d';
  return null;
}

Future<void> llamar(String telefono) => launchUrl(Uri(scheme: 'tel', path: telefono.replaceAll(RegExp(r'[^\d+]'), '')));

Future<bool> whatsapp(String telefono, String mensaje) async {
  final n = telefonoInternacional(telefono);
  if (n == null) return false;
  return launchUrl(Uri.parse('https://wa.me/$n?text=${Uri.encodeComponent(mensaje)}'), mode: LaunchMode.externalApplication);
}

/// Mensajes listos para WhatsApp según el estado del cliente.
List<(String, String)> mensajesWhatsapp(Cliente c) {
  final nombre = c.nombre.trim().isEmpty
      ? ''
      : ' ${c.nombre.trim().split(RegExp(r'\s+')).first.toLowerCase().replaceFirstMapped(RegExp(r'^.'), (m) => m[0]!.toUpperCase())}';
  final cuando = c.fechaVisita == null ? '' : ' ${Dia.relativo(c.fechaVisita!).toLowerCase()}';
  return [
    if (c.pendiente)
      (
        'Recordar traer la cédula',
        'Hola$nombre, le saluda su asesor de crédito. Le recuerdo traer su cédula para revisar su crédito. ¡Le espero$cuando!',
      ),
    if (c.estado == Estado.aprobado)
      (
        'Avisar cupo aprobado',
        'Hola$nombre, ¡buenas noticias! Su crédito fue aprobado${c.monto != null ? ' por ${dinero.format(c.monto)}' : ''}. Le espero$cuando para que pueda usarlo.',
      ),
    if (c.estado == Estado.aprobado && c.fechaVisita != null)
      ('Recordar la visita', 'Hola$nombre, le recuerdo que quedamos en vernos$cuando para su crédito. ¡Le espero!'),
    ('Mensaje en blanco', 'Hola$nombre, '),
  ];
}
