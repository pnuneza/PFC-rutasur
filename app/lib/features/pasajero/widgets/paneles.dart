/// Paneles que se superponen al mapa: indicador de actualización (P-01 #3),
/// sin unidades en circulación (P-05) y ayuda con la leyenda (P-06).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/tema.dart';
import '../../../domain/geometria.dart';
import '../../../domain/modelos.dart';
import '../controlador_mapa.dart';
import 'etiqueta_estado.dart';

/// «Actualizado hace 8 s» en verde, o «Sin conexión» en rojo (P06, P-01 #3).
class IndicadorActualizacion extends StatefulWidget {
  const IndicadorActualizacion({super.key, required this.controlador});

  final ControladorMapa controlador;

  @override
  State<IndicadorActualizacion> createState() => _IndicadorActualizacionState();
}

class _IndicadorActualizacionState extends State<IndicadorActualizacion> {
  Timer? _tic;

  @override
  void initState() {
    super.initState();
    // Avanza el contador de segundos aunque no llegue un dato nuevo
    _tic = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tic?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controlador;
    if (c.sinConexion) {
      return const EtiquetaEstado(
        texto: 'Sin conexión',
        colorTexto: ColoresRutaSur.noConfiableTexto,
        colorFondo: ColoresRutaSur.noConfiableFondo,
        icono: Icons.cloud_off,
      );
    }
    final segundos = c.segundosDesdeActualizacion();
    if (segundos == null) return const SizedBox.shrink();
    final reciente = segundos <= 30;
    return EtiquetaEstado(
      texto: 'Actualizado hace $segundos s',
      colorTexto: reciente ? ColoresRutaSur.vigenteTexto : ColoresRutaSur.demoradoTexto,
      colorFondo: reciente ? ColoresRutaSur.vigenteFondo : ColoresRutaSur.demoradoFondo,
      icono: Icons.sync,
    );
  }
}

/// P-05: distingue la ausencia de servicio de una falla del sistema (RNF-04, RN-009).
class TarjetaSinUnidades extends StatelessWidget {
  const TarjetaSinUnidades({super.key, required this.horario, required this.alReintentar});

  final String horario;
  final VoidCallback alReintentar;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('No hay unidades en circulación', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text(
              'En este momento ningún conductor está transmitiendo. '
              'No es una falla de la aplicación.',
            ),
            const SizedBox(height: 4),
            Text(
              'Horario referencial: $horario',
              style: const TextStyle(color: ColoresRutaSur.textoSecundario),
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(onPressed: alReintentar, child: const Text('Volver a revisar')),
          ],
        ),
      ),
    );
  }
}

/// Líneas de la leyenda según lo que realmente se dibuja en el mapa (D-07).
///
/// Solo aparecen los ramales que tienen variantes activas, y el tramo común solo
/// si hay más de un ramal y la línea tiene paraderos compartidos. Antes la leyenda
/// era fija y seguía mostrando Cerrillo cuando ese ramal estaba desactivado.
List<({Color color, String texto})> entradasLeyenda(Linea? linea) {
  if (linea == null) return const [];
  final activos = {for (final v in linea.variantes) v.ramal};
  return [
    for (final ramal in Ramal.values)
      if (activos.contains(ramal)) (color: ColoresRutaSur.deRamal(ramal), texto: 'Ramal ${ramal.nombre}'),
    if (activos.length > 1 && tramoComun(linea) != null)
      (color: ColoresRutaSur.tramoComun, texto: 'Tramo común hasta 2 de Mayo'),
  ];
}

/// P-06 (parcial): leyenda del mapa y significado de los estados del dato.
Future<void> mostrarAyuda(BuildContext context, {required Linea? linea}) {
  final leyenda = entradasLeyenda(linea);
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('¿Cómo leer el mapa?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final e in leyenda) _Muestra(color: e.color, texto: e.texto),
            if (leyenda.isNotEmpty) const SizedBox(height: 12),
            const Text('Toca un paradero para ver qué unidades llegan y en cuántos minutos. '
                'Toca una unidad para ver su detalle.'),
            const SizedBox(height: 12),
            const Text('Estado del dato', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('Vigente: 30 segundos o menos.\n'
                'Demorado: entre 30 y 90 segundos.\n'
                'No confiable: más de 90 segundos.'),
            const SizedBox(height: 12),
            const Text('Privacidad', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('La aplicación no pide cuenta ni guarda datos personales. '
                'Tu ubicación nunca sale de tu teléfono.'),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Entendido')),
      ],
    ),
  );
}

class _Muestra extends StatelessWidget {
  const _Muestra({required this.color, required this.texto});

  final Color color;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(width: 28, height: 6, color: color),
          const SizedBox(width: 8),
          Flexible(child: Text(texto)),
        ],
      ),
    );
  }
}
