/// P-04 Detalle de la unidad (RF-002, RF-003, RF-008).
library;

import 'package:flutter/material.dart';

import '../../core/tema.dart';
import '../../domain/modelos.dart';
import 'formato.dart';
import 'widgets/etiqueta_estado.dart';

Future<void> mostrarUnidad(BuildContext context, UnidadActiva unidad) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => HojaUnidad(unidad: unidad),
  );
}

class HojaUnidad extends StatelessWidget {
  const HojaUnidad({super.key, required this.unidad});

  final UnidadActiva unidad;

  @override
  Widget build(BuildContext context) {
    final u = unidad;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Unidad ${u.etiqueta}', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          EtiquetaDestino(ramal: u.ramal, destino: u.destino),
          const SizedBox(height: 12),
          _Dato(nombre: 'Ramal', valor: u.ramal.nombre),
          _Dato(nombre: 'Sentido', valor: u.sentido.descripcion),
          _Dato(nombre: 'Última posición', valor: textoAntiguedad(u.antiguedadS)),
          const SizedBox(height: 8),
          EtiquetaEstado.frescura(u.frescura, textoFrescura(u.frescura, u.antiguedadS)),
          const SizedBox(height: 16),
          const Text(
            'Vigente: la posición tiene 30 segundos o menos. '
            'Demorado: tiene entre 30 y 90 segundos. '
            'No confiable: tiene más de 90 segundos; la unidad puede estar en otro lugar.',
            style: TextStyle(color: ColoresRutaSur.textoSecundario),
          ),
        ],
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato({required this.nombre, required this.valor});

  final String nombre;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(nombre, style: const TextStyle(color: ColoresRutaSur.textoSecundario)),
          ),
          Expanded(child: Text(valor, style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}
