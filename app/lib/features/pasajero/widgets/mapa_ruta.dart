/// Mapa con el trazado, los paraderos y las unidades (P-01; RF-001, RF-002, RF-003).
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/tema.dart';
import '../../../domain/geometria.dart';
import '../../../domain/modelos.dart';
import 'marcadores.dart';

class MapaRuta extends StatelessWidget {
  const MapaRuta({
    super.key,
    required this.linea,
    required this.paraderos,
    required this.unidades,
    required this.atenuarUnidades,
    required this.alTocarParadero,
    required this.alTocarUnidad,
  });

  final Linea linea;
  final List<ParaderoEnMapa> paraderos;
  final List<UnidadActiva> unidades;
  final bool atenuarUnidades;
  final ValueChanged<ParaderoEnMapa> alTocarParadero;
  final ValueChanged<UnidadActiva> alTocarUnidad;

  @override
  Widget build(BuildContext context) {
    final puntos = [for (final v in linea.variantes) ...v.trazado];
    final limites = LatLngBounds.fromPoints(puntos);
    final comun = tramoComun(linea);

    return FlutterMap(
      options: MapOptions(
        initialCameraFit: CameraFit.bounds(
          bounds: limites,
          padding: const EdgeInsets.fromLTRB(32, 96, 32, 140),
        ),
        minZoom: 11,
        maxZoom: 18,
        // Desplazamiento limitado al corredor de la línea (P06, P-01 #4)
        cameraConstraint: CameraConstraint.containCenter(bounds: _ampliar(limites)),
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'pe.edu.ucsm.rutasur',
        ),
        PolylineLayer(
          polylines: [
            // Cada variante con el color de su ramal...
            for (final variante in linea.variantes)
              Polyline(
                points: variante.trazado,
                color: ColoresRutaSur.deRamal(variante.ramal),
                strokeWidth: 5,
              ),
            // ...y el tramo común encima, en gris pizarra (RF-001)
            if (comun != null)
              Polyline(points: comun, color: ColoresRutaSur.tramoComun, strokeWidth: 7),
          ],
        ),
        MarkerLayer(
          markers: [
            for (final paradero in paraderos)
              Marker(
                point: paradero.ubicacion,
                width: 36,
                height: 36,
                child: MarcadorParadero(
                  paradero: paradero,
                  alTocar: () => alTocarParadero(paradero),
                ),
              ),
          ],
        ),
        MarkerLayer(
          markers: [
            for (final unidad in unidades)
              Marker(
                point: unidad.ubicacion,
                width: MarcadorUnidad.ancho,
                height: MarcadorUnidad.alto,
                child: MarcadorUnidad(
                  unidad: unidad,
                  atenuada: atenuarUnidades,
                  alTocar: () => alTocarUnidad(unidad),
                ),
              ),
          ],
        ),
        // Atribución obligatoria por la política de uso de OpenStreetMap
        SimpleAttributionWidget(source: const Text('OpenStreetMap contributors')),
      ],
    );
  }

  /// Margen alrededor de la ruta para poder mover un poco el mapa.
  static LatLngBounds _ampliar(LatLngBounds b) => LatLngBounds(
        LatLng(b.south - 0.02, b.west - 0.02),
        LatLng(b.north + 0.02, b.east + 0.02),
      );
}
