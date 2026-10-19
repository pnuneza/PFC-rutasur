import 'package:flutter/material.dart';

import '../../../core/tema.dart';
import '../../../domain/modelos.dart';
import '../formato.dart';

/// Etiqueta de color con texto: el estado nunca se comunica solo con color (WCAG).
class EtiquetaEstado extends StatelessWidget {
  const EtiquetaEstado({
    super.key,
    required this.texto,
    required this.colorTexto,
    required this.colorFondo,
    this.icono,
  });

  factory EtiquetaEstado.frescura(Frescura frescura, String texto, {Key? key}) {
    final colores = ColoresRutaSur.deFrescura(frescura);
    return EtiquetaEstado(
      key: key,
      texto: texto,
      colorTexto: colores.texto,
      colorFondo: colores.fondo,
      icono: switch (frescura) {
        Frescura.vigente => Icons.check_circle_outline,
        Frescura.demorado => Icons.schedule,
        Frescura.noConfiable => Icons.warning_amber_rounded,
      },
    );
  }

  final String texto;
  final Color colorTexto;
  final Color colorFondo;
  final IconData? icono;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: colorFondo, borderRadius: BorderRadius.circular(16)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icono != null) ...[
            Icon(icono, size: 16, color: colorTexto),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              texto,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colorTexto, fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// Destino con el color del ramal y el texto «Va a …» (P06, P-04 #2).
class EtiquetaDestino extends StatelessWidget {
  const EtiquetaDestino({super.key, required this.ramal, required this.destino});

  final Ramal ramal;
  final String destino;

  @override
  Widget build(BuildContext context) {
    final color = ColoresRutaSur.deRamal(ramal);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        textoDestino(destino),
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13),
      ),
    );
  }
}
