/// Piezas comunes del panel: contexto de la sesión, mensajes de error y diálogos.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/tema.dart';
import '../../domain/panel.dart';
import '../../domain/repositorio.dart';

/// Lo que toda pantalla del panel necesita: el servicio, la sesión y cómo cerrarla.
class ContextoPanel {
  const ContextoPanel({required this.servicio, required this.acceso, required this.alExpirar});

  final ServicioPanel servicio;
  final AccesoPanel acceso;

  /// El token venció o la cuenta se desactivó: vuelve a A-01 con un aviso.
  final void Function(String mensaje) alExpirar;

  /// Ejecuta una operación; si la sesión venció, vuelve al ingreso y devuelve null.
  Future<T?> ejecutar<T>(Future<T> Function(ServicioPanel s, AccesoPanel a) operacion) async {
    try {
      return await operacion(servicio, acceso);
    } on ErrorServicio catch (e) {
      if (e.estado == 401) {
        alExpirar('Tu sesión terminó. Vuelve a ingresar.');
        return null;
      }
      rethrow;
    }
  }
}

/// Mensaje claro para el usuario del panel, sin códigos técnicos.
String mensajeDeError(Object error) => switch (error) {
      SinConexion() =>
        'No hay conexión con el servicio. Si estaba apagado, tarda cerca de un minuto en despertar.',
      ErrorServicio(codigo: 'FORBIDDEN') => 'Tu rol no tiene permiso para esta acción.',
      ErrorServicio(:final mensaje) => mensaje,
      _ => 'Algo salió mal. Inténtalo de nuevo.',
    };

String dosDigitos(int n) => n.toString().padLeft(2, '0');

/// «01/11 08:05» en hora local.
String fechaHora(DateTime momento) {
  final l = momento.toLocal();
  return '${dosDigitos(l.day)}/${dosDigitos(l.month)} ${dosDigitos(l.hour)}:${dosDigitos(l.minute)}';
}

/// «hace 45 s», «hace 12 min», «hace 3 h», «hace 2 días».
String hace(DateTime momento, DateTime ahora) {
  final s = ahora.difference(momento).inSeconds;
  if (s < 60) return 'hace ${s < 0 ? 0 : s} s';
  if (s < 3600) return 'hace ${s ~/ 60} min';
  if (s < 86400) return 'hace ${s ~/ 3600} h';
  final dias = s ~/ 86400;
  return 'hace $dias ${dias == 1 ? 'día' : 'días'}';
}

/// Aviso de error dentro de una pantalla, con botón para reintentar.
class AvisoError extends StatelessWidget {
  const AvisoError({super.key, required this.mensaje, this.alReintentar});

  final String mensaje;
  final VoidCallback? alReintentar;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('aviso-error'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ColoresRutaSur.noConfiableFondo,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: ColoresRutaSur.noConfiableTexto),
          const SizedBox(width: 8),
          Expanded(child: Text(mensaje, style: const TextStyle(color: ColoresRutaSur.noConfiableTexto))),
          if (alReintentar != null)
            TextButton(onPressed: alReintentar, child: const Text('Reintentar')),
        ],
      ),
    );
  }
}

/// Confirmación para acciones que no se deshacen con un clic (P06 A-04 #3).
Future<bool> confirmar(
  BuildContext context, {
  required String titulo,
  required String mensaje,
  required String accion,
  bool peligrosa = false,
}) async {
  final respuesta = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(titulo),
      content: Text(mensaje),
      actions: [
        TextButton(
          key: const Key('cancelar'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('confirmar'),
          style: peligrosa ? FilledButton.styleFrom(backgroundColor: ColoresRutaSur.noConfiableTexto) : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(accion),
        ),
      ],
    ),
  );
  return respuesta ?? false;
}

/// Muestra la contraseña temporal una sola vez, con botón para copiarla (A-04 #4).
Future<void> mostrarClaveTemporal(BuildContext context, {required String usuario, required String clave}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('Contraseña temporal'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Usuario: $usuario'),
          const SizedBox(height: 12),
          SelectableText(
            clave,
            key: const Key('clave-temporal'),
            style: const TextStyle(fontSize: 24, fontFamily: 'monospace', fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          const Text(
            'Anótala o cópiala ahora: no se vuelve a mostrar. El servidor solo guarda una '
            'huella de la contraseña, así que nadie puede recuperarla después.',
            style: TextStyle(color: ColoresRutaSur.textoSecundario),
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: () => Clipboard.setData(ClipboardData(text: clave)),
          icon: const Icon(Icons.copy),
          label: const Text('Copiar'),
        ),
        FilledButton(
          key: const Key('cerrar-clave'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Ya la guardé'),
        ),
      ],
    ),
  );
}

/// Etiqueta de estado con color y texto (nunca solo color, WCAG).
class Etiqueta extends StatelessWidget {
  const Etiqueta({super.key, required this.texto, required this.colorTexto, required this.colorFondo});

  final String texto;
  final Color colorTexto;
  final Color colorFondo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: colorFondo, borderRadius: BorderRadius.circular(16)),
      child: Text(texto, style: TextStyle(color: colorTexto, fontWeight: FontWeight.w600)),
    );
  }
}

/// Título de pantalla con acciones a la derecha.
class EncabezadoPantalla extends StatelessWidget {
  const EncabezadoPantalla({super.key, required this.titulo, this.subtitulo, this.acciones = const []});

  final String titulo;
  final String? subtitulo;
  final List<Widget> acciones;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: Theme.of(context).textTheme.headlineSmall),
                if (subtitulo != null)
                  Text(subtitulo!, style: const TextStyle(color: ColoresRutaSur.textoSecundario)),
              ],
            ),
          ),
          Wrap(spacing: 8, runSpacing: 8, children: acciones),
        ],
      ),
    );
  }
}
