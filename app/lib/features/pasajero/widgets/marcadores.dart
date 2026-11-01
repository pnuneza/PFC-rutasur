/// Marcadores del mapa: paraderos y unidades.
library;

import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/tema.dart';
import '../../../domain/modelos.dart';

/// Paradero: círculo blanco con el borde del color de su tramo (RF-001).
class MarcadorParadero extends StatelessWidget {
  const MarcadorParadero({
    super.key,
    required this.paradero,
    required this.alTocar,
    this.destacado = false,
  });

  final ParaderoEnMapa paradero;
  final VoidCallback alTocar;

  /// Paradero principal: un poco más grande, para ubicarse con el mapa alejado.
  final bool destacado;

  @override
  Widget build(BuildContext context) {
    final color = paradero.tramoComun || paradero.ramales.length > 1
        ? ColoresRutaSur.tramoComun
        : ColoresRutaSur.deRamal(paradero.ramales.first);
    return Semantics(
      button: true,
      label: 'Paradero ${paradero.nombre}. Toca para ver las próximas llegadas.',
      child: GestureDetector(
        onTap: alTocar,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: Container(
            width: destacado ? 24 : 18,
            height: destacado ? 24 : 18,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: color, width: destacado ? 6 : 4),
            ),
          ),
        ),
      ),
    );
  }
}

/// Unidad: flecha orientada según su rumbo (RF-002), con el color de su ramal
/// y una etiqueta con su número y su destino (RF-003). Se atenúa si el dato
/// no es confiable o si no hay conexión (RF-008).
class MarcadorUnidad extends StatelessWidget {
  const MarcadorUnidad({
    super.key,
    required this.unidad,
    required this.atenuada,
    required this.alTocar,
  });

  /// Tamaño del marcador. La flecha queda exactamente en el centro, sobre la posición.
  static const double ancho = 200; // cabe «07 → Centro (2 de Mayo)» a 16 sp
  static const double alto = 96;
  static const double _diametro = 36;

  final UnidadActiva unidad;
  final bool atenuada;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    final color = ColoresRutaSur.deRamal(unidad.ramal);
    final apagada = atenuada || unidad.frescura == Frescura.noConfiable;

    return Semantics(
      button: true,
      label: 'Unidad ${unidad.etiqueta}, va a ${unidad.destino}',
      child: GestureDetector(
        onTap: alTocar,
        child: Opacity(
          opacity: apagada ? 0.45 : 1,
          // Stack y no Column: con letra grande en el teléfono la etiqueta puede crecer
          // sin desbordar el marcador ni mover la flecha del centro (D-15).
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              Positioned(
                top: (alto - _diametro) / 2,
                child: Container(
                  width: _diametro,
                  height: _diametro,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
                  ),
                  child: Transform.rotate(
                    angle: (unidad.rumbo ?? 0) * pi / 180,
                    child: const Icon(Icons.navigation, color: Colors.white, size: 20),
                  ),
                ),
              ),
              Positioned(
                top: (alto + _diametro) / 2 + 2,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: ancho),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color),
                  ),
                  child: Text(
                    '${unidad.etiqueta} → ${unidad.destino}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w700),
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
